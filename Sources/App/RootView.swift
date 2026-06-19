import SwiftUI

/// The single navigation host. One stack, one destination resolver.
struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            RoomListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .scan:
                        ScanScreen()
                    case .roomDetail(let id):
                        RoomDetailView(roomID: id)
                    }
                }
        }
    }
}
