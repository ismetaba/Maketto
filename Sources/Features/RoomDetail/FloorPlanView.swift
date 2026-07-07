import SwiftUI
import UIKit

/// Active editing tool when the plan is in edit mode.
enum PlanTool: String, CaseIterable, Sendable { case move, delete }

/// Blueprint-style top-down floor plan of ONE room (Maketto visual language).
/// Tap a wall → it highlights and its measurement appears as a pill ON the model.
/// Pinch to zoom, drag to pan; external chrome (zoom buttons, fit) drives the
/// same `PlanCamera`. A dynamic metric grid sits behind. Per-room drawing is
/// shared with the whole-home plan via `FloorPlanRenderer`.
///
/// When `editing` is non-nil the plan enters edit mode: corner handles appear,
/// dragging a handle moves every wall that joins there, and the active `editTool`
/// routes taps (move = inspect, delete = remove a wall). Read mode (editing == nil)
/// is byte-identical to before.
struct FloorPlanView: View {
    let room: RoomModel
    var showFurniture: Bool = false
    /// When false (e.g. a library thumbnail) the plan is a static fitted render
    /// with no gestures or controls.
    var interactive: Bool = true
    /// External camera; when nil (thumbnails, previews) an internal one is used.
    var camera: PlanCamera?
    /// Screen regions covered by floating chrome (top bar, docks); the
    /// measurement pill is clamped inside these so it never renders off-screen
    /// or under the chrome.
    var chromeInsets: EdgeInsets = EdgeInsets()
    /// Non-nil puts the plan in edit mode, rendered from this live graph.
    var editing: EditableRoom?
    var editTool: PlanTool = .move

    @State private var fallbackCamera = PlanCamera()
    @State private var selectedWallID: UUID?
    @State private var activeCorner: UUID?       // corner being dragged
    @State private var panBase: CGSize?          // camera pan at drag start (pan mode)
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragLive: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    private var cam: PlanCamera { camera ?? fallbackCamera }
    private var dark: Bool { colorScheme == .dark }

    // Blueprint treatment palette (light / dark)
    private var cWall: Color { Color(light: Brand.evergreen, dark: Color(hex: 0xD9C088)) }
    private var cFloor: Color { Color(light: Color(hex: 0xFBF7F0), dark: Color(white: 1, opacity: 0.028)) }
    private var cDoor: Color { Color(light: Color(hex: 0x99793A), dark: Color(hex: 0xC8A862)) }
    private var cWindow: Color { Color(light: Color(hex: 0x5E7E61), dark: Color(hex: 0xA8BFAB)) }
    private var cSel: Color { Color(light: Brand.clay, dark: Color(hex: 0xE0B68F)) }
    private var cPaper: Color { Brand.surface }

