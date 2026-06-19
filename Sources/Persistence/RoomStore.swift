import Foundation
import SwiftData
import Observation

/// Lightweight value summary for list cells — views never touch @Model objects.
struct RoomSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let wallCount: Int
    let thumbnail: Data?
}

/// Hides SwiftData behind a small observable API. `rooms` is a stored,
/// observable property refreshed after every mutation so SwiftUI updates.
@MainActor
@Observable
final class RoomStore {
    private let modelContext: ModelContext

    private(set) var rooms: [RoomSummary] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _ = defaultHome          // ensure a home exists
        refresh()
    }

    // MARK: - Reads

    func refresh() {
        let descriptor = FetchDescriptor<Room>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        rooms = fetched.map { room in
            let model = room.currentVersion?.snapshot?.room
            return RoomSummary(
                id: room.id,
                name: room.name,
                createdAt: room.createdAt,
                wallCount: model?.walls.count ?? 0,
                thumbnail: room.currentVersion?.thumbnail
            )
        }
    }

    func roomModel(for id: UUID) -> RoomModel? {
        room(with: id)?.currentVersion?.snapshot?.room
    }

    private func room(with id: UUID) -> Room? {
        let descriptor = FetchDescriptor<Room>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Writes

    /// Persist a freshly scanned room as a new Room + its initial Version.
    /// `modelURL` is the temporary exported USDZ, copied into permanent storage.
    /// Returns nil (and persists nothing) if the snapshot can't be encoded or the
    /// write fails — the caller surfaces an error instead of storing a phantom room.
    @discardableResult
    func saveScannedRoom(_ roomModel: RoomModel, name: String, modelURL: URL? = nil) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomName = trimmed.isEmpty ? roomModel.name : trimmed
        let room = Room(name: roomName)

        // Copy the scan's 3D model into permanent storage, keyed by room id.
        var usdzPath: String?
        if let modelURL, FileManager.default.fileExists(atPath: modelURL.path(percentEncoded: false)) {
            let dest = Self.modelsDirectory.appending(path: "\(room.id.uuidString).usdz")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: modelURL, to: dest)) != nil {
                usdzPath = dest.lastPathComponent
            }
        }

        // Encode FIRST: never persist a Version we can't round-trip.
        let snapshot = VersionSnapshot(room: roomModel, usdzPath: usdzPath)
        guard let payload = try? JSONEncoder().encode(snapshot), !payload.isEmpty else {
            removeModelFile(usdzPath)
            return nil
        }

        let home = defaultHome
        room.home = home
        home.rooms.append(room)

        let version = Version(label: "Version 1", payload: payload)
        version.room = room
        room.versions.append(version)
        room.currentVersion = version

        modelContext.insert(room)
        modelContext.insert(version)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            removeModelFile(usdzPath)
            return nil
        }
        refresh()
        return room.id
    }

    func deleteRoom(id: UUID) {
        guard let room = room(with: id) else { return }
        removeModelFile(room.currentVersion?.snapshot?.usdzPath)
        modelContext.delete(room)
        try? modelContext.save()
        refresh()
    }

    /// Absolute URL of a saved room's USDZ model, if one exists on disk.
    func modelURL(for id: UUID) -> URL? {
        guard let path = room(with: id)?.currentVersion?.snapshot?.usdzPath else { return nil }
        let url = Self.modelsDirectory.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    // MARK: - Model file storage

    private static var modelsDirectory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "RoomModels", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func removeModelFile(_ relativePath: String?) {
        guard let relativePath else { return }
        try? FileManager.default.removeItem(at: Self.modelsDirectory.appending(path: relativePath))
    }

    // MARK: - Default home

    private var defaultHome: Home {
        if let existing = try? modelContext.fetch(FetchDescriptor<Home>()).first {
            return existing
        }
        let home = Home(name: "My Home")
        modelContext.insert(home)
        try? modelContext.save()
        return home
    }

    // MARK: - Preview / tests

    /// In-memory store seeded with a mock room — drives previews and CI with no device.
    static var preview: RoomStore {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Previews are non-throwing contexts; a failure here is a programmer error.
        let container = try! ModelContainer(for: schema, configurations: [config])
        let store = RoomStore(modelContext: container.mainContext)
        store.saveScannedRoom(.mock, name: "Living Room")
        return store
    }
}
