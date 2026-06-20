import Foundation
import simd

// MARK: - Point2D

/// A point on the floor plane, in METERS.
/// `x` and `z` are the two horizontal world axes. RoomPlan/ARKit are Y-up,
/// so the floor is the XZ plane and we drop world Y entirely.
public struct Point2D: Codable, Hashable, Sendable {
    public var x: Double
    public var z: Double

    public init(x: Double, z: Double) {
        self.x = x
        self.z = z
    }
}

public extension Point2D {
    /// Build from a world-space simd position by dropping Y.
    init(droppingYFrom v: SIMD3<Float>) {
        self.init(x: Double(v.x), z: Double(v.z))
    }

    static func + (l: Point2D, r: Point2D) -> Point2D { .init(x: l.x + r.x, z: l.z + r.z) }
    static func - (l: Point2D, r: Point2D) -> Point2D { .init(x: l.x - r.x, z: l.z - r.z) }
    static func * (p: Point2D, s: Double) -> Point2D { .init(x: p.x * s, z: p.z * s) }

    var length: Double { (x * x + z * z).squareRoot() }
    func distance(to o: Point2D) -> Double { (self - o).length }
    func midpoint(to o: Point2D) -> Point2D { (self + o) * 0.5 }
    func dot(_ o: Point2D) -> Double { x * o.x + z * o.z }
}

// MARK: - Units / provenance

public enum LengthUnit: String, Codable, Sendable {
    /// Storage is ALWAYS meters; display conversions live in the UI layer.
    case meters
}

public enum RoomSource: String, Codable, Sendable {
    case roomplan
    case manual
}

/// Room category. Mirrors RoomPlan's `CapturedRoom.Section.Label` plus a couple
/// of manual kinds; drives default names and the whole-home plan's floor fills.
public enum RoomKind: String, Codable, Sendable, CaseIterable {
    case livingRoom
    case bedroom
    case bathroom
    case kitchen
    case diningRoom
    case hallway
    case balcony
    case unidentified
}

// MARK: - Wall

public struct Wall: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Floor-plane endpoints, meters. start->end defines the 1D parameter axis
    /// used to place openings (offset 0 == start).
    public var start: Point2D
    public var end: Point2D
    /// Wall thickness in meters (Apple dimensions.z).
    public var thickness: Double
    /// Wall height in meters (Apple dimensions.y).
    public var height: Double

    public init(
        id: UUID = UUID(),
        start: Point2D,
        end: Point2D,
        thickness: Double = 0.1,
        height: Double = 2.4
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.thickness = thickness
        self.height = height
    }

    /// Floor length of the wall, meters. (The value the F1 verification UI shows.)
    public var length: Double { start.distance(to: end) }

    /// Unit direction start->end on the floor.
    public var direction: Point2D {
        let d = end - start
        let len = d.length
        return len > 0 ? d * (1.0 / len) : .init(x: 1, z: 0)
    }

    /// Point at a given offset (meters) from `start` along the wall.
    public func point(atOffset offset: Double) -> Point2D {
        start + direction * offset
    }
}

// MARK: - Opening

public struct Opening: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case door
        case window
        case opening   // doorless aperture / pass-through
    }

    public let id: UUID
    public var type: Kind
    /// Which wall this opening is cut into.
    public var onWallId: UUID
    /// Distance in meters from the wall's `start` to the opening CENTER,
    /// measured along the wall direction.
    public var offset: Double
    /// Opening width in meters (along the wall).
    public var width: Double
    /// Opening height in meters.
    public var height: Double
    /// Sill height above floor, meters. nil for doors / full openings.
    public var sillHeight: Double?

    public init(
        id: UUID = UUID(),
        type: Kind,
        onWallId: UUID,
        offset: Double,
        width: Double,
        height: Double,
        sillHeight: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.onWallId = onWallId
        self.offset = offset
        self.width = width
        self.height = height
        self.sillHeight = sillHeight
    }
}

// MARK: - DetectedObject

public struct DetectedObject: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    /// Mirror of RoomPlan's object category as a String, for forward-compat
    /// with new SDK categories without a migration.
    public var category: String
    /// Center on the floor plane, meters.
    public var center: Point2D
    /// Footprint width (local X), meters.
    public var width: Double
    /// Footprint depth (local Z), meters.
    public var depth: Double
    /// Object height (local Y), meters.
    public var height: Double
    /// Yaw about world +Y, radians, from world +X toward +Z.
    public var rotation: Double

    public init(
        id: UUID = UUID(),
        category: String,
        center: Point2D,
        width: Double,
        depth: Double,
        height: Double,
        rotation: Double
    ) {
        self.id = id
        self.category = category
        self.center = center
        self.width = width
        self.depth = depth
        self.height = height
        self.rotation = rotation
    }
}

// MARK: - RoomModel (the portable aggregate)

public struct RoomModel: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var unit: LengthUnit
    public var walls: [Wall]
    public var openings: [Opening]
    public var detectedObjects: [DetectedObject]
    /// Ordered floor polygon (meters). Approximate for F1.
    public var floorOutline: [Point2D]?
    public var source: RoomSource
    /// Room category (from RoomPlan or manual). Optional for backward-compat.
    public var kind: RoomKind?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        unit: LengthUnit = .meters,
        walls: [Wall] = [],
        openings: [Opening] = [],
        detectedObjects: [DetectedObject] = [],
        floorOutline: [Point2D]? = nil,
        source: RoomSource,
        kind: RoomKind? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.unit = unit
        self.walls = walls
        self.openings = openings
        self.detectedObjects = detectedObjects
        self.floorOutline = floorOutline
        self.source = source
        self.kind = kind
    }

    public func wall(_ id: UUID) -> Wall? { walls.first { $0.id == id } }
}
