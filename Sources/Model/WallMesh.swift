import Foundation

/// Pure decomposition of a wall into solid rectangular panels around its
/// openings, in the wall's own (u, v) plane: u runs along the wall from
/// `start` (0…length), v is height above the floor (0…height). The 3D builder
/// turns every panel into one box — so doors and windows are real holes.
enum WallMesh {
    struct Rect: Equatable, Sendable {
        var u0: Double, u1: Double   // along the wall, meters
        var v0: Double, v1: Double   // above the floor, meters
        var width: Double { u1 - u0 }
        var height: Double { v1 - v0 }
    }

    struct Hole: Equatable, Sendable {
        var rect: Rect
        var kind: Opening.Kind
    }

    /// Default sill for windows scanned without one.
    static let defaultSill = 0.9

    /// The openings of `wall` as holes in its (u, v) plane, clamped to the wall.
    static func holes(in wall: Wall, openings: [Opening]) -> [Hole] {
        let length = wall.length, height = wall.height
        guard length > 0, height > 0 else { return [] }
        return openings.compactMap { o in
            guard o.onWallId == wall.id, o.width > 0.01, o.height > 0.01 else { return nil }
            let u0 = max(o.offset - o.width / 2, 0)
            let u1 = min(o.offset + o.width / 2, length)
            let bottom = o.type == .window ? max(o.sillHeight ?? defaultSill, 0) : 0
            let v0 = min(bottom, height)
            let v1 = min(bottom + o.height, height)
            guard u1 - u0 > 0.01, v1 - v0 > 0.01 else { return nil }
            return Hole(rect: Rect(u0: u0, u1: u1, v0: v0, v1: v1), kind: o.type)
        }
    }

    /// Solid panels covering the wall minus its holes. Vertical strips are cut
    /// at every hole edge; each strip keeps the height ranges no hole covers,
    /// and equal neighbouring strips are merged back together.
    static func panels(length: Double, height: Double, holes: [Rect]) -> [Rect] {
        guard length > 0, height > 0 else { return [] }
        var cuts = Set<Double>([0, length])
        for h in holes {
            cuts.insert(min(max(h.u0, 0), length))
            cuts.insert(min(max(h.u1, 0), length))
        }
        let xs = cuts.sorted()
        var strips: [(u0: Double, u1: Double, ranges: [(Double, Double)])] = []
        for i in 0..<(xs.count - 1) {
            let u0 = xs[i], u1 = xs[i + 1]
            guard u1 - u0 > 1e-6 else { continue }
            let mid = (u0 + u1) / 2
            let covering = holes
                .filter { $0.u0 < mid && mid < $0.u1 }
                .map { (max($0.v0, 0), min($0.v1, height)) }
                .sorted { $0.0 < $1.0 }
            var ranges: [(Double, Double)] = []
            var cursor = 0.0
            for (a, b) in covering {
                if a > cursor + 1e-6 { ranges.append((cursor, a)) }
                cursor = max(cursor, b)
            }
            if height > cursor + 1e-6 { ranges.append((cursor, height)) }
            strips.append((u0, u1, ranges))
        }

        // Merge adjacent strips with identical solid ranges (fewer boxes).
        var merged: [(u0: Double, u1: Double, ranges: [(Double, Double)])] = []
        for strip in strips {
            if let last = merged.last, abs(last.u1 - strip.u0) < 1e-6,
               last.ranges.count == strip.ranges.count,
               zip(last.ranges, strip.ranges).allSatisfy({
                   abs($0.0 - $1.0) < 1e-6 && abs($0.1 - $1.1) < 1e-6
               }) {
                merged[merged.count - 1].u1 = strip.u1
            } else {
                merged.append(strip)
            }
        }
        return merged.flatMap { strip in
            strip.ranges.map { Rect(u0: strip.u0, u1: strip.u1, v0: $0.0, v1: $0.1) }
        }
    }
}
