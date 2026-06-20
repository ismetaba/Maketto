import Foundation

/// Rigid 2D transform in the XZ floor plane (no scale — metric, never rescaled).
/// `rotation` is yaw about +Y from +X toward +Z, matching DetectedObject.rotation.
public struct Pose2D: Codable, Hashable, Sendable {
    public var rotation: Double
    public var translation: Point2D

    public init(rotation: Double = 0, translation: Point2D = .init(x: 0, z: 0)) {
        self.rotation = rotation
        self.translation = translation
    }

    public static let identity = Pose2D()

    public func apply(to p: Point2D) -> Point2D {
        let c = cos(rotation), s = sin(rotation)
        return Point2D(x: c * p.x - s * p.z + translation.x,
                       z: s * p.x + c * p.z + translation.z)
    }

    /// The inverse rigid transform: `inverse.apply(apply(p)) == p`.
    public var inverse: Pose2D {
        let c = cos(rotation), s = sin(rotation)
        // R(-a)·t
        let rx = c * translation.x + s * translation.z
        let rz = -s * translation.x + c * translation.z
        return Pose2D(rotation: -rotation, translation: Point2D(x: -rx, z: -rz))
    }
}

/// Pure helpers to re-express a whole room in another frame. Lengths/widths are
/// rigid-invariant; only positions and yaw change. Opening.offset is along a wall,
/// so openings are untouched.
public enum HomeGeometry {
    public static func transform(_ room: RoomModel, by pose: Pose2D) -> RoomModel {
        if pose == .identity { return room }
        var out = room
        out.walls = room.walls.map {
            var w = $0
            w.start = pose.apply(to: w.start)
            w.end = pose.apply(to: w.end)
            return w
        }
        out.detectedObjects = room.detectedObjects.map {
            var o = $0
            o.center = pose.apply(to: o.center)
            o.rotation += pose.rotation
            return o
        }
        out.floorOutline = room.floorOutline?.map(pose.apply(to:))
        return out
    }

    /// Dominant wall skew of a set of rooms, radians in [-π/4, π/4]. Length-weighted
    /// circular mean over the 90°-periodic wall orientation (×4 → full circle → /4).
    public static func dominantAngle(of rooms: [RoomModel]) -> Double {
        var sx = 0.0, sy = 0.0
        for room in rooms {
            for wall in room.walls {
                let d = wall.end - wall.start
                let len = d.length
                guard len > 1e-6 else { continue }
                let a = atan2(d.z, d.x) * 4
                sx += len * cos(a)
                sy += len * sin(a)
            }
        }
        if sx == 0, sy == 0 { return 0 }
        return atan2(sy, sx) / 4
    }

    /// Bounding-box centre of all wall endpoints across the rooms.
    public static func bboxCenter(of rooms: [RoomModel]) -> Point2D {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minZ = minX, maxZ = maxX
        for room in rooms {
            for wall in room.walls {
                for p in [wall.start, wall.end] {
                    minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
                    minZ = Swift.min(minZ, p.z); maxZ = Swift.max(maxZ, p.z)
                }
            }
        }
        guard minX <= maxX else { return Point2D(x: 0, z: 0) }
        return Point2D(x: (minX + maxX) / 2, z: (minZ + maxZ) / 2)
    }

    /// Rigid pose that rotates a home about its centre so walls align to the axes.
    public static func straighteningPose(of rooms: [RoomModel]) -> Pose2D {
        let theta = dominantAngle(of: rooms)
        guard abs(theta) > 1e-4 else { return .identity }
        let c = bboxCenter(of: rooms)
        let a = -theta
        let rc = Pose2D(rotation: a).apply(to: c)   // R_a(c)
        return Pose2D(rotation: a, translation: Point2D(x: c.x - rc.x, z: c.z - rc.z))
    }

    /// Rooms re-expressed with the whole home straightened to the wall axes.
    public static func straightened(_ rooms: [RoomModel]) -> [RoomModel] {
        let pose = straighteningPose(of: rooms)
        if pose == .identity { return rooms }
        return rooms.map { transform($0, by: pose) }
    }
}

/// One room placed within a home, with its source version. Pure; assembled on read.
public struct PlacedRoom: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID            // == Room.id
    public var name: String
    public var kind: RoomKind?
    public var sortIndex: Int
    public var room: RoomModel     // geometry (home-world frame in slice 1)
    public var placement: Pose2D   // R_i -> H ; .identity in slice 1
    public var versionId: UUID?

    public init(id: UUID, name: String, kind: RoomKind?, sortIndex: Int,
                room: RoomModel, placement: Pose2D = .identity, versionId: UUID? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sortIndex = sortIndex
        self.room = room
        self.placement = placement
        self.versionId = versionId
    }

    /// The room geometry expressed in the home frame.
    public var roomInHomeFrame: RoomModel { HomeGeometry.transform(room, by: placement) }
}

/// A whole home = many placed rooms in one coordinate frame. Transient aggregate
/// (never a SwiftData row); assembled from Home + each Room's current/chosen Version.
public struct HomeModel: Codable, Hashable, Identifiable, Sendable {
    public var schemaVersion: Int
    public let id: UUID            // == Home.id
    public var name: String
    public var createdAt: Date
    public var rooms: [PlacedRoom]

    public init(id: UUID, name: String, createdAt: Date = .now,
                rooms: [PlacedRoom], schemaVersion: Int = HomeModel.currentSchemaVersion) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.rooms = rooms
        self.schemaVersion = schemaVersion
    }

    public static let currentSchemaVersion = 1

    public var orderedRooms: [PlacedRoom] {
        rooms.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Every room's geometry in the shared home frame — feed straight to the plan.
    public var roomsInHomeFrame: [RoomModel] {
        orderedRooms.map(\.roomInHomeFrame)
    }
}
