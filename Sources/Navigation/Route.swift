import Foundation

/// Type-safe navigation destinations. Rooms are navigated by id (UUID),
/// never by value, so the stack stays valid across store refreshes.
enum Route: Hashable {
    case scan
    case roomDetail(UUID)

    // Reserved for later milestones (extension points):
    // case planEditor(UUID)
    // case versionHistory(UUID)
}
