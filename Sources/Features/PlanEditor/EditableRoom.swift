import Foundation
import Observation

/// Editable working copy of a room as a shared-corner graph: walls are edges
/// between corner vertices, so dragging a corner moves EVERY incident wall (an
/// L-junction stays joined). Built from a RoomModel on enter, flattened back on
/// save. Transient — never persisted; the RoomModel stays the Codable truth.
///
/// Every mutation is one undo step. Openings keep their WORLD position while
/// their wall is stretched or moved, and are dropped only with their wall.
@MainActor
@Observable
final class EditableRoom {
    struct Corner: Identifiable, Hashable { let id: UUID; var p: Point2D }
    struct Edge: Identifiable, Hashable {
        let id: UUID            // == original Wall.id, so openings stay attached
        var a: UUID
        var b: UUID
        var thickness: Double
        var height: Double
    }

    /// World x / z lines the live drag is currently aligned to (for guides).
    struct SnapGuides: Equatable, Sendable {
        var x: Double?
        var z: Double?
        static let none = SnapGuides()
    }

    let roomId: UUID
    var name: String
    let createdAt: Date
    let unit: LengthUnit
    let source: RoomSource
    let kind: RoomKind?
    let weld: Double            // corner coincidence tolerance

    private(set) var corners: [UUID: Corner] = [:]
    private(set) var edges: [Edge] = []
    private(set) var openings: [Opening]
    private(set) var detectedObjects: [DetectedObject]
    private(set) var furniture: [PlacedFurniture]
    private(set) var snapGuides: SnapGuides = .none

    private struct Snapshot: Equatable {
        var corners: [UUID: Corner]
        var edges: [Edge]
        var openings: [Opening]
        var furniture: [PlacedFurniture]
    }
    private let baseline: Snapshot
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var dragBaseline: Snapshot?

