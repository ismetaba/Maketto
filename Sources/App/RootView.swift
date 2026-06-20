import SwiftUI

/// The single navigation host. One stack, one destination resolver.
struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .scanHome:
                        HomeScanScreen()
                    case .homeDetail(let id):
                        HomeDetailView(homeID: id)
                    case .roomDetail(let id):
                        RoomDetailView(roomID: id)
                    }
                }
        }
    }
}
