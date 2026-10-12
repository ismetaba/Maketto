import SwiftUI
import SwiftData

@main
struct MakettoApp: App {
    private let modelContainer: ModelContainer
    @State private var router = Router()
    @State private var roomStore: RoomStore
    @State private var furnitureLibrary = FurnitureLibrary()
    @State private var showStoreAlert: Bool

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)
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
        _roomStore = State(initialValue: RoomStore(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(roomStore)
                .environment(furnitureLibrary)
                .tint(Brand.clay)
                .alert("Kayıtlı evler açılamadı", isPresented: $showStoreAlert) {
                    Button("Tamam", role: .cancel) {}
                } message: {
                    Text("Verileriniz silinmedi. Bu oturumda yaptığınız değişiklikler kaydedilmeyecek; lütfen uygulamayı güncelleyip yeniden açın.")
                }
        }
        .modelContainer(modelContainer)
    }
}