    init(_ room: RoomModel, furniture: [PlacedFurniture] = [], weld: Double = 0.05) {
        roomId = room.id
        name = room.name
        createdAt = room.createdAt
        unit = room.unit
        source = room.source
        kind = room.kind
        self.weld = weld
        detectedObjects = room.detectedObjects
        self.furniture = furniture

        // Build the corner graph with a LOCAL helper (no instance-method call
        // before all stored properties are initialized).
        var builtCorners: [UUID: Corner] = [:]
        var cornerOrder: [UUID] = []
        var builtEdges: [Edge] = []
        func cid(_ p: Point2D) -> UUID {
            var best: (UUID, Double)?
            for id in cornerOrder {
                let d = builtCorners[id]!.p.distance(to: p)
                if d < weld, best.map({ d < $0.1 }) ?? true { best = (id, d) }
            }
            if let best { return best.0 }
            let id = UUID()
            builtCorners[id] = Corner(id: id, p: p)
            cornerOrder.append(id)
            return id
        }
        var seenPairs = Set<[UUID]>()
        for wall in room.walls {
            let a = cid(wall.start)
            let b = cid(wall.end)
            guard a != b, seenPairs.insert([a, b].sorted { $0.uuidString < $1.uuidString }).inserted
            else { continue }
            builtEdges.append(Edge(id: wall.id, a: a, b: b, thickness: wall.thickness, height: wall.height))
        }

        // Welding may nudge wall ends; keep every opening at its scanned world
        // position on the (possibly nudged) wall, and drop orphans.
        let keptWalls = Dictionary(uniqueKeysWithValues: builtEdges.map { ($0.id, $0) })
        let originalWalls = Dictionary(room.walls.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var fixedOpenings: [Opening] = []
        for opening in room.openings {
            guard let edge = keptWalls[opening.onWallId],
                  let old = originalWalls[opening.onWallId],
                  let pa = builtCorners[edge.a]?.p, let pb = builtCorners[edge.b]?.p
            else { continue }
            var o = opening
            o.offset = EditableRoom.reanchoredOffset(o, from: (old.start, old.end), to: (pa, pb))
            fixedOpenings.append(o)
        }

        corners = builtCorners
        edges = builtEdges
        openings = fixedOpenings
        baseline = Snapshot(corners: builtCorners, edges: builtEdges,
                            openings: fixedOpenings, furniture: furniture)
    }

    // MARK: - Derived

    /// Live walls for rendering (cheap; safe to call every frame).
    func materializedWalls() -> [Wall] {
        edges.compactMap { e in
            guard let a = corners[e.a]?.p, let b = corners[e.b]?.p else { return nil }
            return Wall(id: e.id, start: a, end: b, thickness: e.thickness, height: e.height)
        }
    }

    /// Flatten the graph back to a RoomModel for persistence.
    func flattened() -> RoomModel {
        let walls = materializedWalls()
        return RoomModel(
            id: roomId, name: name, createdAt: createdAt, unit: unit,
            walls: walls, openings: openings, detectedObjects: detectedObjects,
            floorOutline: FloorGeometry.outline(fromWalls: walls, tolerance: 0.005,
                                                maxTolerance: weld),
            source: source, kind: kind
        )
    }

    var isDirty: Bool { snapshot() != baseline }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func wall(_ id: UUID) -> Wall? { materializedWalls().first { $0.id == id } }
    func furnitureItem(_ id: UUID) -> PlacedFurniture? { furniture.first { $0.id == id } }

    /// Corners joined to `id` by a wall.
    func neighbors(of id: UUID) -> [UUID] {
        edges.compactMap { e in e.a == id ? e.b : (e.b == id ? e.a : nil) }
    }

    /// Walls that meet at corner `id`.
    func walls(at id: UUID) -> [Wall] {
        materializedWalls().filter { w in
            edges.contains { $0.id == w.id && ($0.a == id || $0.b == id) }
        }
    }

    // MARK: - Hit testing (world space)

    func corner(near p: Point2D, within radius: Double, excluding: UUID? = nil) -> UUID? {
        var best: (UUID, Double)?
        for (id, c) in corners where id != excluding {
            let d = c.p.distance(to: p)
            if d <= radius, best.map({ d < $0.1 }) ?? true { best = (id, d) }
        }
        return best?.0
    }

    func wall(near p: Point2D, within radius: Double) -> UUID? {
        var best: (UUID, Double)?
        for wall in materializedWalls() {
            let d = FloorGeometry.distance(from: p, to: wall)
            if d <= radius, best.map({ d < $0.1 }) ?? true { best = (wall.id, d) }
        }
        return best?.0
    }

    /// Topmost furniture under `p` (last drawn wins).
    func furnitureID(at p: Point2D, slop: Double = 0) -> UUID? {
        furniture.last { FurnitureGeometry.contains($0, p, slop: slop) }?.id
    }

    func cornerPosition(_ id: UUID) -> Point2D? { corners[id]?.p }

    // MARK: - Snapping

    /// Align `p` to the x / z of nearby corners (walls stay square), within
    /// `tolerance` meters. Returns the snapped point and the guides used.
    func snapped(_ p: Point2D, tolerance: Double, excluding: Set<UUID> = [],
                 extraAnchors: [Point2D] = []) -> (Point2D, SnapGuides) {
        guard tolerance > 0 else { return (p, .none) }
        var anchors = extraAnchors
        for (id, c) in corners where !excluding.contains(id) { anchors.append(c.p) }
        var bestX: (value: Double, delta: Double)?
        var bestZ: (value: Double, delta: Double)?
        for a in anchors {
            let dx = abs(a.x - p.x), dz = abs(a.z - p.z)
            if dx <= tolerance, bestX.map({ dx < $0.delta }) ?? true { bestX = (a.x, dx) }
            if dz <= tolerance, bestZ.map({ dz < $0.delta }) ?? true { bestZ = (a.z, dz) }
        }
        let out = Point2D(x: bestX?.value ?? p.x, z: bestZ?.value ?? p.z)
        return (out, SnapGuides(x: bestX?.value, z: bestZ?.value))
    }

    /// Show / clear alignment guides from the view (e.g. while drawing a wall).
    func setGuides(_ guides: SnapGuides) { snapGuides = guides }

    // MARK: - Corner drag

    /// Begin a corner drag — captures the pre-drag state for one undo step.
    func beginCornerDrag() { dragBaseline = snapshot() }

    /// Live move (aligned to other corners within `snapTolerance` meters).
    func dragCorner(_ id: UUID, to p: Point2D, snapTolerance: Double = 0) {
        guard corners[id] != nil else { return }
        let (target, guides) = snapped(p, tolerance: snapTolerance, excluding: [id])
        corners[id]?.p = target
        snapGuides = guides
        if let reference = dragBaseline {
            reanchorOpenings(touching: [id], reference: reference)
        }
    }

    /// Commit a corner move: weld onto another corner dropped within
    /// `weldRadius`, then push ONE undo step (none for a no-op drag).
    ///
    /// The corner's own wall neighbours only weld when dropped right on them
    /// (within `weld`), and corners that were already close before the drag
    /// never weld — so nudging the end of a short wall can't collapse it.
    func endCornerDrag(_ id: UUID, weldRadius: Double? = nil) {
        snapGuides = .none
        guard let reference = dragBaseline else { return }
        dragBaseline = nil
        if let c = corners[id] {
            let radius = max(weldRadius ?? 0, weld)
            let start = reference.corners[id]?.p
            let neighbours = Set(neighbors(of: id))
            var best: (UUID, Double)?
            for (other, corner) in corners where other != id {
                let d = corner.p.distance(to: c.p)
                let limit = neighbours.contains(other) ? weld : radius
                guard d <= limit else { continue }
                if !neighbours.contains(other), let start,
                   let was = reference.corners[other]?.p, was.distance(to: start) <= radius {
                    continue
                }
                if best.map({ d < $0.1 }) ?? true { best = (other, d) }
            }
            if let other = best?.0 {
                mergeCorner(id, into: other)
                reanchorOpenings(touching: [other], reference: reference)
            }
        }
        if snapshot() != reference { commit(reference) }
    }

    /// Abort a drag (e.g. the gesture was cancelled) and restore the pre-drag state.
    func cancelDrag() {
        snapGuides = .none
        guard let reference = dragBaseline else { return }
        dragBaseline = nil
        apply(reference)
    }

    // MARK: - Wall operations

    func deleteWall(_ id: UUID) {
        guard let e = edges.first(where: { $0.id == id }) else { return }
        let before = snapshot()
        edges.removeAll { $0.id == id }
        openings.removeAll { $0.onWallId == id }
        for c in [e.a, e.b] where !edges.contains(where: { $0.a == c || $0.b == c }) {
            corners[c] = nil
        }
        commit(before)
    }

    /// Set a wall's length by moving its END corner along the wall. A wall
    /// meeting that end at (near) right angles is carried along rigidly, so a
    /// rectangle stays a rectangle ("push the wall"). Returns false if invalid.
    @discardableResult
    func setLength(of edgeID: UUID, to length: Double) -> Bool {
        guard length >= 0.05, length <= 100,
              let e = edges.first(where: { $0.id == edgeID }),
              let pa = corners[e.a]?.p, let pb = corners[e.b]?.p else { return false }
        let current = pa.distance(to: pb)
        guard current > 1e-6, abs(current - length) > 1e-5 else { return false }
        let dir = (pb - pa) * (1 / current)
        let delta = dir * (length - current)

        let before = snapshot()
        var moved: Set<UUID> = [e.b]
        for other in edges where other.id != e.id && (other.a == e.b || other.b == e.b) {
            let far = other.a == e.b ? other.b : other.a
            guard far != e.a, let pf = corners[far]?.p else { continue }
            let od = pf - pb
            let ol = od.length
            if ol > 1e-6, abs(od.dot(dir)) / ol < 0.17 { moved.insert(far) }   // within ~10° of square
        }
        for id in moved { if let p = corners[id]?.p { corners[id]?.p = p + delta } }
        reanchorOpenings(touching: moved, reference: before)
        commit(before)
        return true
    }

    /// Draw a new wall from `p` to `q`. Each end joins a corner within
    /// `snapRadius`, else splits a wall it lands on, else starts a free corner.
    /// Returns the new wall id, or nil for a degenerate / duplicate wall.
    @discardableResult
    func addWall(from p: Point2D, to q: Point2D, snapRadius: Double) -> UUID? {
        guard p.distance(to: q) >= 0.05 else { return nil }
        let before = snapshot()
        let a = resolveCorner(at: p, radius: snapRadius, excluding: nil)
        let b = resolveCorner(at: q, radius: snapRadius, excluding: a)
        guard a != b,
              let pa = corners[a]?.p, let pb = corners[b]?.p, pa.distance(to: pb) >= 0.05,
              !edges.contains(where: { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) })
        else {
            apply(before)
            return nil
        }
        let template = edges.first
        let edge = Edge(id: UUID(), a: a, b: b,
                        thickness: template?.thickness ?? 0.1,
                        height: template?.height ?? 2.5)
        edges.append(edge)
        commit(before)
        return edge.id
    }

