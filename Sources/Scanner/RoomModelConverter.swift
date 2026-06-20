import Foundation
import simd

#if canImport(RoomPlan)
import RoomPlan

/// The ONLY file that imports RoomPlan. Pure, non-isolated, value-in/value-out
/// conversion CapturedRoom -> RoomModel, so it runs in tests with no device.
/// Pure floor geometry lives in `FloorGeometry` (no RoomPlan dependency).
///
/// Coordinate conventions (RoomPlan/ARKit are right-handed, Y-up, meters):
/// the floor plane is XZ (world Y dropped). For a Surface transform (column-major):
///   columns.0 = local +X = RIGHT  (the wall's WIDTH / length direction)
///   columns.1 = local +Y = UP     (height)
///   columns.2 = local +Z = NORMAL (faces out of the wall)
///   columns.3 = POSITION          (the surface CENTER)
/// dimensions = (width, height, thickness): .x = floor length, .y = height, .z = thickness.
enum RoomModelConverter {
    static func makeRoomModel(
        from captured: CapturedRoom,
        name: String,
        createdAt: Date = .now
    ) -> RoomModel {
        let walls = captured.walls.map(makeWall(from:))

        let openings =
            captured.doors.compactMap { makeOpening(from: $0, type: .door, walls: walls) }
            + captured.windows.compactMap { makeOpening(from: $0, type: .window, walls: walls) }
            + captured.openings.compactMap { makeOpening(from: $0, type: .opening, walls: walls) }

        let objects = captured.objects.map(makeObject(from:))
        let outline = FloorGeometry.outline(fromWalls: walls)

        return RoomModel(
            name: name,
            createdAt: createdAt,
            walls: walls,
            openings: openings,
            detectedObjects: objects,
            floorOutline: outline,
            source: .roomplan,
            kind: roomKind(of: captured)
        )
    }

    /// Map RoomPlan's room section label to our RoomKind (first section wins).
    static func roomKind(of captured: CapturedRoom) -> RoomKind {
        switch captured.sections.first?.label {
        case .livingRoom: return .livingRoom
        case .bedroom: return .bedroom
        case .bathroom: return .bathroom
        case .kitchen: return .kitchen
        case .diningRoom: return .diningRoom
        default: return .unidentified
        }
    }

    // MARK: - Walls

    private static func makeWall(from surface: CapturedRoom.Surface) -> Wall {
        let t = surface.transform
        let center = t.columns.3.xyz
        let rightWorld = t.columns.0.xyz
        // Project the wall's right/length axis onto the floor and renormalize.
        var rightFloor = SIMD3<Float>(rightWorld.x, 0, rightWorld.z)
        let m = simd_length(rightFloor)
        rightFloor = m > 1e-6 ? rightFloor / m : SIMD3<Float>(1, 0, 0)
        let half = surface.dimensions.x * 0.5    // half WIDTH == half floor length
        let startW = center - rightFloor * half
        let endW = center + rightFloor * half
        return Wall(
            id: surface.identifier,
            start: Point2D(droppingYFrom: startW),
            end: Point2D(droppingYFrom: endW),
            thickness: Double(surface.dimensions.z),
            height: Double(surface.dimensions.y)
        )
    }

    // MARK: - Openings

    private static func makeOpening(
        from surface: CapturedRoom.Surface,
        type: Opening.Kind,
        walls: [Wall]
    ) -> Opening? {
        let center = Point2D(droppingYFrom: surface.transform.columns.3.xyz)

        // The opening's own surface normal, projected to the floor plane.
        let nWorld = surface.transform.columns.2.xyz
        let n = Point2D(x: Double(nWorld.x), z: Double(nWorld.z))
        let nl = n.length
        let openingNormal = nl > 1e-6 ? n * (1.0 / nl) : Point2D(x: 1, z: 0)

        // Prefer walls whose normal is parallel to the opening's normal, so a
        // corner door/window is not stolen by a perpendicular adjoining wall.
        let aligned = walls.filter { abs(openingNormal.dot(FloorGeometry.wallNormal($0))) > 0.5 }
        let candidates = aligned.isEmpty ? walls : aligned
        guard let wall = candidates.min(by: {
            FloorGeometry.distance(from: center, to: $0) < FloorGeometry.distance(from: center, to: $1)
        }) else { return nil }

        // Drop stray surfaces that belong to no wall.
        guard FloorGeometry.distance(from: center, to: wall) <= max(wall.thickness, 0.3) else { return nil }

        let along = (center - wall.start).dot(wall.direction)
        let offset = min(max(along, 0), wall.length)
        let centerY = Double(surface.transform.columns.3.y)
        let height = Double(surface.dimensions.y)
        let sill: Double? = (type == .window) ? max(centerY - height / 2, 0) : nil
        return Opening(
            id: surface.identifier,
            type: type,
            onWallId: wall.id,
            offset: offset,
            width: Double(surface.dimensions.x),
            height: height,
            sillHeight: sill
        )
    }

    // MARK: - Objects

    private static func makeObject(from object: CapturedRoom.Object) -> DetectedObject {
        let t = object.transform
        let yaw = atan2(t.columns.0.z, t.columns.0.x)
        return DetectedObject(
            id: object.identifier,
            category: String(describing: object.category),
            center: Point2D(droppingYFrom: t.columns.3.xyz),
            width: Double(object.dimensions.x),
            depth: Double(object.dimensions.z),
            height: Double(object.dimensions.y),
            rotation: Double(yaw)
        )
    }
}
#endif
