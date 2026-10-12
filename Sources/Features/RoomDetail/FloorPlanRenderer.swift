import SwiftUI

/// Per-room ink palette for the plan renderer.
struct PlanInk {
    var paper: Color    // knockout color for gaps
    var floor: Color
    var wall: Color
    var door: Color
    var window: Color
}

/// Stateless drawing of ONE room's geometry (floor poché, walls, openings,
/// furniture). Shared by the single-room `FloorPlanView` and the multi-room
/// `WholeHomePlanView` — the only difference between them is the ink and how
/// many rooms they loop over.
enum FloorPlanRenderer {
    static func drawRoom(_ room: RoomModel, into context: GraphicsContext,
                         t: PlanGeometry.Transform, ink: PlanInk, showScanObjects: Bool) {
        drawFloor(room, into: context, t: t, floor: ink.floor)
        drawStructure(walls: room.walls, openings: PlanGeometry.hostedOpenings(room),
                      centroid: PlanGeometry.centroid(room), objects: room.detectedObjects,
                      into: context, t: t, ink: ink, showScanObjects: showScanObjects)
    }

    /// Floor poché only (the whole-home plan draws fills per room, walls once).
    static func drawFloor(_ room: RoomModel, into context: GraphicsContext,
                          t: PlanGeometry.Transform, floor: Color) {
        guard let poly = PlanGeometry.floorPolygon(room) else { return }
        var path = Path()
        path.addLines(poly.map { t.apply($0) })
        path.closeSubpath()
        context.fill(path, with: .color(floor))
    }

    /// Walls + openings (+ RoomPlan's detected objects as dashed ghosts) from
    /// explicit lists. The whole-home plan passes a de-duplicated union so
    /// shared walls draw exactly once.
    static func drawStructure(walls: [Wall], openings: [PlanGeometry.HostedOpening], centroid: Point2D,
                              objects: [DetectedObject], into context: GraphicsContext,
                              t: PlanGeometry.Transform, ink: PlanInk, showScanObjects: Bool) {
        if showScanObjects {
            for obj in objects { drawObject(context, obj: obj, t: t) }
        }
        for wall in walls {
            var p = Path()
            p.move(to: t.apply(wall.start))
            p.addLine(to: t.apply(wall.end))
            let wpt = max(t.points(wall.thickness), 2.5)
            context.stroke(p, with: .color(ink.wall),
                           style: StrokeStyle(lineWidth: wpt, lineCap: .square, lineJoin: .miter))
        }
        for hosted in openings {
            let seg = PlanGeometry.openingSegment(hosted.opening, on: hosted.wall, interiorReference: centroid)
            drawOpening(context, opening: hosted.opening, seg: seg, t: t, ink: ink)
        }
    }

    // MARK: - Furniture

