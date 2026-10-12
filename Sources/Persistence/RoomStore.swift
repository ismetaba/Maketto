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

/// One room as the editor sees it: geometry + furniture in the home's
/// straightened DISPLAY frame, plus where it sits in its version history.
struct RoomDocument: Hashable, Sendable {
    let roomID: UUID
    let room: RoomModel
    let furniture: [PlacedFurniture]
    let versionID: UUID?
    /// 1-based position of the current version in chronological order.
    let versionNumber: Int
    let versionCount: Int
    let versionLabel: String
    /// Other rooms of the same home can be deleted without emptying it.
    let canDeleteRoom: Bool
}

/// One saved version of a room, for the history sheet (display frame).
struct VersionInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    let createdAt: Date
    /// 1-based, oldest = 1.
    let number: Int
    let isCurrent: Bool
    let room: RoomModel
    let furniture: [PlacedFurniture]
}

/// Hides SwiftData behind a small observable API.
///
/// Every committed mutation calls `refresh()`, which bumps `revision`; every
/// read API touches `revision`, so ANY view that reads through the store
/// re-renders after a change (e.g. the home map after a room edit).
@MainActor
@Observable
final class RoomStore {
    private let modelContext: ModelContext
    private(set) var homes: [HomeSummary] = []
    private(set) var revision = 0

    /// Decoded snapshots by version id. Payloads are immutable, so entries
    /// never go stale; they are evicted when their version is deleted.
    @ObservationIgnored private var snapshotCache: [UUID: VersionSnapshot] = [:]
    /// Keeps an owned container alive for in-memory stores (previews, tests).
    @ObservationIgnored private var ownedContainer: ModelContainer?

    init(modelContext: ModelContext, owning container: ModelContainer? = nil) {
        self.modelContext = modelContext
        self.ownedContainer = container
        refresh()
    }

    // MARK: - Reads

    func refresh() {
        let descriptor = FetchDescriptor<Home>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        homes = fetched.map { home in
            let pose = straighteningPose(of: home)
            let models = orderedRooms(of: home).compactMap { room -> RoomModel? in
                guard let snap = currentSnapshot(of: room) else { return nil }
                var rm = HomeGeometry.transform(snap.room, by: pose)
                rm.name = room.name
                return rm
            }
            let area = models.reduce(0.0) { $0 + PlanGeometry.area(of: $1) }
            return HomeSummary(id: home.id, name: home.name, createdAt: home.createdAt,
                               roomCount: models.count, totalArea: area, rooms: models)
        }
        revision &+= 1
    }

    func homeModel(for id: UUID) -> HomeModel? {
        _ = revision
        guard let home = home(with: id) else { return nil }
        let pose = straighteningPose(of: home)
        let placed = orderedRooms(of: home).compactMap { room -> PlacedRoom? in
            guard let version = room.currentVersion, let snap = snapshot(of: version) else { return nil }
            var rm = HomeGeometry.transform(snap.room, by: pose)
            rm.name = room.name                    // Room.name is the source of truth
            return PlacedRoom(id: room.id, name: room.name, kind: rm.kind,
                              sortIndex: room.sortIndex, room: rm,
                              furniture: HomeGeometry.transform(snap.furniture, by: pose),
                              placement: .identity, versionId: version.id)
        }
        return HomeModel(id: home.id, name: home.name, createdAt: home.createdAt, rooms: placed)
    }

    func document(for roomID: UUID) -> RoomDocument? {
        _ = revision
        guard let room = room(with: roomID), let current = room.currentVersion,
              let snap = snapshot(of: current) else { return nil }
        let pose = room.home.map { straighteningPose(of: $0) } ?? .identity
        var rm = HomeGeometry.transform(snap.room, by: pose)
        rm.name = room.name
        let chronological = room.versions.sorted(by: Self.chronological)
        let number = (chronological.firstIndex { $0.id == current.id } ?? 0) + 1
        return RoomDocument(
            roomID: room.id, room: rm,
            furniture: HomeGeometry.transform(snap.furniture, by: pose),
            versionID: current.id, versionNumber: number,
            versionCount: chronological.count, versionLabel: current.label,
            canDeleteRoom: (room.home?.rooms.count ?? 1) > 1
        )
    }

    func roomModel(for id: UUID) -> RoomModel? { document(for: id)?.room }