    /// Existing corner near `p`, else a split point on a wall near `p`, else a
    /// brand-new corner at `p`. (Part of a larger edit — no undo step.)
    private func resolveCorner(at p: Point2D, radius: Double, excluding: UUID?) -> UUID {
        if let id = corner(near: p, within: radius, excluding: excluding) { return id }
        if let wallID = wall(near: p, within: radius),
           let split = splitEdge(wallID, at: p) {
            return split
        }
        let id = UUID()
        corners[id] = Corner(id: id, p: p)
        return id
    }

    /// Split a wall at the projection of `p`, keeping openings on the half
    /// they sit on. Returns the new corner, or nil if `p` is too near an end.
    private func splitEdge(_ edgeID: UUID, at p: Point2D) -> UUID? {
        guard let i = edges.firstIndex(where: { $0.id == edgeID }),
              let pa = corners[edges[i].a]?.p, let pb = corners[edges[i].b]?.p else { return nil }
        let e = edges[i]
        let length = pa.distance(to: pb)
        let point = FloorGeometry.closestPoint(on: pa, pb, to: p)
        guard length > 0.1 else { return nil }

        // Never split through a door or window: move the split to the
        // opening's nearer edge so the opening stays whole on one half.
        var along = point.distance(to: pa)
        for o in openings where o.onWallId == e.id {
            let lo = o.offset - o.width / 2, hi = o.offset + o.width / 2
            if along > lo, along < hi { along = (along - lo < hi - along) ? lo : hi }
        }
        guard along > 0.05, length - along > 0.05 else { return nil }
        let splitPoint = pa + (pb - pa) * (along / length)

        let mid = UUID()
        corners[mid] = Corner(id: mid, p: splitPoint)
        let second = Edge(id: UUID(), a: mid, b: e.b, thickness: e.thickness, height: e.height)
        edges[i].b = mid
        edges.insert(second, at: i + 1)
        for k in openings.indices where openings[k].onWallId == e.id && openings[k].offset >= along {
            openings[k].onWallId = second.id
            openings[k].offset -= along
        }
        return mid
    }

