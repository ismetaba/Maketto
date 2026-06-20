import Foundation
import Observation

/// Editable working copy of a room as a shared-corner graph: walls are edges
/// between corner vertices, so dragging a corner moves EVERY incident wall (an
/// L-junction stays joined). Built from a RoomModel on enter, flattened back on
/// save. Transient — never persisted; the RoomModel stays the Codable truth.
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

    let roomId: UUID
    var name: String
    let createdAt: Date
    let unit: LengthUnit
    let source: RoomSource
    let kind: RoomKind?
    let weld: Double            // corner coincidence tolerance (== outline default)

    private(set) var corners: [UUID: Corner] = [:]
    private(set) var edges: [Edge] = []
    private(set) var openings: [Opening]
    private(set) var detectedObjects: [DetectedObject]

    private struct Snapshot { var corners: [UUID: Corner]; var edges: [Edge]; var openings: [Opening] }
    private let baseline: Snapshot
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var dragBaseline: Snapshot?

    init(_ room: RoomModel, weld: Double = 0.02) {
        roomId = room.id
        name = room.name
        createdAt = room.createdAt
        unit = room.unit
        source = room.source
        kind = room.kind
        self.weld = weld
        openings = room.openings
        detectedObjects = room.detectedObjects

        // Build the corner graph with a LOCAL helper (no instance-method call
        // before all stored properties are initialized).
        var builtCorners: [UUID: Corner] = [:]
        var builtEdges: [Edge] = []
        func cid(_ p: Point2D) -> UUID {
            for (id, c) in builtCorners where c.p.distance(to: p) < weld { return id }
            let id = UUID()
            builtCorners[id] = Corner(id: id, p: p)
            return id
        }
        for wall in room.walls {
            let a = cid(wall.start)
            let b = cid(wall.end)
            guard a != b else { continue }
            builtEdges.append(Edge(id: wall.id, a: a, b: b, thickness: wall.thickness, height: wall.height))
        }
        corners = builtCorners
        edges = builtEdges
        baseline = Snapshot(corners: builtCorners, edges: builtEdges, openings: room.openings)
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
            floorOutline: FloorGeometry.outline(fromWalls: walls, tolerance: weld),
            source: source, kind: kind
        )
    }

    var isDirty: Bool {
        edges != baseline.edges || corners != baseline.corners || openings != baseline.openings
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Hit testing (world space)

    func corner(near p: Point2D, within radius: Double) -> UUID? {
        var best: (UUID, Double)?
        for (id, c) in corners {
            let d = c.p.distance(to: p)
            if d <= radius, best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    func wall(near p: Point2D, within radius: Double) -> UUID? {
        var best: (UUID, Double)?
        for wall in materializedWalls() {
            let d = FloorGeometry.distance(from: p, to: wall)
            if d <= radius, best == nil || d < best!.1 { best = (wall.id, d) }
        }
        return best?.0
    }

    func cornerPosition(_ id: UUID) -> Point2D? { corners[id]?.p }

    // MARK: - Operations

    /// Begin a corner drag — captures the pre-drag state for one undo step.
    func beginCornerDrag() { dragBaseline = snapshot() }

    /// Live move (no undo/snap) — call on every drag change.
    func dragCorner(_ id: UUID, to p: Point2D) { corners[id]?.p = p }

    /// Commit a corner move: snap to grid + weld onto a nearby corner, push undo.
    func endCornerDrag(_ id: UUID, gridStep: Double = 0.05) {
        guard let baseline = dragBaseline else { return }
        dragBaseline = nil
        if var c = corners[id] {
            c.p = Point2D(x: (c.p.x / gridStep).rounded() * gridStep,
                          z: (c.p.z / gridStep).rounded() * gridStep)
            corners[id] = c
            if let other = corner(near: c.p, within: max(weld, gridStep) * 1.5) , other != id {
                mergeCorner(id, into: other)
            }
        }
        commit(baseline)
    }

    func deleteWall(_ id: UUID) {
        guard let e = edges.first(where: { $0.id == id }) else { return }
        let baseline = snapshot()
        edges.removeAll { $0.id == id }
        openings.removeAll { $0.onWallId == id }
        for c in [e.a, e.b] where !edges.contains(where: { $0.a == c || $0.b == c }) {
            corners[c] = nil
        }
        commit(baseline)
    }

    /// Re-point every edge from `moving` onto `target` and drop the merged corner.
    private func mergeCorner(_ moving: UUID, into target: UUID) {
        guard moving != target else { return }
        for i in edges.indices {
            if edges[i].a == moving { edges[i].a = target }
            if edges[i].b == moving { edges[i].b = target }
        }
        edges.removeAll { $0.a == $0.b }
        corners[moving] = nil
    }

    // MARK: - Undo / redo

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        apply(s)
    }
    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        apply(s)
    }

    private func snapshot() -> Snapshot { Snapshot(corners: corners, edges: edges, openings: openings) }
    private func commit(_ baseline: Snapshot) { undoStack.append(baseline); redoStack.removeAll() }
    private func apply(_ s: Snapshot) { corners = s.corners; edges = s.edges; openings = s.openings }
}
