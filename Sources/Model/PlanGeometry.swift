import Foundation
import CoreGraphics

/// Pure top-down floor-plan geometry: maps the portable `RoomModel`
/// (`Point2D` in world XZ meters) into screen-space `CGPoint`s for the F2
/// 2D plan `Canvas`. CoreGraphics/Foundation ONLY — no SwiftUI, no RoomPlan —
/// so it previews/unit-tests with `RoomModel.mock` on any platform.
///
/// ## Coordinate rule (SINGLE SOURCE OF TRUTH — do not deviate anywhere)
/// World floor plane is `Point2D(x, z)` in meters (Y-up dropped). Screen is
/// UIKit/Canvas: origin top-left, +x right, +y DOWN. The map is:
///
///     screen.x = (world.x - origin.x) * scale + offset.x
///     screen.y = (world.z - origin.y) * scale + offset.y     // z -> y, NOT negated
///
/// Neither axis is negated, so the map is a pure uniform scale + translation
/// (det = +scale^2 > 0): orientation-preserving, NOT a mirror. This is the
/// architect's top-down view: look straight down -Y; world +x is screen-right,
/// world +z is toward the BOTTOM of the page. Every swing/normal/rotation in
/// the renderer is derived under this one rule. Route EVERY world point through
/// `Transform.apply`; never hand-convert a point inline.
enum PlanGeometry {

    // MARK: - Transform

    /// Affine world(meters)->view(points) map: uniform scale + translation.
    /// Built by `fit(...)`. User pinch/pan are composed on top of this base in
    /// the SwiftUI layer (this struct holds only the base fit, keeping it pure).
    struct Transform: Equatable, Sendable {
        /// World-space min corner that anchors the mapping (bbox.min), meters.
        var origin: CGPoint        // NOTE: .x = world x, .y = world z
        /// Uniform meters->points scale (identical on both axes -> aspect kept).
        var scale: CGFloat         // points per meter
        /// View-space translation applied after scaling (handles centering+pan).
        var offset: CGPoint        // points

        /// World `Point2D` (meters) -> view `CGPoint` (points).
        func apply(_ p: Point2D) -> CGPoint {
            CGPoint(
                x: (CGFloat(p.x) - origin.x) * scale + offset.x,
                y: (CGFloat(p.z) - origin.y) * scale + offset.y   // z -> y
            )
        }

        /// Inverse: view `CGPoint` (points) -> world `Point2D` (meters).
        /// For hit-testing taps back onto walls/objects (used by later milestones).
        func unapply(_ q: CGPoint) -> Point2D {
            guard scale != 0 else { return Point2D(x: 0, z: 0) }
            return Point2D(
                x: Double((q.x - offset.x) / scale + origin.x),
                z: Double((q.y - offset.y) / scale + origin.y)
            )
        }

        /// Scale a world distance (meters) into view points (wall thickness,
        /// swing radius, grid spacing, footprint size...).
        func points(_ meters: Double) -> CGFloat { CGFloat(meters) * scale }
    }

    // MARK: - Bounding box

    /// Axis-aligned world bbox over ALL wall endpoints (start + end).
    /// Walls always exist (unlike `floorOutline`, nil on partial scans), and
    /// openings/objects live within the walls, so this bounds everything drawn.
    /// Returns nil when there are no walls.
    static func worldBounds(_ room: RoomModel, includeObjects: Bool = true) -> CGRect? {
        var pts: [Point2D] = []
        pts.reserveCapacity(room.walls.count * 2 + room.detectedObjects.count * 4)
        for w in room.walls { pts.append(w.start); pts.append(w.end) }
        // Fold in furniture footprint corners so overhanging objects never clip
        // (only when furniture is actually drawn).
        if includeObjects {
            for o in room.detectedObjects { pts.append(contentsOf: footprintCorners(o)) }
        }
        return bounds(of: pts)
    }

    /// AABB of an arbitrary point set, in world meters (rect.y = world z).
    static func bounds(of pts: [Point2D]) -> CGRect? {
        guard let first = pts.first else { return nil }
        var minX = first.x, maxX = first.x
        var minZ = first.z, maxZ = first.z
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        return CGRect(x: minX, y: minZ, width: maxX - minX, height: maxZ - minZ)
    }

    // MARK: - Fit

    /// Build the base fit `Transform` that centers the room in `size` with
    /// uniform scale and `padding` points of inset on every edge. `maxScale`
    /// clamps zoom for tiny/degenerate rooms. Returns nil for an empty room.
    static func fit(
        _ room: RoomModel,
        in size: CGSize,
        padding: CGFloat = 28,
        maxScale: CGFloat = 240,
        includeObjects: Bool = true
    ) -> Transform? {
        guard let bbox = worldBounds(room, includeObjects: includeObjects) else { return nil }
        return fit(bounds: bbox, in: size, padding: padding, maxScale: maxScale)
    }

