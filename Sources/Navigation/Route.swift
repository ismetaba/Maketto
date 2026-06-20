import Foundation

/// Type-safe navigation destinations. Homes and rooms are navigated by id (UUID).
enum Route: Hashable {
    case scanHome
    case homeDetail(UUID)
    case roomDetail(UUID)
}
