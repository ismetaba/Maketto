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
/// optional furniture). Shared by the single-room `FloorPlanView` and the
/// multi-room `WholeHomePlanView` — the only difference between them is the ink
/// and how many rooms they loop over.
enum FloorPlanRenderer {
    static func drawRoom(_ room: RoomModel, into context: GraphicsContext,
                         t: PlanGeometry.Transform, ink: PlanInk, showFurniture: Bool) {
        let centroid = PlanGeometry.centroid(room)

        if let poly = PlanGeometry.floorPolygon(room) {
            var path = Path()
            path.addLines(poly.map { t.apply($0) })
            path.closeSubpath()
            context.fill(path, with: .color(ink.floor))
        }

        for wall in room.walls {
            var p = Path()
            p.move(to: t.apply(wall.start))
            p.addLine(to: t.apply(wall.end))
            let wpt = max(t.points(wall.thickness), 2.5)
            context.stroke(p, with: .color(ink.wall),
                           style: StrokeStyle(lineWidth: wpt, lineCap: .square, lineJoin: .miter))
        }

        for opening in room.openings {
            guard let seg = PlanGeometry.openingSegment(opening, in: room, interiorReference: centroid)
            else { continue }
            drawOpening(context, opening: opening, seg: seg, t: t, ink: ink)
        }

        if showFurniture {
            for obj in room.detectedObjects {
                drawObject(context, obj: obj, t: t)
            }
        }
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

    private static func drawObject(_ context: GraphicsContext, obj: DetectedObject,
                                   t: PlanGeometry.Transform) {
        let corners = PlanGeometry.footprintCorners(obj).map { t.apply($0) }
        guard corners.count == 4 else { return }
        var path = Path(); path.addLines(corners); path.closeSubpath()
        let furn = Color(light: Color(hex: 0xF1E8D2), dark: Color(hex: 0xC8A862).opacity(0.16))
        let furnLine = Color(light: Color(hex: 0xCBB069), dark: Color(hex: 0xA8853C))
        context.fill(path, with: .color(furn))
        context.stroke(path, with: .color(furnLine), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
}