    /// The room's saved versions, NEWEST first, in the display frame.
    func versions(for roomID: UUID) -> [VersionInfo] {
        _ = revision
        guard let room = room(with: roomID) else { return [] }
        let pose = room.home.map { straighteningPose(of: $0) } ?? .identity
        let chronological = room.versions.sorted(by: Self.chronological)
        let infos = chronological.enumerated().compactMap { i, version -> VersionInfo? in
            guard let snap = snapshot(of: version) else { return nil }
            var rm = HomeGeometry.transform(snap.room, by: pose)
            rm.name = room.name
            return VersionInfo(id: version.id, label: version.label, createdAt: version.createdAt,
                               number: i + 1, isCurrent: version.id == room.currentVersion?.id,
                               room: rm, furniture: HomeGeometry.transform(snap.furniture, by: pose))
        }
        return Array(infos.reversed())
    }

    func modelURL(for id: UUID) -> URL? {
        guard let room = room(with: id), let path = currentSnapshot(of: room)?.usdzPath else { return nil }
        let url = Self.modelsDirectory.appending(path: path)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// True when any saved version still shows a piece with this photo.
    func isPhotoReferenced(_ photoID: String) -> Bool {
        let versions = (try? modelContext.fetch(FetchDescriptor<Version>())) ?? []
        return versions.contains { v in
            snapshot(of: v)?.furniture.contains { $0.photoID == photoID } ?? false
        }
    }

    // MARK: - Lookup helpers

    private func home(with id: UUID) -> Home? {
        let d = FetchDescriptor<Home>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(d).first
    }

    private func room(with id: UUID) -> Room? {
        let d = FetchDescriptor<Room>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(d).first
    }

    private func orderedRooms(of home: Home) -> [Room] {
        home.rooms.sorted {
            $0.sortIndex != $1.sortIndex ? $0.sortIndex < $1.sortIndex : $0.createdAt < $1.createdAt
        }
    }

    private static func chronological(_ a: Version, _ b: Version) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
    }

    private func snapshot(of version: Version) -> VersionSnapshot? {
        if let cached = snapshotCache[version.id] { return cached }
        guard let decoded = version.snapshot else { return nil }
        snapshotCache[version.id] = decoded
        return decoded
    }

    private func currentSnapshot(of room: Room) -> VersionSnapshot? {
        room.currentVersion.flatMap(snapshot(of:))
    }

    /// The whole home's straightening pose (raw scan frame → display frame).
    private func straighteningPose(of home: Home) -> Pose2D {
        HomeGeometry.straighteningPose(of: home.rooms.compactMap { currentSnapshot(of: $0)?.room })
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

        // Discards every pending insert of this call (nothing was saved yet).
        func abort() -> UUID? {
            modelContext.rollback()
            copied.forEach { removeModelFile($0) }
            return nil
        }

        for (i, rm) in rooms.enumerated() {
            let name = rm.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let room = Room(name: name.isEmpty ? "Oda \(i + 1)" : name, sortIndex: i)
            room.home = home
            home.rooms.append(room)

            var usdz: String?
            if let url = modelURLs[rm.id],
               FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                let dest = Self.modelsDirectory.appending(path: "\(room.id.uuidString).usdz")
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    usdz = dest.lastPathComponent
                    copied.append(dest.lastPathComponent)
                }
            }

