import Foundation

/// Immutable snapshot persisted (JSON-encoded) into `Version.payload`.
/// Editing always produces a NEW snapshot/version; stored bytes are never mutated.
struct VersionSnapshot: Codable, Hashable, Sendable {
    /// Bumped when the Codable shape changes; lets us migrate inside the
    /// Codable layer without a SwiftData schema migration.
    var schemaVersion: Int
    var room: RoomModel
    /// Furniture placed by the user, in the same frame as `room`.
    var furniture: [PlacedFurniture]
    /// Populated by the AI render milestone. Empty today.
    var renders: [RenderImageRef]
    /// Filename of an exported RoomPlan USDZ model in the app's models
    /// directory (nil if none was captured).
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

    static let currentSchemaVersion = 2

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, room, furniture, renders, usdzPath
    }

    /// Only `room` is required: every other field decodes with a default, so a
    /// snapshot written by an older (or newer) build never fails to load —
    /// a failed decode would make the room silently disappear.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        room = try c.decode(RoomModel.self, forKey: .room)
        furniture = (try? c.decodeIfPresent([PlacedFurniture].self, forKey: .furniture)) ?? []
        renders = (try? c.decodeIfPresent([RenderImageRef].self, forKey: .renders)) ?? []
        usdzPath = try c.decodeIfPresent(String.self, forKey: .usdzPath)
    }
}

/// Reference to a generated render image stored on disk (AI render milestone).
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
