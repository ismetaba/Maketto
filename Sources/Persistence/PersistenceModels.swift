import Foundation
import SwiftData

// MARK: - Home

/// Top of the ownership graph. F0/F1 use a single implicit "My Home".
@Model
final class Home {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Room.home)
    var rooms: [Room]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.rooms = []
    }
}

// MARK: - Room

@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// For future manual ordering of rooms in a home.
    var sortIndex: Int

    /// Owner (inverse declared on Home.rooms). Set explicitly on insert.
    var home: Home?

    @Relationship(deleteRule: .cascade, inverse: \Version.room)
    var versions: [Version]

    /// Selection pointer into `versions` — NOT an owner, so .nullify and no inverse
    /// (cascade would delete a real snapshot; an inverse would create a cycle).
    @Relationship(deleteRule: .nullify)
    var currentVersion: Version?

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.versions = []
    }

    /// SwiftData relationship arrays are unordered; sort at read time.
    var versionsNewestFirst: [Version] {
        versions.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Version

/// One immutable snapshot of a room. The whole `VersionSnapshot` value type is
/// JSON-encoded into `payload`; the @Model schema only ever sees Data/Date/UUID,
/// so the domain types can evolve inside the Codable layer with no migration.
@Model
final class Version {
    @Attribute(.unique) var id: UUID
    var label: String
    var createdAt: Date

    @Attribute(.externalStorage) var payload: Data
    @Attribute(.externalStorage) var thumbnail: Data?

    /// Owner (inverse declared on Room.versions). Set explicitly on insert.
    var room: Room?

    init(
        id: UUID = UUID(),
        label: String,
        createdAt: Date = .now,
        payload: Data,
        thumbnail: Data? = nil
    ) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.payload = payload
        self.thumbnail = thumbnail
    }
}

extension Version {
    /// Transient (computed, non-persistent) decode of the stored snapshot.
    var snapshot: VersionSnapshot? {
        try? JSONDecoder().decode(VersionSnapshot.self, from: payload)
    }
}
