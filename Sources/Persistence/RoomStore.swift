import Foundation
import SwiftData
import Observation

/// Lightweight value summary for the home library — views never touch @Model rows.
struct HomeSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let roomCount: Int
    let totalArea: Double
    /// Rooms in the shared home frame, for the whole-home thumbnail.
    let rooms: [RoomModel]
}

/// Hides SwiftData behind a small observable API. `homes` is a stored, observable
/// property refreshed after every mutation so SwiftUI updates.
@MainActor
@Observable
final class RoomStore {
    private let modelContext: ModelContext
    private(set) var homes: [HomeSummary] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        refresh()
    }

    // MARK: - Reads

    func refresh() {
        let descriptor = FetchDescriptor<Home>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        homes = fetched.map { home in
            let raw = home.rooms
                .sorted { $0.sortIndex < $1.sortIndex }
                .compactMap { room -> RoomModel? in
                    guard var rm = room.currentVersion?.snapshot?.room else { return nil }
                    rm.name = room.name
                    return rm
                }
            let models = HomeGeometry.straightened(raw)
            let area = models.reduce(0.0) { $0 + PlanGeometry.area(of: $1) }
            return HomeSummary(id: home.id, name: home.name, createdAt: home.createdAt,
                               roomCount: models.count, totalArea: area, rooms: models)
        }
    }

    func homeModel(for id: UUID) -> HomeModel? {
        guard let home = home(with: id) else { return nil }
        let entries = home.rooms
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { room -> (Room, RoomModel)? in
                guard var rm = room.currentVersion?.snapshot?.room else { return nil }
                rm.name = room.name                    // Room.name is the source of truth
                return (room, rm)
            }
        let straight = HomeGeometry.straightened(entries.map { $0.1 })
        let placed = zip(entries, straight).map { entry, geom in
            PlacedRoom(id: entry.0.id, name: entry.0.name, kind: geom.kind,
                       sortIndex: entry.0.sortIndex, room: geom, placement: .identity,
                       versionId: entry.0.currentVersion?.id)
        }
        return HomeModel(id: home.id, name: home.name, createdAt: home.createdAt, rooms: placed)
    }

    func roomModel(for id: UUID) -> RoomModel? {
        guard let room = room(with: id), var rm = room.currentVersion?.snapshot?.room else { return nil }
        rm.name = room.name
        // Apply the home's straightening so a single room reads upright too.
        if let home = room.home {
            let homeRooms = home.rooms.compactMap { $0.currentVersion?.snapshot?.room }
            return HomeGeometry.transform(rm, by: HomeGeometry.straighteningPose(of: homeRooms))
        }
        return rm
    }

    func modelURL(for id: UUID) -> URL? {
        guard let path = room(with: id)?.currentVersion?.snapshot?.usdzPath else { return nil }
        let url = Self.modelsDirectory.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func home(with id: UUID) -> Home? {
        let d = FetchDescriptor<Home>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(d).first
    }

    private func room(with id: UUID) -> Room? {
        let d = FetchDescriptor<Room>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(d).first
    }

    // MARK: - Writes

    /// Persist a whole-home scan: ONE Home + N Rooms, each with an initial Version.
    /// All-or-nothing — returns nil and persists nothing on any failure.
    @discardableResult
    func saveScannedHome(_ rooms: [RoomModel], homeName: String,
                         modelURLs: [UUID: URL] = [:]) -> UUID? {
        guard !rooms.isEmpty else { return nil }
        let trimmed = homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = Home(name: trimmed.isEmpty ? "Evim" : trimmed)
        var copied: [String] = []

        for (i, rm) in rooms.enumerated() {
            let room = Room(name: rm.name.isEmpty ? "Oda \(i + 1)" : rm.name, sortIndex: i)
            room.home = home
            home.rooms.append(room)

            var usdz: String?
            if let url = modelURLs[rm.id],
               FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                let dest = Self.modelsDirectory.appending(path: "\(room.id.uuidString).usdz")
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    usdz = dest.lastPathComponent
                    copied.append(usdz!)
                }
            }

            let snapshot = VersionSnapshot(room: rm, usdzPath: usdz)
            guard let payload = try? JSONEncoder().encode(snapshot), !payload.isEmpty else {
                modelContext.rollback()
                copied.forEach { removeModelFile($0) }
                return nil
            }
            let version = Version(label: "Version 1", payload: payload)
            version.room = room
            room.versions.append(version)
            room.currentVersion = version
            modelContext.insert(room)
            modelContext.insert(version)
        }

        modelContext.insert(home)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            copied.forEach { removeModelFile($0) }
            return nil
        }
        refresh()
        return home.id
    }

    func renameRoom(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let room = room(with: id) else { return }
        room.name = trimmed
        do { try modelContext.save() } catch { modelContext.rollback(); return }
        refresh()
    }

    func deleteHome(id: UUID) {
        guard let home = home(with: id) else { return }
        let paths = home.rooms.compactMap { $0.currentVersion?.snapshot?.usdzPath }
        modelContext.delete(home)
        do { try modelContext.save() } catch { modelContext.rollback(); return }
        paths.forEach { removeModelFile($0) }   // remove files only after the delete commits
        refresh()
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

    // MARK: - Preview / tests

    static var preview: RoomStore {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let store = RoomStore(modelContext: container.mainContext)
        let rooms = [
            RoomModel.mockLShaped,
            HomeGeometry.transform(.mock, by: Pose2D(translation: Point2D(x: 5.2, z: 0)))
        ]
        store.saveScannedHome(rooms, homeName: "Daire 1")
        return store
    }
}
