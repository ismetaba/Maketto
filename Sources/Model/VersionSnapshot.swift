import Foundation

/// Immutable snapshot persisted (JSON-encoded) into `Version.payload`.
/// Editing always produces a NEW snapshot/version; stored bytes are never mutated.
struct VersionSnapshot: Codable, Hashable, Sendable {
    /// Bumped when the Codable shape changes; lets us migrate inside the
    /// Codable layer without a SwiftData schema migration.
    var schemaVersion: Int
    var room: RoomModel
    /// Populated by the furniture-placement milestone. Empty today.
    var furniture: [PlacedFurniture]
    /// Populated by the Gemini render milestone. Empty today.
    var renders: [RenderImageRef]
    /// Filename of the exported RoomPlan USDZ model in the app's models
    /// directory (nil if export failed or none captured).
    var usdzPath: String?

    init(
        schemaVersion: Int = VersionSnapshot.currentSchemaVersion,
        room: RoomModel,
        furniture: [PlacedFurniture] = [],
        renders: [RenderImageRef] = [],
        usdzPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.room = room
        self.furniture = furniture
        self.renders = renders
        self.usdzPath = usdzPath
    }

    static let currentSchemaVersion = 1
}

/// Placeholder for the furniture-placement milestone. Forward-valid default ([]).
struct PlacedFurniture: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// Footprint center on the floor plane, meters.
    var center: Point2D
    var width: Double
    var depth: Double
    /// Yaw in radians.
    var rotation: Double

    init(
        id: UUID = UUID(),
        name: String,
        center: Point2D,
        width: Double,
        depth: Double,
        rotation: Double = 0
    ) {
        self.id = id
        self.name = name
        self.center = center
        self.width = width
        self.depth = depth
        self.rotation = rotation
    }
}

/// Reference to a generated render image stored on disk (Gemini milestone).
/// Only the relative path lives in the snapshot; the bytes live in the app's
/// render directory so multi-MB images stay out of the store.
struct RenderImageRef: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// Path relative to the app's render directory.
    var relativePath: String
    var createdAt: Date

    init(id: UUID = UUID(), relativePath: String, createdAt: Date = .now) {
        self.id = id
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}
