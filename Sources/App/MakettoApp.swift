import SwiftUI
import SwiftData

@main
struct MakettoApp: App {
    private let modelContainer: ModelContainer
    @State private var router = Router()
    @State private var roomStore: RoomStore
    @State private var furnitureLibrary = FurnitureLibrary()
    @State private var showStoreAlert: Bool
    /// False when running on the temporary fallback store.
    private let storeIsPersistent: Bool

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        #if DEBUG
        if DemoLaunch.isActive {
            // Screenshot / UI-review launch: throw-away store, seeded content.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [memory])
            let store = RoomStore(modelContext: container.mainContext, owning: container)
            let library = FurnitureLibrary(fileURL: nil)
            let router = Router()
            if !DemoLaunch.is(.empty) {
                let seeded = DemoContent.seed(store, library: library)
                if let home = seeded.homeID, let room = seeded.roomID {
                    switch DemoLaunch.screen {
                    case .home, .homeRoom, .home3D:
                        router.path = [.homeDetail(home)]
                    case .room, .room3D, .edit, .editFurniture, .editWall, .catalog, .creator, .versions:
                        router.path = [.homeDetail(home), .roomDetail(room)]
                    case .scan:
                        router.path = [.scanHome]
                    default:
                        break
                    }
                }
            }
            modelContainer = container
            storeIsPersistent = false
            _showStoreAlert = State(initialValue: false)
            _roomStore = State(initialValue: store)
            _furnitureLibrary = State(initialValue: library)
            _router = State(initialValue: router)
            return
        }
        #endif
        let container: ModelContainer
        var failed = false
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Never crash-loop on launch: keep the user's file as-is and run on
            // a temporary store so the app stays usable.
            failed = true
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // An in-memory store cannot fail to open short of a programming error.
            container = try! ModelContainer(for: schema, configurations: [memory])
        }
        self.modelContainer = container
        // Shown once when the on-disk store could not be opened and the app runs
        // on a temporary in-memory store instead (the file is left untouched).
        _showStoreAlert = State(initialValue: failed)
        storeIsPersistent = !failed
        _roomStore = State(initialValue: RoomStore(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(roomStore)
                .environment(furnitureLibrary)
                .tint(Brand.clay)
                .task {
                    // Sweep furniture photos nothing shows any more. Never on
                    // the fallback store, which would see no references.
                    guard storeIsPersistent else { return }
                    FurniturePhotoStore.removeUnreferenced(
                        keeping: roomStore.referencedPhotoIDs().union(furnitureLibrary.photoIDs))
                }
                .alert("Kayıtlı evler açılamadı", isPresented: $showStoreAlert) {
                    Button("Tamam", role: .cancel) {}
                } message: {
                    Text("Verileriniz silinmedi. Bu oturumda yaptığınız değişiklikler kaydedilmeyecek; lütfen uygulamayı güncelleyip yeniden açın.")
                }
        }
        .modelContainer(modelContainer)
    }
}
