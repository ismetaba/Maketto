import Foundation

/// Pure floor-plane geometry on our portable types — NO RoomPlan dependency,
/// so it is unit-testable with mock data on any platform.
enum FloorGeometry {
    /// Floor-plane normal of a wall (perpendicular to its direction).
    static func wallNormal(_ wall: Wall) -> Point2D {
        let d = wall.direction
        return Point2D(x: -d.z, z: d.x)
    }

    /// Point-to-segment distance on the floor plane (meters).
    static func distance(from p: Point2D, to wall: Wall) -> Double {
        let ab = wall.end - wall.start
        let abLen2 = ab.dot(ab)
        guard abLen2 > 1e-9 else { return p.distance(to: wall.start) }
        var t = (p - wall.start).dot(ab) / abLen2
        t = min(max(t, 0), 1)
        let proj = wall.start + ab * t
        return p.distance(to: proj)
    }

    /// Order wall corners into a closed loop by WALKING wall adjacency (shared
    /// endpoints) — correct for non-convex (L/U) rooms, unlike an angular sort.
    /// Returns nil when the walls do not form a single simple closed loop
    /// (e.g. a partial scan), so consumers never trust a degenerate polygon.
    static func outline(fromWalls walls: [Wall], tolerance: Double = 0.02) -> [Point2D]? {
        guard walls.count >= 3 else { return nil }

        // Canonical corner list (merge endpoints within tolerance).
        var corners: [Point2D] = []
        func cornerIndex(_ p: Point2D) -> Int {
            if let i = corners.firstIndex(where: { $0.distance(to: p) < tolerance }) { return i }
            corners.append(p)
            return corners.count - 1
        }

        // Corner-adjacency graph from wall connectivity.
        var adjacency: [Int: [Int]] = [:]
        for wall in walls {
            let a = cornerIndex(wall.start)
            let b = cornerIndex(wall.end)
            guard a != b else { continue }
            adjacency[a, default: []].append(b)
            adjacency[b, default: []].append(a)
        }
        guard corners.count >= 3 else { return nil }
        // A simple closed loop requires every corner to have exactly two neighbors.
        guard adjacency.count == corners.count,
              adjacency.allSatisfy({ $0.value.count == 2 }) else { return nil }

        // Walk wall-to-wall through shared corners to order the loop.
        var order: [Int] = []
        var previous = -1
        var current = 0
        repeat {
            order.append(current)
            let neighbors = adjacency[current] ?? []
            guard let next = neighbors.first(where: { $0 != previous }) ?? neighbors.first
            else { return nil }
            previous = current
            current = next
            if order.count > corners.count { return nil }   // malformed-graph guard
        } while current != 0

        guard order.count == corners.count else { return nil }
        return order.map { corners[$0] }
    }
}