    /// Placed furniture: tinted footprint (or the item's photo), a front tick
    /// so orientation reads at a glance, and the name when it fits.
    @MainActor
    static func drawFurniture(_ items: [PlacedFurniture], into context: GraphicsContext,
                              t: PlanGeometry.Transform, dark: Bool,
                              selectedID: UUID? = nil, selectionColor: Color = Brand.clay,
                              labels: Bool = true) {
        for item in items {
            let poly = FurnitureGeometry.footprint(item).map { t.apply($0) }
            guard poly.count >= 3 else { continue }
            var path = Path()
            path.addLines(poly)
            path.closeSubpath()

            let color = Color(hex: UInt(item.resolvedColorHex))
            let isRug = item.category == .rug
            context.fill(path, with: .color(color.opacity(isRug ? 0.16 : (dark ? 0.45 : 0.30))))

            if let id = item.photoID, let photo = FurniturePhotoStore.image(for: id) {
                var clipped = context
                clipped.clip(to: path)
                let c = t.apply(item.center)
                clipped.translateBy(x: c.x, y: c.y)
                clipped.rotate(by: .radians(item.rotation))
                let w = t.points(item.width), h = t.points(item.depth)
                let iw = max(photo.size.width, 1), ih = max(photo.size.height, 1)
                let scale = max(w / iw, h / ih)
                let rect = CGRect(x: -iw * scale / 2, y: -ih * scale / 2, width: iw * scale, height: ih * scale)
                clipped.opacity = 0.92
                clipped.draw(clipped.resolve(Image(uiImage: photo)), in: rect)
            }

            let line = color.opacity(dark ? 0.95 : 0.85)
            context.stroke(path, with: .color(line),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round,
                                              dash: isRug ? [5, 4] : []))

            // Front tick (local +z edge) for rectangular pieces.
            if item.shape == .rectangle, !isRug, t.points(item.width) > 18 {
                let inset = 4 / max(t.scale, 1)
                let a = t.apply(FurnitureGeometry.toWorld(
                    Point2D(x: -item.width * 0.3, z: item.depth / 2 - inset), of: item))
                let b = t.apply(FurnitureGeometry.toWorld(
                    Point2D(x: item.width * 0.3, z: item.depth / 2 - inset), of: item))
                var tick = Path(); tick.move(to: a); tick.addLine(to: b)
                context.stroke(tick, with: .color(line), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            if item.id == selectedID {
                context.stroke(path, with: .color(selectionColor.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 8, lineJoin: .round))
                context.stroke(path, with: .color(selectionColor),
                               style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }

            if labels {
                let minSide = min(t.points(item.width), t.points(item.depth))
                guard minSide > 30 else { continue }
                let text = context.resolve(
                    Text(item.name).font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Brand.textPrimary)
                )
                let size = text.measure(in: CGSize(width: 400, height: 40))
                guard size.width < max(t.points(item.width), t.points(item.depth)) - 6 else { continue }
                let labelPoint = t.apply(labelAnchor(item))
                context.draw(text, at: labelPoint, anchor: .center)
            }
        }
    }

    /// Where a piece's name sits: its centre, or the middle of an L's back bar.
    private static func labelAnchor(_ item: PlacedFurniture) -> Point2D {
        guard item.shape == .lShape, let back = FurnitureGeometry.localBoxes(item).first else {
            return item.center
        }
        return FurnitureGeometry.toWorld(back.center, of: item)
    }

    // MARK: - Pills

    /// A filled capsule label (measurements, sizes), clamped into `bounds`.
    static func drawPill(_ context: GraphicsContext, text: String, at center: CGPoint,
                         fill: Color, textColor: Color = .white, fontSize: CGFloat = 13,
                         within bounds: CGRect? = nil) {
        let resolved = context.resolve(
            Text(text).font(.system(size: fontSize, weight: .heavy)).foregroundColor(textColor)
        )
        let ts = resolved.measure(in: CGSize(width: 320, height: 60))
        let w = ts.width + 20, h = ts.height + 10
        var c = center
        if let bounds {
            let minX = bounds.minX + w / 2, maxX = bounds.maxX - w / 2
            let minY = bounds.minY + h / 2, maxY = bounds.maxY - h / 2
            if minX < maxX { c.x = min(max(c.x, minX), maxX) }
            if minY < maxY { c.y = min(max(c.y, minY), maxY) }
        }
        let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        context.fill(Capsule().path(in: rect), with: .color(fill))
        context.draw(resolved, at: c, anchor: .center)
    }

    private static func drawOpening(_ context: GraphicsContext, opening: Opening,
                                    seg: PlanGeometry.OpeningSegment, t: PlanGeometry.Transform,
                                    ink: PlanInk) {
        let pa = t.apply(seg.start)
        let pb = t.apply(seg.end)
        let wpt = max(t.points(seg.thickness), 2.5)

        var hole = Path(); hole.move(to: pa); hole.addLine(to: pb)
        context.stroke(hole, with: .color(ink.paper), style: StrokeStyle(lineWidth: wpt + 1, lineCap: .butt))

        switch opening.type {
        case .opening:
            break
        case .window:
            var line = Path(); line.move(to: pa); line.addLine(to: pb)
            context.stroke(line, with: .color(ink.window), style: StrokeStyle(lineWidth: 3))
        case .door:
            drawDoor(context, seg: seg, t: t, ink: ink)
        }
    }

    private static func drawDoor(_ context: GraphicsContext, seg: PlanGeometry.OpeningSegment,
                                 t: PlanGeometry.Transform, ink: PlanInk) {
        let hinge = t.apply(seg.start)
        let latch = t.apply(seg.end)
        let radius = hypot(latch.x - hinge.x, latch.y - hinge.y)
        guard radius > 1 else { return }
        let closed = atan2(latch.y - hinge.y, latch.x - hinge.x)
        let cScreen = t.apply(seg.center)
        let inTip = t.apply(seg.center + seg.interiorNormal)
        let inAng = atan2(inTip.y - cScreen.y, inTip.x - cScreen.x)
        let plus = closed + .pi / 2, minus = closed - .pi / 2
        let open = abs(angleDiff(plus, inAng)) < abs(angleDiff(minus, inAng)) ? plus : minus

        var leaf = Path()
        leaf.move(to: hinge)
        leaf.addLine(to: CGPoint(x: hinge.x + radius * cos(open), y: hinge.y + radius * sin(open)))
        context.stroke(leaf, with: .color(ink.door), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        if radius > 10 {
            var arc = Path()
            arc.addArc(center: hinge, radius: radius,
                       startAngle: .radians(closed), endAngle: .radians(open),
                       clockwise: open < closed)
            context.stroke(arc, with: .color(ink.door.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5))
        }
    }

    /// A RoomPlan-detected object: dashed ghost outline (it is reference, not
    /// furniture the user placed).
    private static func drawObject(_ context: GraphicsContext, obj: DetectedObject,
                                   t: PlanGeometry.Transform) {
        let corners = PlanGeometry.footprintCorners(obj).map { t.apply($0) }
        guard corners.count == 4 else { return }
        var path = Path(); path.addLines(corners); path.closeSubpath()
        let ghost = Color(light: Color(hex: 0x8C9083), dark: Color(hex: 0xAFC4A9))
        context.fill(path, with: .color(ghost.opacity(0.10)))
        context.stroke(path, with: .color(ghost.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: [4, 3]))
    }

    private static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    // MARK: - Dynamic metric grid (shared)

    /// Metric "graph paper" whose cell size adapts to zoom (1 m → 1 cm); the finest
    /// tier fades in smoothly. Shared by single-room and whole-home plans.
    static func drawGrid(_ context: GraphicsContext, size: CGSize,
                         t: PlanGeometry.Transform, dark: Bool) {
        let ppm = t.scale
        guard ppm > 0 else { return }
        let steps: [Double] = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10]
        let target: CGFloat = 20
        guard let i = steps.firstIndex(where: { CGFloat($0) * ppm >= target }) else { return }
        let minor = steps[i]
        let major = i + 1 < steps.count ? steps[i + 1] : minor * 5
        let minorSpacing = CGFloat(minor) * ppm
        let fade = Double(min(max(minorSpacing / target - 1.0, 0), 1))

        let tl = t.unapply(.zero)
        let br = t.unapply(CGPoint(x: size.width, y: size.height))
        let minX = min(tl.x, br.x), maxX = max(tl.x, br.x)
        let minZ = min(tl.z, br.z), maxZ = max(tl.z, br.z)
        let ink = dark ? Color.white : Brand.ink

        gridLines(context, step: minor, minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, t: t,
                  color: ink.opacity((dark ? 0.06 : 0.05) * fade), width: 0.5)
        gridLines(context, step: major, minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, t: t,
                  color: ink.opacity(dark ? 0.13 : 0.09), width: 0.75)

        let cell = fade > 0.35 ? minor : major
        let resolved = context.resolve(
            Text(gridUnitLabel(cell)).font(.system(size: 10, weight: .semibold))
                .foregroundColor(Brand.textFaint)
        )
        context.draw(resolved, at: CGPoint(x: 14, y: size.height - 12), anchor: .bottomLeading)
    }

    private static func gridLines(_ context: GraphicsContext, step: Double,
                                  minX: Double, maxX: Double, minZ: Double, maxZ: Double,
                                  t: PlanGeometry.Transform, color: Color, width: CGFloat) {
        guard step > 0 else { return }
        let span = max(maxX - minX, maxZ - minZ)
        guard span / step <= 500 else { return }
        let style = StrokeStyle(lineWidth: width)
        var x = (minX / step).rounded(.down) * step
        while x <= maxX {
            var p = Path()
            p.move(to: t.apply(Point2D(x: x, z: minZ)))
            p.addLine(to: t.apply(Point2D(x: x, z: maxZ)))
            context.stroke(p, with: .color(color), style: style)
            x += step
        }
        var z = (minZ / step).rounded(.down) * step
        while z <= maxZ {
            var p = Path()
            p.move(to: t.apply(Point2D(x: minX, z: z)))
            p.addLine(to: t.apply(Point2D(x: maxX, z: z)))
            context.stroke(p, with: .color(color), style: style)
            z += step
        }
    }

    private static func gridUnitLabel(_ meters: Double) -> String {
        if meters < 1 { return "\(Int((meters * 100).rounded())) cm" }
        return meters == meters.rounded()
            ? "\(Int(meters)) m"
            : String(format: "%.1f m", locale: MeasurementFormat.locale, meters)
    }
}
