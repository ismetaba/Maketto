import SwiftUI
import UIKit

/// Beautiful read-only top-down floor plan (F2). Renders purely from a
/// `RoomModel` via the pure `PlanGeometry`, so it previews with mock data and
/// needs no device/RoomPlan. Pinch to zoom, drag to pan, double-tap to fit.
struct FloorPlanView: View {
    let room: RoomModel
    /// Detected furniture is hidden for now (walls + openings only). Flip to
    /// true — or wire a toggle — when the interior-design / furniture milestone
    /// lands; the drawing + data path is kept intact behind this flag.
    var showFurniture: Bool = false

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragLive: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveZoom: CGFloat { zoom * pinch }
    private var effectivePan: CGSize {
        CGSize(width: pan.width + dragLive.width, height: pan.height + dragLive.height)
    }

    var body: some View {
        if PlanGeometry.worldBounds(room, includeObjects: showFurniture) == nil {
            ContentUnavailableView("No Floor Plan", systemImage: "square.dashed")
        } else {
            Canvas { context, size in
                draw(context, size: size)
            }
            .contentShape(Rectangle())
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = (zoom * value.magnification).clamped(0.4, 6) }
                .simultaneously(with:
                    DragGesture()
                        .updating($dragLive) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            pan.width += value.translation.width
                            pan.height += value.translation.height
                        }
                )
        )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.3)) { zoom = 1; pan = .zero }
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ context: GraphicsContext, size: CGSize) {
        let paper = Color(.secondarySystemBackground)
        guard let base = PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240,
                                          includeObjects: showFurniture) else {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
            return
        }
        // Anchor zoom about the view CENTER (not the bbox-min corner) so pinching
        // magnifies in place instead of shoving the plan off-screen.
        let z = effectiveZoom
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let t = PlanGeometry.Transform(
            origin: base.origin,
            scale: base.scale * z,
            offset: CGPoint(x: c.x + (base.offset.x - c.x) * z + effectivePan.width,
                            y: c.y + (base.offset.y - c.y) * z + effectivePan.height)
        )
        let centroid = PlanGeometry.centroid(room)
        let dark = colorScheme == .dark
        let ink = Color.primary
        let accent = Color.accentColor

        // 1) Paper background (defines the page; openings knock out to this color)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))

        // 2) Grid
        drawGrid(context, size: size, t: t, ink: ink, dark: dark)

        // 3) Floor poché
        if let poly = PlanGeometry.floorPolygon(room) {
            var path = Path()
            path.addLines(poly.map { t.apply($0) })
            path.closeSubpath()
            context.fill(path, with: .color(ink.opacity(dark ? 0.10 : 0.05)))
        }

        // 4) Wall bodies (poché via thick stroke)
        for wall in room.walls {
            var p = Path()
            p.move(to: t.apply(wall.start))
            p.addLine(to: t.apply(wall.end))
            let wpt = max(t.points(wall.thickness), 2)
            context.stroke(p, with: .color(ink.opacity(dark ? 0.92 : 0.90)),
                           style: StrokeStyle(lineWidth: wpt, lineCap: .square, lineJoin: .miter))
        }

        // 5) Openings (knock-out + symbols)
        for opening in room.openings {
            guard let seg = PlanGeometry.openingSegment(opening, in: room, interiorReference: centroid)
            else { continue }
            drawOpening(context, opening: opening, seg: seg, t: t, ink: ink, paper: paper)
        }

        // 6) Furniture footprints — hidden until the interior-design milestone.
        if showFurniture {
            for obj in room.detectedObjects {
                drawObject(context, obj: obj, t: t, accent: accent, dark: dark)
            }
        }

        // 7) Dimensions
        for wall in room.walls {
            drawDimension(context, wall: wall, t: t, centroid: centroid)
        }

        // 8) Scale bar (chrome)
        drawScaleBar(context, size: size, t: t, ink: ink)
    }

    private func drawGrid(_ context: GraphicsContext, size: CGSize, t: PlanGeometry.Transform,
                          ink: Color, dark: Bool) {
        let topLeft = t.unapply(.zero)
        let bottomRight = t.unapply(CGPoint(x: size.width, y: size.height))
        let minX = min(topLeft.x, bottomRight.x), maxX = max(topLeft.x, bottomRight.x)
        let minZ = min(topLeft.z, bottomRight.z), maxZ = max(topLeft.z, bottomRight.z)

        var step: Double = t.points(1) < 14 ? 5 : 1
        let span = max(maxX - minX, maxZ - minZ)
        while step > 0, span / step > 120 { step *= 2 }     // cap line count
        guard step > 0 else { return }

        let color = ink.opacity(dark ? 0.08 : 0.05)
        let style = StrokeStyle(lineWidth: 0.5)

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

    private func drawOpening(_ context: GraphicsContext, opening: Opening,
                             seg: PlanGeometry.OpeningSegment, t: PlanGeometry.Transform,
                             ink: Color, paper: Color) {
        let pa = t.apply(seg.start)
        let pb = t.apply(seg.end)
        let wpt = max(t.points(seg.thickness), 2)

        // a) knock the hole in the wall band
        var hole = Path()
        hole.move(to: pa); hole.addLine(to: pb)
        context.stroke(hole, with: .color(paper), style: StrokeStyle(lineWidth: wpt + 1, lineCap: .butt))

        // jamb ticks across the wall thickness at each end
        let half = seg.thickness / 2
        func jamb(at worldPoint: Point2D) {
            let p1 = t.apply(worldPoint + seg.interiorNormal * half)
            let p2 = t.apply(worldPoint - seg.interiorNormal * half)
            var p = Path(); p.move(to: p1); p.addLine(to: p2)
            context.stroke(p, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1))
        }

        switch opening.type {
        case .opening:
            jamb(at: seg.start); jamb(at: seg.end)
        case .window:
            var center = Path(); center.move(to: pa); center.addLine(to: pb)
            context.stroke(center, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5))
            jamb(at: seg.start); jamb(at: seg.end)
        case .door:
            drawDoor(context, seg: seg, t: t, ink: ink)
            jamb(at: seg.start); jamb(at: seg.end)
        }
    }

    private func drawDoor(_ context: GraphicsContext, seg: PlanGeometry.OpeningSegment,
                          t: PlanGeometry.Transform, ink: Color) {
        let hinge = t.apply(seg.start)
        let latch = t.apply(seg.end)
        let radius = hypot(latch.x - hinge.x, latch.y - hinge.y)
        guard radius > 1 else { return }
        let closed = atan2(latch.y - hinge.y, latch.x - hinge.x)

        // interior direction in screen space
        let cScreen = t.apply(seg.center)
        let inTip = t.apply(seg.center + seg.interiorNormal)
        let inAng = atan2(inTip.y - cScreen.y, inTip.x - cScreen.x)
        let plus = closed + .pi / 2
        let minus = closed - .pi / 2
        let open = abs(angleDiff(plus, inAng)) < abs(angleDiff(minus, inAng)) ? plus : minus

        // leaf
        var leaf = Path()
        leaf.move(to: hinge)
        leaf.addLine(to: CGPoint(x: hinge.x + radius * cos(open), y: hinge.y + radius * sin(open)))
        context.stroke(leaf, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        // dashed swing arc, bulging toward the interior
        if radius > 10 {
            var arc = Path()
            arc.addArc(center: hinge, radius: radius,
                       startAngle: .radians(closed), endAngle: .radians(open),
                       clockwise: open < closed)
            context.stroke(arc, with: .color(ink.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func drawObject(_ context: GraphicsContext, obj: DetectedObject,
                            t: PlanGeometry.Transform, accent: Color, dark: Bool) {
        let corners = PlanGeometry.footprintCorners(obj).map { t.apply($0) }
        guard corners.count == 4 else { return }
        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        context.fill(path, with: .color(accent.opacity(dark ? 0.22 : 0.14)))
        context.stroke(path, with: .color(accent.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        // facing tick (constant length, toward local +z)
        let center = t.apply(obj.center)
        let facingTip = t.apply(obj.center + PlanGeometry.facingDirection(obj))
        let dx = facingTip.x - center.x, dy = facingTip.y - center.y
        let len = hypot(dx, dy)
        if len > 0.5 {
            let ux = dx / len, uy = dy / len
            var tick = Path()
            tick.move(to: center)
            tick.addLine(to: CGPoint(x: center.x + ux * 14, y: center.y + uy * 14))
            context.stroke(tick, with: .color(accent.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // label, only if the footprint is wide enough to read
        let footprintWidth = hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y)
        if footprintWidth > 36 {
            let resolved = context.resolve(
                Text(obj.category.capitalized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            )
            context.draw(resolved, at: center, anchor: .center)
        }
    }

    private func drawDimension(_ context: GraphicsContext, wall: Wall,
                               t: PlanGeometry.Transform, centroid: Point2D) {
        let a = t.apply(wall.start)
        let b = t.apply(wall.end)
        let screenLen = hypot(b.x - a.x, b.y - a.y)
        guard screenLen > 40 else { return }     // declutter short walls

        let d = PlanGeometry.dimensionLabel(for: wall, interiorReference: centroid,
                                            text: MeasurementFormat.meters(wall.length))
        // outward normal in screen space
        let mid = t.apply(d.midpoint)
        let nTip = t.apply(d.midpoint + d.outwardNormal)
        var nx = nTip.x - mid.x, ny = nTip.y - mid.y
        let nlen = hypot(nx, ny)
        guard nlen > 0 else { return }
        nx /= nlen; ny /= nlen

        let gap: CGFloat = 18
        let a2 = CGPoint(x: a.x + nx * gap, y: a.y + ny * gap)
        let b2 = CGPoint(x: b.x + nx * gap, y: b.y + ny * gap)
        let col = Color.secondary

        // dimension line
        var dim = Path(); dim.move(to: a2); dim.addLine(to: b2)
        context.stroke(dim, with: .color(col), style: StrokeStyle(lineWidth: 1, lineCap: .butt))

        // extension lines
        var ext = Path()
        ext.move(to: a); ext.addLine(to: a2)
        ext.move(to: b); ext.addLine(to: b2)
        context.stroke(ext, with: .color(col.opacity(0.55)), style: StrokeStyle(lineWidth: 0.75))

        // 45deg ticks at the ends
        var dirx = b2.x - a2.x, diry = b2.y - a2.y
        let dlen = hypot(dirx, diry)
        if dlen > 0 { dirx /= dlen; diry /= dlen }
        func tick(at p: CGPoint) {
            let tx = dirx + nx, ty = diry + ny
            let tl = hypot(tx, ty)
            guard tl > 0 else { return }
            let ux = tx / tl, uy = ty / tl
            var tk = Path()
            tk.move(to: CGPoint(x: p.x - ux * 4, y: p.y - uy * 4))
            tk.addLine(to: CGPoint(x: p.x + ux * 4, y: p.y + uy * 4))
            context.stroke(tk, with: .color(col), style: StrokeStyle(lineWidth: 1))
        }
        tick(at: a2); tick(at: b2)

        // label, centered on the dim line, pushed slightly further out, kept upright
        let labelPos = CGPoint(x: (a2.x + b2.x) / 2 + nx * 9, y: (a2.y + b2.y) / 2 + ny * 9)
        let angle = atan2(Double(b.y - a.y), Double(b.x - a.x))
        drawRotatedLabel(context, d.text, at: labelPos, angle: angle)
    }

    private func drawScaleBar(_ context: GraphicsContext, size: CGSize,
                              t: PlanGeometry.Transform, ink: Color) {
        let candidates: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10]
        guard let meters = candidates.first(where: { t.points($0) >= 60 && t.points($0) <= 130 })
                ?? candidates.last(where: { t.points($0) <= 130 })
                ?? candidates.first else { return }
        let barLen = t.points(meters)
        guard barLen > 8 else { return }

        let x0: CGFloat = 16
        let y0: CGFloat = size.height - 18
        let color = ink.opacity(0.7)

        // alternating filled/empty half-meter (or half-step) segments
        let segments = 4
        let segLen = barLen / CGFloat(segments)
        for i in 0..<segments {
            let rect = CGRect(x: x0 + CGFloat(i) * segLen, y: y0 - 3, width: segLen, height: 6)
            if i % 2 == 0 {
                context.fill(Path(rect), with: .color(color))
            } else {
                context.stroke(Path(rect), with: .color(color), style: StrokeStyle(lineWidth: 0.75))
            }
        }
        let label = meters < 1 ? String(format: "%.1f m", meters) : String(format: "%.0f m", meters)
        let resolved = context.resolve(
            Text(label).font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
        )
        context.draw(resolved, at: CGPoint(x: x0 + barLen + 6, y: y0), anchor: .leading)
    }

    private func drawRotatedLabel(_ context: GraphicsContext, _ string: String,
                                  at point: CGPoint, angle: Double) {
        var a = angle
        if a > .pi / 2 || a < -.pi / 2 { a += .pi }   // keep upright
        var layer = context
        layer.translateBy(x: point.x, y: point.y)
        layer.rotate(by: .radians(a))
        let resolved = layer.resolve(
            Text(string)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
        )
        layer.draw(resolved, at: .zero, anchor: .center)
    }

    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        self < lo ? lo : (self > hi ? hi : self)
    }
}

#Preview("Rectangle") {
    FloorPlanView(room: .mock)
        .frame(height: 340)
        .padding()
}

#Preview("L-shaped") {
    FloorPlanView(room: .mockLShaped)
        .frame(height: 340)
        .padding()
}