    /// Fit an explicit world bbox — exposed so callers can union extra regions.
    static func fit(
        bounds bbox: CGRect,
        in size: CGSize,
        padding: CGFloat = 28,
        maxScale: CGFloat = 240
    ) -> Transform {
        let availW = max(size.width  - 2 * padding, 1)
        let availH = max(size.height - 2 * padding, 1)
        let worldW = bbox.width
        let worldH = bbox.height

        // Uniform scale: the smaller axis ratio wins so the room fits both ways.
        // A degenerate (zero) extent on an axis must not drive scale to 0/inf, so
        // it is ignored unless BOTH are zero.
        let sx: CGFloat = worldW > 1e-9 ? availW / CGFloat(worldW) : .greatestFiniteMagnitude
        let sy: CGFloat = worldH > 1e-9 ? availH / CGFloat(worldH) : .greatestFiniteMagnitude
        var scale = min(sx, sy)
        if !scale.isFinite { scale = 100 }            // empty/degenerate bbox
        scale = min(scale, maxScale)

        // Center the scaled content in the view.
        let scaledW = CGFloat(worldW) * scale
        let scaledH = CGFloat(worldH) * scale
        let offset = CGPoint(
            x: (size.width  - scaledW) / 2,
            y: (size.height - scaledH) / 2
        )
        return Transform(
            origin: CGPoint(x: bbox.minX, y: bbox.minY),
            scale: scale,
            offset: offset
        )
    }

    // MARK: - 1) Opening endpoints + normal

    /// The two world endpoints of an opening's gap on its wall, the wall's unit
    /// direction and normal, plus an INTERIOR-pointing normal (resolved against
    /// the room centroid) so doors swing inward and windows/openings cap cleanly.
    struct OpeningSegment {
        var start: Point2D        // gap endpoint nearer wall.start
        var end: Point2D          // gap endpoint nearer wall.end
        var center: Point2D
        var direction: Point2D    // unit, wall.start -> wall.end
        var normal: Point2D       // unit, = FloorGeometry.wallNormal (90 deg CCW of dir)
        var interiorNormal: Point2D   // unit, points INTO the room
        var thickness: Double
        var width: Double
    }

    /// `offset` is the distance from `wall.start` to the opening CENTER, so the
    /// gap spans `[offset - width/2, offset + width/2]`, clamped to the wall.
    static func openingSegment(
        _ opening: Opening,
        on wall: Wall,
        interiorReference centroid: Point2D
    ) -> OpeningSegment {
        let half = opening.width / 2
        let len = wall.length
        let a = min(max(opening.offset - half, 0), len)
        let b = min(max(opening.offset + half, 0), len)
        let p1 = wall.point(atOffset: a)
        let p2 = wall.point(atOffset: b)
        let n = FloorGeometry.wallNormal(wall)
        let mid = wall.start.midpoint(to: wall.end)
        // Interior normal points toward the room centroid.
        let toward = centroid - mid
        let interior = n.dot(toward) >= 0 ? n : (n * -1)
        return OpeningSegment(
            start: p1,
            end: p2,
            center: p1.midpoint(to: p2),
            direction: wall.direction,
            normal: n,
            interiorNormal: interior,
            thickness: wall.thickness,
            width: opening.width
        )
    }

    /// Convenience: resolve the wall from the room first.
    static func openingSegment(
        _ opening: Opening,
        in room: RoomModel,
        interiorReference centroid: Point2D
    ) -> OpeningSegment? {
        guard let wall = room.wall(opening.onWallId) else { return nil }
        return openingSegment(opening, on: wall, interiorReference: centroid)
    }

    // MARK: - 2) Object footprint corners

    /// The 4 world-space corners of a detected object's footprint rectangle,
    /// ordered (back-left, back-right, front-right, front-left) as seen from
    /// local +z. `width` = local X extent, `depth` = local Z extent, `rotation`
    /// is yaw about +Y from world +X toward +Z (RoomModel convention).
    ///
    /// We rotate the LOCAL corner POINTS by the yaw and add the center; the
    /// renderer then runs each through `Transform.apply`. Rotating points (not
    /// the angle) makes the non-mirror property of the transform automatic.
    static func footprintCorners(_ obj: DetectedObject) -> [Point2D] {
        let hw = obj.width / 2
        let hd = obj.depth / 2
        let c = cos(obj.rotation)
        let s = sin(obj.rotation)
        let local: [(Double, Double)] = [
            (-hw, -hd),   // back-left
            ( hw, -hd),   // back-right
            ( hw,  hd),   // front-right
            (-hw,  hd),   // front-left
        ]
        // +x -> +z convention:  wx = lx*cos - lz*sin ;  wz = lx*sin + lz*cos
        return local.map { lx, lz in
            Point2D(x: obj.center.x + lx * c - lz * s,
                    z: obj.center.z + lx * s + lz * c)
        }
    }

    /// Object facing direction (local +z) in world space — for a "front" tick.
    static func facingDirection(_ obj: DetectedObject) -> Point2D {
        let c = cos(obj.rotation), s = sin(obj.rotation)
        return Point2D(x: -s, z: c)   // (0,1) rotated by yaw
    }

