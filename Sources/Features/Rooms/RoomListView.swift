import SwiftUI

/// F0 home screen: the list of scanned rooms, with a button to start a scan.
struct RoomListView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if store.rooms.isEmpty {
                ContentUnavailableView {
                    Label("No Rooms Yet", systemImage: "camera.viewfinder")
                } description: {
                    Text("Scan a room to capture its dimensions.")
                } actions: {
                    Button("Scan a Room") { router.push(.scan) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(store.rooms) { summary in
                        NavigationLink(value: Route.roomDetail(summary.id)) {
                            RoomRow(summary: summary)
                        }
                    }
                    .onDelete(perform: deleteRooms)
                }
            }
        }
        .navigationTitle("Rooms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.push(.scan)
                } label: {
                    Label("Scan Room", systemImage: "plus")
                }
            }
        }
    }

    private func deleteRooms(at offsets: IndexSet) {
        // Snapshot ids BEFORE deleting: each delete refreshes (reassigns) the
        // rooms array, so indexing it mid-loop would delete the wrong row / crash.
        let ids = offsets.map { store.rooms[$0].id }
        for id in ids {
            store.deleteRoom(id: id)
        }
    }
}

#Preview {
    NavigationStack {
        RoomListView()
    }
    .environment(RoomStore.preview)
    .environment(Router())
}