    /// Re-point every edge from `moving` onto `target` and drop the merged
    /// corner, plus any wall that collapsed or now duplicates another (with
    /// the openings on it).
    private func mergeCorner(_ moving: UUID, into target: UUID) {
        guard moving != target else { return }
        for i in edges.indices {
            if edges[i].a == moving { edges[i].a = target }
            if edges[i].b == moving { edges[i].b = target }
        }
        var seen = Set<[UUID]>()
        var removed = Set<UUID>()
        edges.removeAll { e in
            let key = [e.a, e.b].sorted { $0.uuidString < $1.uuidString }
            if e.a == e.b || !seen.insert(key).inserted {
                removed.insert(e.id)
                return true
            }
            return false
        }
        openings.removeAll { removed.contains($0.onWallId) }
        corners[moving] = nil
        for (id, _) in corners where !edges.contains(where: { $0.a == id || $0.b == id }) {
            corners[id] = nil
        }
    }

    // MARK: - Furniture

    func addFurniture(_ item: PlacedFurniture) {
        let before = snapshot()
        furniture.append(item)
        commit(before)
    }

    /// Add several pieces as ONE undo step (e.g. importing scanned objects).
    func addFurniture(_ items: [PlacedFurniture]) {
        guard !items.isEmpty else { return }
        let before = snapshot()
        furniture.append(contentsOf: items)
        commit(before)
    }

    func beginFurnitureDrag() { dragBaseline = snapshot() }

    /// Live move to `center`, sliding flush against walls within `snapTolerance`.
    func dragFurniture(_ id: UUID, to center: Point2D, snapTolerance: Double = 0) {
        guard let i = furniture.firstIndex(where: { $0.id == id }) else { return }
        var f = furniture[i]
        f.center = center
        furniture[i] = FurnitureGeometry.snappedToWalls(f, walls: materializedWalls(),
                                                        tolerance: snapTolerance)
    }

