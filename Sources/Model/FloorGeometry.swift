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
        distance(from: p, toSegment: wall.start, wall.end)
    }

    /// Point-to-segment distance on the floor plane (meters).
    static func distance(from p: Point2D, toSegment a: Point2D, _ b: Point2D) -> Double {
        p.distance(to: closestPoint(on: a, b, to: p))
    }

    /// The point of segment `a`–`b` closest to `p`.
    static func closestPoint(on a: Point2D, _ b: Point2D, to p: Point2D) -> Point2D {
        let ab = b - a
        let abLen2 = ab.dot(ab)
        guard abLen2 > 1e-12 else { return a }
        let t = min(max((p - a).dot(ab) / abLen2, 0), 1)
        return a + ab * t
    }

    /// Intersection of the two infinite lines through `a1→a2` and `b1→b2`;
    /// nil when they are (near) parallel.
    static func lineIntersection(_ a1: Point2D, _ a2: Point2D,
                                 _ b1: Point2D, _ b2: Point2D) -> Point2D? {
        let r = a2 - a1, s = b2 - b1
        let denom = r.x * s.z - r.z * s.x
        let scale = r.length * s.length
        guard scale > 1e-12, abs(denom) / scale > 0.05 else { return nil }   // < ~3° apart
        let t = ((b1.x - a1.x) * s.z - (b1.z - a1.z) * s.x) / denom
        return a1 + r * t
    }

    // MARK: - Floor outline

    /// Order wall corners into a closed loop by WALKING wall adjacency (shared
    /// endpoints) — correct for non-convex (L/U) rooms, unlike an angular sort.
    ///
    /// Scans are imperfect, so this is deliberately forgiving: dangling walls
    /// (spurs that end in mid-air) are pruned, and when the corners do not meet
    /// at `tolerance` the match radius is widened step by step up to
    /// `maxTolerance`. Returns nil when the walls still do not form a single
    /// simple closed loop (e.g. a partial scan), so consumers never trust a
    /// degenerate polygon.
    static func outline(fromWalls walls: [Wall], tolerance: Double = 0.02,
                        maxTolerance: Double = 0.10) -> [Point2D]? {
        var tol = tolerance
        while true {
            if let loop = strictOutline(fromWalls: walls, tolerance: tol) { return loop }
            if tol >= maxTolerance { return nil }
            tol = min(tol * 2, maxTolerance)
        }
    }

    /// One attempt at a fixed match radius (see `outline`).
    static func strictOutline(fromWalls walls: [Wall], tolerance: Double) -> [Point2D]? {
        guard walls.count >= 3 else { return nil }

        // Canonical corner list (merge endpoints within tolerance).
        var corners: [Point2D] = []
        func cornerIndex(_ p: Point2D) -> Int {
            if let i = corners.firstIndex(where: { $0.distance(to: p) < tolerance }) { return i }
            corners.append(p)
            return corners.count - 1
        }

        // Corner-adjacency graph from wall connectivity (parallel duplicates
        // collapse to one edge).
        var adjacency: [Int: Set<Int>] = [:]
        for wall in walls {
            let a = cornerIndex(wall.start)
            let b = cornerIndex(wall.end)
            guard a != b else { continue }
            adjacency[a, default: []].insert(b)
            adjacency[b, default: []].insert(a)
        }

        // Prune spurs: a corner with a single neighbour is a dangling wall end.
        var pruned = true
        while pruned {
            pruned = false
            for (corner, neighbors) in adjacency where neighbors.count < 2 {
                for n in neighbors { adjacency[n]?.remove(corner) }
                adjacency[corner] = nil
                pruned = true
            }
        }

        // A simple closed loop requires every remaining corner to have exactly
        // two neighbours.
        guard adjacency.count >= 3,
              adjacency.allSatisfy({ $0.value.count == 2 }),
              let start = adjacency.keys.min() else { return nil }

        // Walk wall-to-wall through shared corners to order the loop.
        var order: [Int] = []
        var previous = -1
        var current = start
        repeat {
            order.append(current)
            let neighbors = (adjacency[current] ?? []).sorted()
            guard let next = neighbors.first(where: { $0 != previous }) ?? neighbors.first
            else { return nil }
            previous = current
            current = next
            if order.count > adjacency.count { return nil }   // malformed-graph guard
        } while current != start

        // Several disjoint loops (e.g. two rooms) are not ONE floor polygon.
        guard order.count == adjacency.count else { return nil }
        let polygon = order.map { corners[$0] }
        return abs(signedArea(polygon)) > 1e-4 ? polygon : nil
    }

    /// Shoelace signed area (positive = counter-clockwise in x/z).
    static func signedArea(_ poly: [Point2D]) -> Double {
        guard poly.count >= 3 else { return 0 }
        var s = 0.0
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            s += a.x * b.z - b.x * a.z
        }
        return s * 0.5
    }

    // MARK: - Corner welding (scan clean-up)

    /// Snap nearly-touching wall ends onto one shared corner so the room's walls
    /// form a real graph: each cluster of endpoints within `tolerance` becomes a
    /// single corner — the intersection of the two wall lines when exactly two
    /// non-parallel walls meet there (a true corner), else the cluster mean.
    ///
    /// Both ends of one wall never merge, and walls shorter than `minLength`
    /// (scan slivers) are dropped first. Pure and order-stable.
    static func weldCorners(_ walls: [Wall], tolerance: Double = 0.10,
                            minLength: Double = 0.12) -> [Wall] {
        let kept = walls.filter { $0.length >= minLength }
        guard kept.count >= 2 else { return kept }

        // Endpoint k: wall k/2, start if k even, end if odd.
        let count = kept.count * 2
        func point(_ k: Int) -> Point2D { k % 2 == 0 ? kept[k / 2].start : kept[k / 2].end }

        // Union-find over endpoints, never joining a wall's two ends.
        var parent = Array(0..<count)
        var members: [Int: Set<Int>] = Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, [$0 / 2]) })
        func find(_ k: Int) -> Int {
            var r = k
            while parent[r] != r { r = parent[r] }
            var c = k
            while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
            return r
        }

        // Closest pairs first, so a corner grabs its true partner before a
        // farther endpoint can chain into the cluster.
        var pairs: [(Double, Int, Int)] = []
        for i in 0..<count {
            for j in (i + 1)..<count where i / 2 != j / 2 {
                let d = point(i).distance(to: point(j))
                if d <= tolerance { pairs.append((d, i, j)) }
            }
        }
        pairs.sort { $0.0 < $1.0 }
        for (_, i, j) in pairs {
            let ri = find(i), rj = find(j)
            guard ri != rj else { continue }
            let wallsI = members[ri] ?? [], wallsJ = members[rj] ?? []
            guard wallsI.isDisjoint(with: wallsJ) else { continue }
            parent[rj] = ri
            members[ri] = wallsI.union(wallsJ)
            members[rj] = nil
        }

        // Resolve each cluster to one corner point.
        var clusters: [Int: [Int]] = [:]
        for k in 0..<count { clusters[find(k), default: []].append(k) }
        var resolved = [Point2D](repeating: Point2D(x: 0, z: 0), count: count)
        for (_, ends) in clusters {
            let mean = ends.reduce(Point2D(x: 0, z: 0)) { $0 + point($1) } * (1.0 / Double(ends.count))
            var corner = mean
            if ends.count == 2 {
                let w1 = kept[ends[0] / 2], w2 = kept[ends[1] / 2]
                if let x = lineIntersection(w1.start, w1.end, w2.start, w2.end),
                   x.distance(to: mean) <= tolerance * 2 {
                    corner = x
                }
            }
            for k in ends { resolved[k] = corner }
        }

        return kept.enumerated().compactMap { i, wall in
            var w = wall
            w.start = resolved[2 * i]
            w.end = resolved[2 * i + 1]
            return w.length >= minLength * 0.5 ? w : nil
        }
    }
}
