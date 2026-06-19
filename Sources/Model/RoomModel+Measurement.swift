import Foundation

/// One wall's measured length, for the F1 verification UI (tape-measure check).
struct WallMeasurement: Identifiable, Hashable, Sendable {
    /// Stable wall id, so the list keeps identity across refreshes.
    let id: UUID
    let label: String
    let meters: Double
    var centimeters: Double { meters * 100 }
}

extension RoomModel {
    /// Per-wall lengths for the F1 verification surface.
    var wallMeasurements: [WallMeasurement] {
        walls.enumerated().map { index, wall in
            WallMeasurement(id: wall.id, label: "Wall \(index + 1)", meters: wall.length)
        }
    }

    /// Sum of all wall lengths (meters) — a rough floor perimeter.
    var totalWallLength: Double {
        walls.reduce(0) { $0 + $1.length }
    }
}
