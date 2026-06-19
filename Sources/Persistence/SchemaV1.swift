import SwiftData

/// Versioned schema from day one so future lightweight migrations are explicit.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Home.self, Room.self, Version.self]
    }
}
