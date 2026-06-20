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
        makeRoomModel(
            walls: captured.walls, doors: captured.doors, windows: captured.windows,
            openings: captured.openings, objects: captured.objects,
            name: name, kind: roomKind(of: captured), createdAt: createdAt
        )
    }

    /// Build a RoomModel from explicit surface/object subsets (used to split a
    /// whole-home capture into per-room models).
    static func makeRoomModel(
        walls capturedWalls: [CapturedRoom.Surface],
        doors: [CapturedRoom.Surface],
        windows: [CapturedRoom.Surface],
        openings: [CapturedRoom.Surface],
        objects capturedObjects: [CapturedRoom.Object],
        name: String, kind: RoomKind, createdAt: Date = .now
    ) -> RoomModel {
        let walls = capturedWalls.map(makeWall(from:))
        let openingModels =
            doors.compactMap { makeOpening(from: $0, type: .door, walls: walls) }
            + windows.compactMap { makeOpening(from: $0, type: .window, walls: walls) }
            + openings.compactMap { makeOpening(from: $0, type: .opening, walls: walls) }
        let objects = capturedObjects.map(makeObject(from:))
        let outline = FloorGeometry.outline(fromWalls: walls)
        return RoomModel(
            name: name, createdAt: createdAt, walls: walls, openings: openingModels,
            detectedObjects: objects, floorOutline: outline, source: .roomplan, kind: kind
        )
    }

    /// Split ONE whole-home capture into per-room models using its sections:
    /// each wall/opening/object is assigned to the nearest section centre.
    /// Falls back to a single room when there is 0–1 section.
    static func splitRooms(from captured: CapturedRoom, createdAt: Date = .now) -> [RoomModel] {
        let sections = captured.sections
        guard sections.count > 1 else {
            return [makeRoomModel(from: captured, name: "", createdAt: createdAt)]
        }
        let n = sections.count

        /// Squared distances from a point to every section centre, sorted nearest-first.
        func ranked(_ p: SIMD3<Float>) -> [(index: Int, d2: Float)] {
            sections.enumerated().map { i, s in
                let dx = s.center.x - p.x, dz = s.center.z - p.z
                return (i, dx * dx + dz * dz)
            }
            .sorted { $0.d2 < $1.d2 }
        }
        /// Assign to the nearest section AND a near-tie second one, so a shared
        /// wall/opening between two rooms belongs to BOTH and each loop can close.
        func assign(_ p: SIMD3<Float>, into buckets: inout [[Int]], item: Int) {
            let r = ranked(p)
            buckets[r[0].index].append(item)
            if r.count > 1, r[1].d2 < r[0].d2 * 2.56 {   // within ~1.6x of nearest
                buckets[r[1].index].append(item)
            }
        }
        func nearest(_ p: SIMD3<Float>) -> Int { ranked(p)[0].index }

        var wallIdx = Array(repeating: [Int](), count: n)
        var doorIdx = wallIdx, windowIdx = wallIdx, openIdx = wallIdx
        var objIdx = Array(repeating: [Int](), count: n)
        for (k, w) in captured.walls.enumerated() { assign(w.transform.columns.3.xyz, into: &wallIdx, item: k) }
        for (k, d) in captured.doors.enumerated() { assign(d.transform.columns.3.xyz, into: &doorIdx, item: k) }
        for (k, w) in captured.windows.enumerated() { assign(w.transform.columns.3.xyz, into: &windowIdx, item: k) }
        for (k, o) in captured.openings.enumerated() { assign(o.transform.columns.3.xyz, into: &openIdx, item: k) }
        for (k, o) in captured.objects.enumerated() { objIdx[nearest(o.transform.columns.3.xyz)].append(k) }

        let rooms = sections.enumerated().map { i, s in
            makeRoomModel(
                walls: wallIdx[i].map { captured.walls[$0] },
                doors: doorIdx[i].map { captured.doors[$0] },
                windows: windowIdx[i].map { captured.windows[$0] },
                openings: openIdx[i].map { captured.openings[$0] },
                objects: objIdx[i].map { captured.objects[$0] },
                name: "", kind: sectionKind(s.label), createdAt: createdAt
            )
        }
        // Drop sections that won no walls; fall back to one room if all collapse.
        let nonEmpty = rooms.filter { !$0.walls.isEmpty }
        return nonEmpty.isEmpty ? [makeRoomModel(from: captured, name: "", createdAt: createdAt)] : nonEmpty
    }

    static func roomKind(of captured: CapturedRoom) -> RoomKind {
        sectionKind(captured.sections.first?.label ?? .unidentified)
    }

    static func sectionKind(_ label: CapturedRoom.Section.Label) -> RoomKind {
        switch label {
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
