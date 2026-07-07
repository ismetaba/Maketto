import SwiftUI
import UIKit

/// Whole-home map: many rooms in one shared frame, each with its own soft tint
/// (robot-vacuum-map style, tuned to the Maketto palette) and a centred
/// name + area label. Walls and openings are drawn once from the de-duplicated
/// union. Tap a room to select it; tap empty paper to deselect.
///
/// Pan/zoom live in a `PlanCamera` that the SCREEN owns, so floating chrome
/// (zoom buttons, fit) and the canvas gestures drive one shared camera.
/// Reuses FloorPlanRenderer.
struct WholeHomePlanView: View {
    let rooms: [RoomModel]
    /// Interactive maps get gestures, the metric grid and room labels; a
    /// non-interactive plan is a calm static thumbnail.
    var interactive: Bool = true
    var selectedRoomID: UUID?
    /// External camera; when nil (thumbnails, previews) an internal one is used.
    var camera: PlanCamera?
    /// Called with the tapped room, or nil when empty paper was tapped.
    var onSelect: ((UUID?) -> Void)?

    @State private var fallbackCamera = PlanCamera()
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragLive: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    private var cam: PlanCamera { camera ?? fallbackCamera }
    private var dark: Bool { colorScheme == .dark }

    private var cWall: Color { Color(light: Brand.evergreen, dark: Color(hex: 0xD9C088)) }
    private var cDoor: Color { Color(light: Color(hex: 0x99793A), dark: Color(hex: 0xC8A862)) }
    private var cWindow: Color { Color(light: Color(hex: 0x5E7E61), dark: Color(hex: 0xA8BFAB)) }
    private var cPaper: Color { Brand.surface }

