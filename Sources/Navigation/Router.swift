import Observation

/// Owns the single NavigationStack path so the scanner can programmatically
/// pop to root and push the new room's detail after a save.
@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
