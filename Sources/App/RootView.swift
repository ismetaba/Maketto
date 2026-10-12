import SwiftUI

/// The single navigation host. One stack, one destination resolver.
struct RootView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        #if DEBUG
        if DemoLaunch.is(.scanReview) {
            ScanReviewView(rooms: DemoContent.reviewRooms(), onSave: { _, _ in false },
                           onRescan: {}, onDiscard: {})
        } else {
            stack(router: $router.path)
        }
        #else
        stack(router: $router.path)
        #endif
    }

    private func stack(router path: Binding<[Route]>) -> some View {
        NavigationStack(path: path) {
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