    var body: some View {
        if PlanGeometry.worldBounds(room, includeObjects: showFurniture) == nil {
            if interactive {
                ContentUnavailableView("Plan yok", systemImage: "square.dashed")
            } else {
                Color.clear
            }
        } else if interactive {
            // Read camera + live graph at BODY level so observation ties
            // re-rendering to both; the canvas closure captures plain values.
            let zoom = cam.zoom * pinch
            let pan = CGSize(width: cam.pan.width + dragLive.width,
                             height: cam.pan.height + dragLive.height)
            let display = editing?.flattened() ?? room
            let corners = editing.map { Array($0.corners.values) }
            GeometryReader { geo in
                AnimatedPlanCanvas(zoom: zoom, pan: pan) { context, size, z, p in
                    draw(context, size: size, zoom: z, pan: p,
                         display: display, corners: corners)
                }
                .contentShape(Rectangle())
                .gesture(activeGesture(in: geo.size))
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        handleTap(at: value.location, in: geo.size)
                    }
                )
            }
        } else {
            Canvas { context, size in
                draw(context, size: size, zoom: 1, pan: .zero, display: room, corners: nil)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Gestures

    private func activeGesture(in size: CGSize) -> AnyGesture<Void> {
        if let editing {
            return AnyGesture(editNavigationGesture(in: size, editing: editing).map { _ in () })
        }
        return AnyGesture(navigationGesture.map { _ in () })
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

    /// Edit-mode navigation: pinch still zooms; a drag grabs the nearest corner
    /// (move tool) or pans the canvas. Pan is gated by `activeCorner` so the plan
    /// never slides while a handle is being dragged.
    private func editNavigationGesture(in size: CGSize, editing: EditableRoom) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in cam.commitPinch(value.magnification) }
            .simultaneously(with: editDragGesture(in: size, editing: editing))
    }

    private func editDragGesture(in size: CGSize, editing: EditableRoom) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if activeCorner == nil, panBase == nil {
                    // Decide once: grab a corner (move tool) or start panning.
                    if editTool == .move,
                       let w = worldPoint(value.startLocation, in: size),
                       let cid = editing.corner(near: w, within: worldRadius(26, in: size)) {
                        activeCorner = cid
                        editing.beginCornerDrag()
                        Haptics.light()
                    } else {
                        panBase = cam.pan
                    }
                }
                if let cid = activeCorner, let w = worldPoint(value.location, in: size) {
                    editing.dragCorner(cid, to: w)
                } else if let base = panBase {
                    cam.pan = CGSize(width: base.width + value.translation.width,
                                     height: base.height + value.translation.height)
                }
            }
            .onEnded { value in
                if let cid = activeCorner {
                    editing.endCornerDrag(cid)
                    activeCorner = nil
                } else if let base = panBase {
                    cam.pan = CGSize(width: base.width + value.translation.width,
                                     height: base.height + value.translation.height)
                    panBase = nil
                }
            }
    }

    // MARK: - Transform (shared by draw + hit-test)

    // The fit frame always uses the immutable `room`, so the plan never re-centres
    // under the finger while live geometry is being edited.
    private func planTransform(in size: CGSize) -> PlanGeometry.Transform? {
        PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240, includeObjects: showFurniture)
            .map { $0.composed(in: size, zoom: cam.zoom * pinch,
                               pan: CGSize(width: cam.pan.width + dragLive.width,
                                           height: cam.pan.height + dragLive.height)) }
    }

    private func worldPoint(_ p: CGPoint, in size: CGSize) -> Point2D? {
        planTransform(in: size).map { $0.unapply(p) }
    }

    /// A screen-point hit radius expressed in world metres at the current zoom.
    private func worldRadius(_ screenPts: CGFloat, in size: CGSize) -> Double {
        guard let t = planTransform(in: size), t.scale > 0 else { return 0.3 }
        return Double(screenPts / t.scale)
    }

    private func handleTap(at point: CGPoint, in size: CGSize) {
        guard let world = worldPoint(point, in: size) else { return }
        if let editing {
            switch editTool {
            case .delete:
                if let id = editing.wall(near: world, within: worldRadius(26, in: size)) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if selectedWallID == id { selectedWallID = nil }
                        editing.deleteWall(id)
                    }
                    Haptics.light()
                }
            case .move:
                selectClosestWall(to: world, among: editing.materializedWalls(),
                                  within: worldRadius(26, in: size))
            }
        } else {
            selectClosestWall(to: world, among: room.walls, within: 0.5)
        }
    }

    private func selectClosestWall(to world: Point2D, among walls: [Wall], within: Double) {
        var best: (id: UUID, dist: Double)?
        for wall in walls {
            let d = FloorGeometry.distance(from: world, to: wall)
            if best == nil || d < best!.dist { best = (wall.id, d) }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let best, best.dist < within {
                selectedWallID = (selectedWallID == best.id) ? nil : best.id
                Haptics.selection()
            } else {
                selectedWallID = nil
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ context: GraphicsContext, size: CGSize, zoom: CGFloat, pan: CGSize,
                      display: RoomModel, corners: [EditableRoom.Corner]?) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cPaper))
        // Fit to the immutable `room` for a stable frame; render live `display`.
        guard let base = PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240,
                                          includeObjects: showFurniture) else { return }
        let t = base.composed(in: size, zoom: zoom, pan: pan)

        FloorPlanRenderer.drawGrid(context, size: size, t: t, dark: dark)

        let ink = PlanInk(paper: cPaper, floor: cFloor, wall: cWall, door: cDoor, window: cWindow)
        FloorPlanRenderer.drawRoom(display, into: context, t: t, ink: ink, showFurniture: showFurniture)

        if let id = selectedWallID, let wall = display.walls.first(where: { $0.id == id }) {
            drawSelection(context, size: size, wall: wall, t: t,
                          centroid: PlanGeometry.centroid(display))
        }

        if let corners { drawHandles(context, corners: corners, t: t) }
    }

    private func drawHandles(_ context: GraphicsContext, corners: [EditableRoom.Corner],
                             t: PlanGeometry.Transform) {
        for corner in corners {
            let p = t.apply(corner.p)
            let r: CGFloat = corner.id == activeCorner ? 9 : 6
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(cPaper))
            context.stroke(Circle().path(in: rect), with: .color(cSel),
                           style: StrokeStyle(lineWidth: corner.id == activeCorner ? 3 : 2.5))
        }
    }

    private func drawSelection(_ context: GraphicsContext, size: CGSize, wall: Wall,
                               t: PlanGeometry.Transform, centroid: Point2D) {
        let a = t.apply(wall.start), b = t.apply(wall.end)
        var hl = Path(); hl.move(to: a); hl.addLine(to: b)
        let wpt = max(t.points(wall.thickness), 3) + 5
        context.stroke(hl, with: .color(cSel.opacity(0.92)),
                       style: StrokeStyle(lineWidth: wpt, lineCap: .round))

        let d = PlanGeometry.dimensionLabel(for: wall, interiorReference: centroid,
                                            text: MeasurementFormat.meters(wall.length))
        let mid = t.apply(d.midpoint)
        let nTip = t.apply(d.midpoint + d.outwardNormal)
        var nx = nTip.x - mid.x, ny = nTip.y - mid.y
        let nl = hypot(nx, ny); if nl > 0 { nx /= nl; ny /= nl }

        let resolved = context.resolve(
            Text(d.text).font(.system(size: 14, weight: .heavy)).foregroundColor(.white)
        )
        let ts = resolved.measure(in: CGSize(width: 240, height: 60))
        let w = ts.width + 22, h = ts.height + 12

        // Clamp the pill inside the visible, chrome-free region so an outer
        // wall's measurement never renders off-screen or under the bars.
        var pillCenter = CGPoint(x: mid.x + nx * 28, y: mid.y + ny * 28)
        let minX = chromeInsets.leading + w / 2 + 6
        let maxX = size.width - chromeInsets.trailing - w / 2 - 6
        let minY = chromeInsets.top + h / 2 + 6
        let maxY = size.height - chromeInsets.bottom - h / 2 - 6
        if minX < maxX { pillCenter.x = min(max(pillCenter.x, minX), maxX) }
        if minY < maxY { pillCenter.y = min(max(pillCenter.y, minY), maxY) }

        let rect = CGRect(x: pillCenter.x - w / 2, y: pillCenter.y - h / 2, width: w, height: h)
        context.fill(Capsule().path(in: rect), with: .color(cSel))
        context.draw(resolved, at: pillCenter, anchor: .center)
    }

}

#Preview("Rectangle") {
    FloorPlanView(room: .mock)
        .frame(height: 360)
        .background(Brand.surface)
}

#Preview("L-shaped") {
    FloorPlanView(room: .mockLShaped)
        .frame(height: 360)
        .background(Brand.surface)
}