    // MARK: - 3) Dimension label placement

    /// Where to anchor a wall's dimension and how to orient it.
    struct DimensionLabel {
        var start: Point2D        // wall.start
        var end: Point2D          // wall.end
        var midpoint: Point2D     // wall midpoint
        var outwardNormal: Point2D // unit, points AWAY from the room interior
        var text: String
        /// Wall angle in WORLD radians (atan2(dz, dx)). The renderer recomputes
        /// the SCREEN angle from mapped endpoints (so it survives any future
        /// transform), then flips 180 deg if it would render upside down.
        var angle: Double
    }

    /// Build a dimension descriptor for `wall`. The renderer offsets the line
    /// OUTWARD by a constant POINT gap (so it never drifts with zoom); outward =
    /// the side of `outwardNormal`. `text` defaults to a "%.2f m" length string;
    /// pass `MeasurementFormat.meters(wall.length)` from the view for parity.
    static func dimensionLabel(
        for wall: Wall,
        interiorReference centroid: Point2D,
        text: String? = nil
    ) -> DimensionLabel {
        let mid = wall.start.midpoint(to: wall.end)
        var n = FloorGeometry.wallNormal(wall)
        let towardInterior = centroid - mid
        if n.dot(towardInterior) > 0 { n = n * -1 }   // make it OUTWARD
        let dir = wall.direction
        return DimensionLabel(
            start: wall.start,
            end: wall.end,
            midpoint: mid,
            outwardNormal: n,
            text: text ?? String(format: "%.2f m", wall.length),
            angle: atan2(dir.z, dir.x)
        )
    }

    // MARK: - Centroid / outline helpers

    /// Interior reference point for outward-normal resolution. Uses the
    /// area-weighted `floorOutline`/reconstructed outline when a closed polygon
    /// exists, else the mean of wall endpoints.
    static func centroid(_ room: RoomModel) -> Point2D {
        if let poly = room.floorOutline ?? FloorGeometry.outline(fromWalls: room.walls),
           poly.count >= 3,
           let c = polygonCentroid(poly) {
            return c
        }
        var sx = 0.0, sz = 0.0, n = 0.0
        for w in room.walls {
            sx += w.start.x + w.end.x
            sz += w.start.z + w.end.z
            n += 2
        }
        return n > 0 ? Point2D(x: sx / n, z: sz / n) : Point2D(x: 0, z: 0)
    }

    /// Shoelace area-weighted polygon centroid (world XZ). nil for degenerate area.
    static func polygonCentroid(_ poly: [Point2D]) -> Point2D? {
        guard poly.count >= 3 else { return nil }
        var area = 0.0, cx = 0.0, cz = 0.0
        for i in 0..<poly.count {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            let cross = a.x * b.z - b.x * a.z
            area += cross
            cx += (a.x + b.x) * cross
            cz += (a.z + b.z) * cross
        }
        area *= 0.5
        guard abs(area) > 1e-9 else { return nil }
        return Point2D(x: cx / (6 * area), z: cz / (6 * area))
    }

    /// Floor polygon in WORLD meters (outline if valid, else nil). The renderer
    /// maps it through `Transform.apply`. Returns nil if no closed polygon.
    static func floorPolygon(_ room: RoomModel) -> [Point2D]? {
        let poly = room.floorOutline ?? FloorGeometry.outline(fromWalls: room.walls)
        guard let poly, poly.count >= 3 else { return nil }
        return poly
    }

    // MARK: - Multi-room (whole home)

    /// Union bounding box over several rooms (all in one shared world frame).
    static func worldBounds(_ rooms: [RoomModel], includeObjects: Bool = false) -> CGRect? {
        var rect: CGRect?
        for room in rooms {
            guard let b = worldBounds(room, includeObjects: includeObjects) else { continue }
            rect = rect.map { $0.union(b) } ?? b
        }
        return rect
    }

    /// Fit a whole home (many rooms) into a view. Lower default maxScale so a
    /// one-room home doesn't render enormous.
    static func fit(_ rooms: [RoomModel], in size: CGSize,
                    padding: CGFloat = 28, maxScale: CGFloat = 120) -> Transform? {
        guard let bbox = worldBounds(rooms) else { return nil }
        return fit(bounds: bbox, in: size, padding: padding, maxScale: maxScale)
    }

    /// Floor area (m²) via shoelace over the room's floor polygon.
    static func area(of room: RoomModel) -> Double {
        guard let poly = floorPolygon(room), poly.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            s += a.x * b.z - b.x * a.z
        }
        return abs(s) * 0.5
    }

    /// Even-odd point-in-polygon test (floor plane) — for tap-a-room hit testing.
    static func contains(_ poly: [Point2D], _ p: Point2D) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.z > p.z) != (b.z > p.z) {
                let x = a.x + (p.z - a.z) / (b.z - a.z) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
