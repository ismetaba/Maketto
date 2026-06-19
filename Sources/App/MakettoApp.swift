import SwiftUI
import SwiftData

@main
struct MakettoApp: App {
    private let modelContainer: ModelContainer
    @State private var router = Router()
    @State private var roomStore: RoomStore

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.modelContainer = container
        _roomStore = State(initialValue: RoomStore(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(roomStore)
        }
        .modelContainer(modelContainer)
    }
}