    var body: some View {
        if PlanGeometry.worldBounds(rooms) == nil {
            if interactive {
                ContentUnavailableView("Plan yok", systemImage: "square.dashed")
            } else {
                Color.clear
            }
        } else if interactive {
            // Read the camera at BODY level so observation ties re-rendering to
            // it; the canvas then interpolates plain values.
            let zoom = cam.zoom * pinch
            let pan = CGSize(width: cam.pan.width + dragLive.width,
                             height: cam.pan.height + dragLive.height)
            GeometryReader { geo in
                AnimatedPlanCanvas(zoom: zoom, pan: pan) { context, size, z, p in
                    draw(context, size: size, zoom: z, pan: p)
                }
                .contentShape(Rectangle())
                .gesture(navigationGesture)
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        selectRoom(at: value.location, in: geo.size)
                    }
                )
            }
        } else {
            Canvas { context, size in
                draw(context, size: size, zoom: 1, pan: .zero)
            }
            .allowsHitTesting(false)
        }
    }

    private var navigationGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in cam.commitPinch(value.magnification) }
            .simultaneously(with:
                DragGesture()
                    .updating($dragLive) { value, state, _ in state = value.translation }
                    .onEnded { value in cam.commitPan(value.translation) }
            )
    }

    private func selectRoom(at point: CGPoint, in size: CGSize) {
        guard let onSelect else { return }
        guard let base = PlanGeometry.fit(rooms, in: size, padding: 28, maxScale: 120) else { return }
        let t = base.composed(in: size, zoom: cam.zoom, pan: cam.pan)
        let world = t.unapply(point)

        // Among rooms whose polygon contains the tap, pick the smallest (innermost).
        var hit: (id: UUID, area: Double)?
        for room in rooms {
            if let poly = PlanGeometry.floorPolygon(room), PlanGeometry.contains(poly, world) {
                let a = PlanGeometry.area(of: room)
                if hit == nil || a < hit!.area { hit = (room.id, a) }
            }
        }
        if let hit { onSelect(hit.id); return }

        // Rooms whose walls never closed into a polygon stay reachable across
        // their whole footprint (bbox + a little slop); a tap on empty paper
        // deselects.
        var boxHit: (id: UUID, area: Double)?
        for room in rooms {
            guard PlanGeometry.floorPolygon(room) == nil,
                  let b = PlanGeometry.worldBounds(room) else { continue }
            guard b.insetBy(dx: -0.4, dy: -0.4).contains(CGPoint(x: world.x, y: world.z))
            else { continue }
            let a = Double(b.width * b.height)
            if boxHit == nil || a < boxHit!.area { boxHit = (room.id, a) }
        }
        onSelect(boxHit?.id)
    }

    private func draw(_ context: GraphicsContext, size: CGSize, zoom: CGFloat, pan: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cPaper))
        guard let base = PlanGeometry.fit(rooms, in: size, padding: 28, maxScale: 120) else { return }
        let t = base.composed(in: size, zoom: zoom, pan: pan)

        if interactive {
            FloorPlanRenderer.drawGrid(context, size: size, t: t, dark: dark)
        }

        // Every room gets its own soft tint, stable by position in the home.
        for (i, room) in rooms.enumerated() {
            FloorPlanRenderer.drawFloor(room, into: context, t: t,
                                        floor: RoomPalette.tint(i).fill)
        }

        // Walls + openings drawn ONCE from the de-duplicated union, so a shared
        // wall never doubles up into a crossing sliver.
        let ink = PlanInk(paper: cPaper, floor: .clear, wall: cWall, door: cDoor, window: cWindow)
        FloorPlanRenderer.drawStructure(
            walls: PlanGeometry.dropOffAxisOutliers(PlanGeometry.deduped(rooms.flatMap(\.walls))),
            openings: PlanGeometry.deduped(rooms.flatMap(\.openings)),
            centroid: HomeGeometry.bboxCenter(of: rooms),
            objects: [], into: context, t: t, ink: ink, showFurniture: false
        )

        // Selection: soft glow + crisp outline in the room's own accent.
        if let id = selectedRoomID,
           let idx = rooms.firstIndex(where: { $0.id == id }),
           let poly = PlanGeometry.floorPolygon(rooms[idx]) {
            let accent = RoomPalette.tint(idx).accent
            var p = Path(); p.addLines(poly.map { t.apply($0) }); p.closeSubpath()
            context.stroke(p, with: .color(accent.opacity(0.30)),
                           style: StrokeStyle(lineWidth: 10, lineJoin: .round))
            context.stroke(p, with: .color(accent),
                           style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
        }

        // Labels last, so neighbouring fills never cover text (skipped on
        // static thumbnails, where they'd be unreadably small anyway).
        if interactive {
            for (i, room) in rooms.enumerated() {
                drawLabel(context, room: room, tint: RoomPalette.tint(i), t: t)
            }
        }
    }

    private func drawLabel(_ context: GraphicsContext, room: RoomModel,
                           tint: RoomTint, t: PlanGeometry.Transform) {
        guard let centroid = PlanGeometry.roomCenter(room) else { return }
        let extent = (PlanGeometry.worldBounds(room).map { min($0.width, $0.height) } ?? 0) * t.scale
        guard extent >= 26 else { return }   // too small at this zoom — keep the map calm
        let center = t.apply(centroid)

        let nameText = context.resolve(
            Text(room.name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint.accent)
        )
        if extent < 54 {
            context.draw(nameText, at: center, anchor: .center)
            return
        }
        context.draw(nameText, at: CGPoint(x: center.x, y: center.y - 12), anchor: .center)
        let areaText = context.resolve(
            Text(MeasurementFormat.squareMeters(PlanGeometry.area(of: room)))
                .font(.display(22))
                .foregroundColor(Brand.textPrimary)
        )
        context.draw(areaText, at: CGPoint(x: center.x, y: center.y + 10), anchor: .center)
    }
}

#Preview {
    WholeHomePlanView(rooms: [
        RoomModel.mockLShaped,
        HomeGeometry.transform(.mock, by: Pose2D(translation: Point2D(x: 5.2, z: 0)))
    ])
    .frame(height: 420)
    .background(Brand.surface)
}