            let snapshot = VersionSnapshot(room: rm, usdzPath: usdz)
            guard let payload = try? JSONEncoder().encode(snapshot), !payload.isEmpty else {
                return abort()
            }
            let version = Version(label: Self.versionLabel(1), payload: payload)
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
            return abort()
        }
        refresh()
        return home.id
    }

    /// Persist a hand-edited room (+ its furniture) as a NEW Version and make it
    /// current. The input is in the STRAIGHTENED display frame (as returned by
    /// `document(for:)`); it is converted back to the raw home frame so the
    /// stored snapshot stays consistent with every other room. Rolls back fully
    /// on failure. Returns false if nothing was saved.
    @discardableResult
    func saveEditedRoom(id: UUID, editedDisplayRoom: RoomModel,
                        furniture: [PlacedFurniture] = [], label: String? = nil) -> Bool {
        guard let room = room(with: id) else { return false }

        let inverse = (room.home.map { straighteningPose(of: $0) } ?? .identity).inverse
        let raw = HomeGeometry.transform(editedDisplayRoom, by: inverse)
        let rawFurniture = HomeGeometry.transform(furniture, by: inverse)

        let snapshot = VersionSnapshot(room: raw, furniture: rawFurniture,
                                       usdzPath: currentSnapshot(of: room)?.usdzPath)
        guard let payload = try? JSONEncoder().encode(snapshot), !payload.isEmpty else { return false }

        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let version = Version(label: trimmed.isEmpty ? nextVersionLabel(for: room) : trimmed,
                              payload: payload)
        version.room = room
        let previousCurrent = room.currentVersion
        room.versions.append(version)
        room.currentVersion = version
        modelContext.insert(version)

        do {
            try modelContext.save()
        } catch {
            room.versions.removeAll { $0.id == version.id }
            room.currentVersion = previousCurrent
            modelContext.rollback()
            return false
        }
        snapshotCache[version.id] = snapshot
        refresh()
        return true
    }

    /// Make an older version current again. Nothing is deleted; the version
    /// you leave stays in the history.
    @discardableResult
    func restoreVersion(roomID: UUID, versionID: UUID) -> Bool {
        guard let room = room(with: roomID),
              let target = room.versions.first(where: { $0.id == versionID }) else { return false }
        guard target.id != room.currentVersion?.id else { return true }
        let previous = room.currentVersion
        room.currentVersion = target
        do {
            try modelContext.save()
        } catch {
            room.currentVersion = previous
            modelContext.rollback()
            return false
        }
        refresh()
        return true
    }

    @discardableResult
    func renameVersion(roomID: UUID, versionID: UUID, to label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let room = room(with: roomID),
              let version = room.versions.first(where: { $0.id == versionID }) else { return false }
        let previous = version.label
        version.label = String(trimmed.prefix(60))
        do {
            try modelContext.save()
        } catch {
            version.label = previous
            modelContext.rollback()
            return false
        }
        refresh()
        return true
    }

    /// Delete a non-current version (the current one and the last one are kept).
    @discardableResult
    func deleteVersion(roomID: UUID, versionID: UUID) -> Bool {
        guard let room = room(with: roomID), room.versions.count > 1,
              room.currentVersion?.id != versionID,
              let version = room.versions.first(where: { $0.id == versionID }) else { return false }
        room.versions.removeAll { $0.id == versionID }
        modelContext.delete(version)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return false
        }
        snapshotCache[versionID] = nil
        refresh()
        return true
    }

    @discardableResult
    func renameRoom(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let room = room(with: id) else { return false }
        let previous = room.name
        room.name = String(trimmed.prefix(60))
        do {
            try modelContext.save()
        } catch {
            room.name = previous
            modelContext.rollback()
            return false
        }
        refresh()
        return true
    }

    @discardableResult
    func renameHome(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let home = home(with: id) else { return false }
        let previous = home.name
        home.name = String(trimmed.prefix(60))
        do {
            try modelContext.save()
        } catch {
            home.name = previous
            modelContext.rollback()
            return false
        }
        refresh()
        return true
    }

    /// Delete one room (and its history) from a home. The last room of a home
    /// is kept — delete the home instead.
    @discardableResult
    func deleteRoom(id: UUID) -> Bool {
        guard let room = room(with: id), let home = room.home, home.rooms.count > 1 else { return false }
        let versionIDs = room.versions.map(\.id)
        let paths = Set(room.versions.compactMap { snapshot(of: $0)?.usdzPath })
        home.rooms.removeAll { $0.id == id }
        modelContext.delete(room)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return false
        }
        versionIDs.forEach { snapshotCache[$0] = nil }
        paths.forEach { removeModelFile($0) }   // remove files only after the delete commits
        refresh()
        return true
    }

    @discardableResult
    func deleteHome(id: UUID) -> Bool {
        guard let home = home(with: id) else { return false }
        let versions = home.rooms.flatMap(\.versions)
        let paths = Set(versions.compactMap { snapshot(of: $0)?.usdzPath })
        let versionIDs = versions.map(\.id)
        modelContext.delete(home)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            return false
        }
        versionIDs.forEach { snapshotCache[$0] = nil }
        paths.forEach { removeModelFile($0) }   // remove files only after the delete commits
        refresh()
        return true
    }

    // MARK: - Version labels

    static func versionLabel(_ number: Int) -> String { "Sürüm \(number)" }

    /// "Sürüm N" for the next N not already used by this room.
    private func nextVersionLabel(for room: Room) -> String {
        let used = Set(room.versions.map(\.label))
        var n = room.versions.count + 1
        while used.contains(Self.versionLabel(n)) { n += 1 }
        return Self.versionLabel(n)
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

    static func inMemory() -> RoomStore {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // An in-memory store cannot fail to open short of a programming error.
        let container = try! ModelContainer(for: schema, configurations: [config])
        return RoomStore(modelContext: container.mainContext, owning: container)
    }

    static var preview: RoomStore {
        let store = inMemory()
        var living = RoomModel.mockLShaped
        living.name = "Salon"
        living.kind = .livingRoom
        var bedroom = HomeGeometry.transform(.mock, by: Pose2D(translation: Point2D(x: 5.2, z: 0)))
        bedroom.name = "Yatak Odası"
        bedroom.kind = .bedroom
        store.saveScannedHome([living, bedroom], homeName: "Daire 1")
        return store
    }
}