    func endFurnitureDrag() {
        guard let reference = dragBaseline else { return }
        dragBaseline = nil
        if snapshot() != reference { commit(reference) }
    }

    func rotateFurniture(_ id: UUID, by angle: Double) {
        updateFurniture(id) { $0.rotation = FurnitureGeometry.normalized($0.rotation + angle) }
    }

    /// Apply an arbitrary change to one piece as one undo step.
    func updateFurniture(_ id: UUID, _ change: (inout PlacedFurniture) -> Void) {
        guard let i = furniture.firstIndex(where: { $0.id == id }) else { return }
        let before = snapshot()
        var f = furniture[i]
        change(&f)
        f.width = min(max(f.width, 0.05), 20)
        f.depth = min(max(f.depth, 0.05), 20)
        f.height = min(max(f.height, 0.005), 6)
        guard f != furniture[i] else { return }
        furniture[i] = f
        commit(before)
    }

    func deleteFurniture(_ id: UUID) {
        guard furniture.contains(where: { $0.id == id }) else { return }
        let before = snapshot()
        furniture.removeAll { $0.id == id }
        commit(before)
    }

    /// Copy a piece, offset slightly so both stay visible. Returns the copy's id.
    @discardableResult
    func duplicateFurniture(_ id: UUID) -> UUID? {
        guard let original = furnitureItem(id) else { return nil }
        let copy = PlacedFurniture(
            name: original.name, category: original.category, shape: original.shape,
            center: original.center + Point2D(x: 0.25, z: 0.25),
            width: original.width, depth: original.depth, height: original.height,
            rotation: original.rotation, armDepth: original.armDepth,
            mirrored: original.mirrored, colorHex: original.colorHex,
            photoID: original.photoID, templateID: original.templateID
        )
        addFurniture(copy)
        return copy.id
    }

    // MARK: - Undo / redo

    func undo() {
        guard let s = undoStack.popLast() else { return }
        dragBaseline = nil
        redoStack.append(snapshot())
        apply(s)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        dragBaseline = nil
        undoStack.append(snapshot())
        apply(s)
    }

    private func snapshot() -> Snapshot {
        Snapshot(corners: corners, edges: edges, openings: openings, furniture: furniture)
    }

    /// Push one undo step. Any drag still pending (its gesture was abandoned
    /// without ending) is finished here, so a later cancel can never roll
    /// back this newer edit.
    private func commit(_ before: Snapshot) {
        dragBaseline = nil
        undoStack.append(before)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func apply(_ s: Snapshot) {
        corners = s.corners
        edges = s.edges
        openings = s.openings
        furniture = s.furniture
    }

    // MARK: - Opening anchoring

    /// Keep openings on walls touching `moved` corners at their world
    /// position in `reference` (recomputed from the reference every time, so
    /// a long drag never accumulates drift).
    private func reanchorOpenings(touching moved: Set<UUID>, reference: Snapshot) {
        let touched = edges.filter { moved.contains($0.a) || moved.contains($0.b) }
        guard !touched.isEmpty else { return }
        for edge in touched {
            guard let refEdge = reference.edges.first(where: { $0.id == edge.id }),
                  let ra = reference.corners[refEdge.a]?.p, let rb = reference.corners[refEdge.b]?.p,
                  let na = corners[edge.a]?.p, let nb = corners[edge.b]?.p else { continue }
            for k in openings.indices where openings[k].onWallId == edge.id {
                guard let original = reference.openings.first(where: { $0.id == openings[k].id })
                else { continue }
                openings[k].offset = Self.reanchoredOffset(original, from: (ra, rb), to: (na, nb))
            }
        }
    }

    /// Offset that keeps `opening`'s centre at its old world position after
    /// its wall moved from `old` to `new`, clamped so the opening stays on it.
    nonisolated static func reanchoredOffset(_ opening: Opening,
                                             from old: (Point2D, Point2D),
                                             to new: (Point2D, Point2D)) -> Double {
        let oldWall = Wall(start: old.0, end: old.1)
        let newWall = Wall(start: new.0, end: new.1)
        let world = oldWall.point(atOffset: opening.offset)
        let along = (world - newWall.start).dot(newWall.direction)
        let length = newWall.length
        let half = opening.width / 2
        guard length > opening.width else { return length / 2 }
        return min(max(along, half), length - half)
    }
}
