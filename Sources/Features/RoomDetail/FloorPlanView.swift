import SwiftUI
import UIKit

/// Active editing tool when the plan is in edit mode.
enum PlanTool: String, CaseIterable, Sendable {
    /// Drag corners / furniture, tap to select walls and furniture.
    case select
    /// Drag to draw a new wall (ends join corners or split walls).
    case draw
    /// Tap a wall or a piece of furniture to delete it.
    case erase
}

/// What is selected on the plan.
enum PlanSelection: Hashable, Sendable {
    case wall(UUID)
    case furniture(UUID)
}

/// Blueprint-style top-down floor plan of ONE room (Maketto visual language).
/// Tap a wall → it highlights and its measurement appears as a pill ON the model.
/// Pinch to zoom, drag to pan; external chrome (zoom buttons, fit) drives the
/// same `PlanCamera`. A dynamic metric grid sits behind. Per-room drawing is
/// shared with the whole-home plan via `FloorPlanRenderer`.
///
/// When `editing` is non-nil the plan enters edit mode, rendered from that live
/// graph: corner handles appear and `editTool` routes gestures (see PlanTool).
struct FloorPlanView: View {
    let room: RoomModel
    var furniture: [PlacedFurniture] = []
    var showScanObjects: Bool = false
    /// When false (e.g. a thumbnail) the plan is a static fitted render with
    /// no gestures or controls.
    var interactive: Bool = true
    /// External camera; when nil (thumbnails, previews) an internal one is used.
    var camera: PlanCamera?
    /// Screen regions covered by floating chrome (top bar, docks); pills are
    /// clamped inside so they never render off-screen or under the chrome.
    var chromeInsets: EdgeInsets = EdgeInsets()
    /// Non-nil puts the plan in edit mode, rendered from this live graph.
    var editing: EditableRoom?
    var editTool: PlanTool = .select
    /// External selection; when nil the plan keeps its own.
    var selection: Binding<PlanSelection?>?

    @State private var fallbackCamera = PlanCamera()
    @State private var localSelection: PlanSelection?
    @State private var drag: ActiveDrag?
    /// Live translation of an edit-mode pan (committed on release, like the
    /// read-mode pan, so it composes correctly with a simultaneous pinch).
    @State private var editPan: CGSize = .zero
    @GestureState private var pinch = PinchState()
    @GestureState private var dragLive: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    /// One edit-mode drag, keyed by where it started so an abandoned gesture
    /// (onEnded never delivered) can be detected and rolled back.
    private struct ActiveDrag: Equatable {
        var start: CGPoint
        var kind: Kind
        enum Kind: Equatable {
            case corner(id: UUID, grab: Point2D)       // grab = corner − finger
            case furniture(id: UUID, grab: Point2D)
            case drawing(start: Point2D, end: Point2D)
            /// `origin` = translation when panning began (a drag can turn
            /// into a pan mid-gesture when a pinch starts).
            case pan(origin: CGSize)
        }
    }

    private var cam: PlanCamera { camera ?? fallbackCamera }
    private var liveTranslation: CGSize {
        CGSize(width: dragLive.width + editPan.width, height: dragLive.height + editPan.height)
    }
    private var dark: Bool { colorScheme == .dark }
    private var currentSelection: PlanSelection? { selection?.wrappedValue ?? localSelection }

    private func select(_ value: PlanSelection?) {
        if let selection { selection.wrappedValue = value } else { localSelection = value }
    }

    // Blueprint treatment palette (light / dark)
    private var cWall: Color { Color(light: Brand.evergreen, dark: Color(hex: 0xD9C088)) }
    private var cFloor: Color { Color(light: Color(hex: 0xFBF7F0), dark: Color(white: 1, opacity: 0.028)) }
    private var cDoor: Color { Color(light: Color(hex: 0x99793A), dark: Color(hex: 0xC8A862)) }
    private var cWindow: Color { Color(light: Color(hex: 0x5E7E61), dark: Color(hex: 0xA8BFAB)) }
    private var cSel: Color { Color(light: Brand.clay, dark: Color(hex: 0xE0B68F)) }
    private var cPaper: Color { Brand.surface }

    var body: some View {
        if PlanGeometry.worldBounds(room, includeObjects: showScanObjects) == nil {
            if interactive {
                ContentUnavailableView("Plan yok", systemImage: "square.dashed",
                                       description: Text("Bu odada çizilecek duvar bulunamadı."))
            } else {
                Color.clear
            }
        } else if interactive {
            // Read camera + live graph at BODY level so observation ties
            // re-rendering to both; the canvas closure captures plain values.
            let scene = PlanScene(
                display: editing?.flattened() ?? room,
                items: editing?.furniture ?? furniture,
                corners: editing.map { Array($0.corners.values) },
                guides: editing?.snapGuides ?? .none,
                selection: currentSelection,
                drag: drag?.kind
            )
            let _ = (cam.zoom, cam.pan)   // track the camera at body level
            GeometryReader { geo in
                let live = cam.live(pinch: pinch, drag: liveTranslation, in: geo.size)
                AnimatedPlanCanvas(zoom: live.zoom, pan: live.pan) { context, size, z, p in
                    draw(context, size: size, zoom: z, pan: p, scene: scene)
                }
                .contentShape(Rectangle())
                .gesture(activeGesture(in: geo.size))
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        handleTap(at: value.location, in: geo.size)
                    }
                )
            }
            .accessibilityElement()
            .accessibilityLabel("Kat planı")
            .accessibilityValue(accessibilitySummary(scene.display, items: scene.items))
        } else {
            Canvas { context, size in
                draw(context, size: size, zoom: 1, pan: .zero,
                     scene: PlanScene(display: room, items: furniture, corners: nil,
                                      guides: .none, selection: nil, drag: nil))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Everything one frame draws, captured as plain values.
    private struct PlanScene {
        var display: RoomModel
        var items: [PlacedFurniture]
        var corners: [EditableRoom.Corner]?
        var guides: EditableRoom.SnapGuides
        var selection: PlanSelection?
        var drag: ActiveDrag.Kind?
    }

    private func accessibilitySummary(_ room: RoomModel, items: [PlacedFurniture]) -> String {
        var parts = ["\(MeasurementFormat.squareMeters(PlanGeometry.area(of: room)))",
                     "\(room.walls.count) duvar"]
        if !room.openings.isEmpty { parts.append("\(room.openings.count) açıklık") }
        if !items.isEmpty { parts.append("\(items.count) eşya") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Gestures

    private func activeGesture(in size: CGSize) -> AnyGesture<Void> {
        if let editing {
            return AnyGesture(
                pinchGesture(in: size)
                    .simultaneously(with: editDragGesture(in: size, editing: editing))
                    .map { _ in () }
            )
        }
        return AnyGesture(
            pinchGesture(in: size)
                .simultaneously(with:
                    DragGesture()
                        .updating($dragLive) { value, state, _ in state = value.translation }
                        .onEnded { value in cam.commitPan(value.translation) }
                )
                .map { _ in () }
        )
    }

    /// Pinch zoom anchored between the fingers.
    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = PinchState(scale: value.magnification, anchor: value.startLocation)
            }
            .onEnded { value in
                cam.commitPinch(PinchState(scale: value.magnification, anchor: value.startLocation),
                                in: size)
            }
    }

    private func editDragGesture(in size: CGSize, editing: EditableRoom) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if drag == nil || drag?.start != value.startLocation {
                    abandonDrag(editing)          // a previous gesture never ended
                    drag = ActiveDrag(start: value.startLocation,
                                      kind: beginDrag(at: value.startLocation, in: size, editing: editing))
                }
                // A second finger turned this into a pinch: never let it also
                // drag the corner / piece / wall the first finger landed on.
                if pinch.scale != 1, let current = drag {
                    switch current.kind {
                    case .corner, .furniture:
                        editing.cancelDrag()
                        drag?.kind = .pan(origin: value.translation)
                    case .drawing:
                        editing.setGuides(.none)
                        drag?.kind = .pan(origin: value.translation)
                    case .pan:
                        break
                    }
                }
                guard let current = drag, let w = worldPoint(value.location, in: size) else { return }
                switch current.kind {
                case .corner(let id, let grab):
                    editing.dragCorner(id, to: w + grab, snapTolerance: worldRadius(9, in: size))
                case .furniture(let id, let grab):
                    editing.dragFurniture(id, to: w + grab, snapTolerance: worldRadius(10, in: size))
                case .drawing(let start, _):
                    let (end, guides) = editing.snapped(w, tolerance: worldRadius(9, in: size),
                                                        extraAnchors: [start])
                    editing.setGuides(guides)
                    drag?.kind = .drawing(start: start, end: end)
                case .pan(let origin):
                    editPan = CGSize(width: value.translation.width - origin.width,
                                     height: value.translation.height - origin.height)
                }
            }
            .onEnded { value in
                guard let current = drag else { return }
                drag = nil
                switch current.kind {
                case .corner(let id, _):
                    editing.endCornerDrag(id, weldRadius: worldRadius(14, in: size))
                case .furniture:
                    editing.endFurnitureDrag()
                case .drawing(let start, let end):
                    editing.setGuides(.none)
                    if let id = editing.addWall(from: start, to: end, snapRadius: worldRadius(18, in: size)) {
                        select(.wall(id))
                        Haptics.success()
                    }
                case .pan(let origin):
                    editPan = .zero
                    cam.commitPan(CGSize(width: value.translation.width - origin.width,
                                         height: value.translation.height - origin.height))
                }
            }
    }

    /// Decide once per gesture what a drag does.
    private func beginDrag(at start: CGPoint, in size: CGSize, editing: EditableRoom) -> ActiveDrag.Kind {
        guard let w = worldPoint(start, in: size) else { return .pan(origin: .zero) }
        switch editTool {
        case .select:
            // Priority: a corner handle right under the finger, then a piece
            // the finger is inside, then a nearby corner, then a piece's edge.
            // (A small piece snapped into a room corner stays grabbable.)
            func grabCorner(_ radius: CGFloat) -> ActiveDrag.Kind? {
                guard let cid = editing.corner(near: w, within: worldRadius(radius, in: size)),
                      let p = editing.cornerPosition(cid) else { return nil }
                editing.beginCornerDrag()
                Haptics.light()
                return .corner(id: cid, grab: p - w)
            }
            func grabFurniture(slop: CGFloat) -> ActiveDrag.Kind? {
                guard let fid = editing.furnitureID(at: w, slop: worldRadius(slop, in: size)),
                      let item = editing.furnitureItem(fid) else { return nil }
                editing.beginFurnitureDrag()
                select(.furniture(fid))
                Haptics.light()
                return .furniture(id: fid, grab: item.center - w)
            }
            return grabCorner(12) ?? grabFurniture(slop: 0) ?? grabCorner(26)
                ?? grabFurniture(slop: 6) ?? .pan(origin: .zero)
        case .draw:
            let anchor = editing.corner(near: w, within: worldRadius(22, in: size))
                .flatMap { editing.cornerPosition($0) }
            let start = anchor ?? editing.snapped(w, tolerance: worldRadius(9, in: size)).0
            Haptics.light()
            return .drawing(start: start, end: start)
        case .erase:
            return .pan(origin: .zero)
        }
    }

    /// Roll back a drag whose gesture was cancelled without `onEnded`.
    private func abandonDrag(_ editing: EditableRoom) {
        guard let current = drag else { return }
        drag = nil
        switch current.kind {
        case .corner, .furniture: editing.cancelDrag()
        case .drawing: editing.setGuides(.none)
        case .pan: editPan = .zero
        }
    }

    // MARK: - Transform (shared by draw + hit-test)

    // The fit frame always uses the immutable `room`, so the plan never re-centres
    // under the finger while live geometry is being edited.
    private func planTransform(in size: CGSize) -> PlanGeometry.Transform? {
        let live = cam.live(pinch: pinch, drag: liveTranslation, in: size)
        return PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240, includeObjects: showScanObjects)
            .map { $0.composed(in: size, zoom: live.zoom, pan: live.pan) }
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
        let radius = worldRadius(24, in: size)
        let walls = editing?.materializedWalls() ?? room.walls
        let items = editing?.furniture ?? furniture

        if let editing, editTool == .erase {
            if let fid = editing.furnitureID(at: world, slop: worldRadius(4, in: size)) {
                withAnimation(.maketto) {
                    if currentSelection == .furniture(fid) { select(nil) }
                    editing.deleteFurniture(fid)
                }
                Haptics.light()
            } else if let id = editing.wall(near: world, within: radius) {
                withAnimation(.maketto) {
                    if currentSelection == .wall(id) { select(nil) }
                    editing.deleteWall(id)
                }
                Haptics.light()
            }
            return
        }
        if editing != nil, editTool == .draw { return }

        // Furniture first (it sits on top), then the closest wall.
        if let item = items.last(where: { FurnitureGeometry.contains($0, world, slop: worldRadius(4, in: size)) }) {
            withAnimation(.maketto) {
                select(currentSelection == .furniture(item.id) ? nil : .furniture(item.id))
            }
            Haptics.selection()
            return
        }
        var best: (id: UUID, dist: Double)?
        for wall in walls {
            let d = FloorGeometry.distance(from: world, to: wall)
            if best.map({ d < $0.dist }) ?? true { best = (wall.id, d) }
        }
        withAnimation(.maketto) {
            if let best, best.dist < radius {
                select(currentSelection == .wall(best.id) ? nil : .wall(best.id))
                Haptics.selection()
            } else {
                select(nil)
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ context: GraphicsContext, size: CGSize, zoom: CGFloat, pan: CGSize,
                      scene: PlanScene) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cPaper))
        // Fit to the immutable `room` for a stable frame; render the live scene.
        guard let base = PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240,
                                          includeObjects: showScanObjects) else { return }
        let t = base.composed(in: size, zoom: zoom, pan: pan)
        let clamp = CGRect(x: chromeInsets.leading + 6, y: chromeInsets.top + 6,
                           width: max(size.width - chromeInsets.leading - chromeInsets.trailing - 12, 1),
                           height: max(size.height - chromeInsets.top - chromeInsets.bottom - 12, 1))

        if interactive {
            FloorPlanRenderer.drawGrid(context, size: size, t: t, dark: dark)
        }

        let ink = PlanInk(paper: cPaper, floor: cFloor, wall: cWall, door: cDoor, window: cWindow)
        FloorPlanRenderer.drawRoom(scene.display, into: context, t: t, ink: ink,
                                   showScanObjects: showScanObjects)

        var selectedFurniture: UUID?
        if case .furniture(let id) = scene.selection { selectedFurniture = id }
        // Labels self-limit to pieces large enough on screen, so thumbnails
        // stay clean while exports and the live plan are labelled.
        FloorPlanRenderer.drawFurniture(scene.items, into: context, t: t, dark: dark,
                                        selectedID: selectedFurniture, selectionColor: cSel)

        drawGuides(context, size: size, guides: scene.guides, t: t)

        let centroid = PlanGeometry.centroid(scene.display)
        if case .wall(let id) = scene.selection,
           let wall = scene.display.walls.first(where: { $0.id == id }) {
            drawWallSelection(context, wall: wall, t: t, centroid: centroid, clamp: clamp)
        }
        if let id = selectedFurniture, let item = scene.items.first(where: { $0.id == id }) {
            let bottom = FurnitureGeometry.footprint(item).map { t.apply($0).y }.max() ?? 0
            FloorPlanRenderer.drawPill(context, text: item.sizeLabel,
                                       at: CGPoint(x: t.apply(item.center).x, y: bottom + 18),
                                       fill: cSel, fontSize: 12, within: clamp)
        }

        if let corners = scene.corners, editTool != .erase {
            drawHandles(context, corners: corners, t: t, drag: scene.drag)
        }
        if case .corner(let id, _) = scene.drag, let editing {
            for wall in editing.walls(at: id) {
                drawLiveLength(context, wall: wall, t: t, centroid: centroid, clamp: clamp)
            }
        }
        if case .drawing(let start, let end) = scene.drag {
            drawWallPreview(context, from: start, to: end, t: t, clamp: clamp)
        }
    }

    private func drawHandles(_ context: GraphicsContext, corners: [EditableRoom.Corner],
                             t: PlanGeometry.Transform, drag: ActiveDrag.Kind?) {
        var active: UUID?
        if case .corner(let id, _) = drag { active = id }
        let small = editTool == .draw
        for corner in corners {
            let p = t.apply(corner.p)
            let r: CGFloat = corner.id == active ? 9 : (small ? 4.5 : 6)
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(cPaper))
            context.stroke(Circle().path(in: rect), with: .color(cSel),
                           style: StrokeStyle(lineWidth: corner.id == active ? 3 : 2.5))
        }
    }

    /// Dashed alignment guides across the canvas while a drag is snapped.
    private func drawGuides(_ context: GraphicsContext, size: CGSize,
                            guides: EditableRoom.SnapGuides, t: PlanGeometry.Transform) {
        let style = StrokeStyle(lineWidth: 1, dash: [6, 5])
        if let x = guides.x {
            let sx = t.apply(Point2D(x: x, z: 0)).x
            var p = Path(); p.move(to: CGPoint(x: sx, y: 0)); p.addLine(to: CGPoint(x: sx, y: size.height))
            context.stroke(p, with: .color(cSel.opacity(0.7)), style: style)
        }
        if let z = guides.z {
            let sy = t.apply(Point2D(x: 0, z: z)).y
            var p = Path(); p.move(to: CGPoint(x: 0, y: sy)); p.addLine(to: CGPoint(x: size.width, y: sy))
            context.stroke(p, with: .color(cSel.opacity(0.7)), style: style)
        }
    }

    private func drawWallSelection(_ context: GraphicsContext, wall: Wall, t: PlanGeometry.Transform,
                                   centroid: Point2D, clamp: CGRect) {
        let a = t.apply(wall.start), b = t.apply(wall.end)
        var hl = Path(); hl.move(to: a); hl.addLine(to: b)
        let wpt = max(t.points(wall.thickness), 3) + 5
        context.stroke(hl, with: .color(cSel.opacity(0.92)),
                       style: StrokeStyle(lineWidth: wpt, lineCap: .round))
        FloorPlanRenderer.drawPill(context, text: MeasurementFormat.meters(wall.length),
                                   at: outwardPoint(wall, t: t, centroid: centroid, distance: 28),
                                   fill: cSel, fontSize: 14, within: clamp)
    }

    /// Smaller live length pill for the walls moving with a dragged corner.
    private func drawLiveLength(_ context: GraphicsContext, wall: Wall, t: PlanGeometry.Transform,
                                centroid: Point2D, clamp: CGRect) {
        FloorPlanRenderer.drawPill(context, text: MeasurementFormat.meters(wall.length),
                                   at: outwardPoint(wall, t: t, centroid: centroid, distance: 22),
                                   fill: cWall.opacity(0.9), fontSize: 12, within: clamp)
    }

    private func drawWallPreview(_ context: GraphicsContext, from start: Point2D, to end: Point2D,
                                 t: PlanGeometry.Transform, clamp: CGRect) {
        let a = t.apply(start), b = t.apply(end)
        var p = Path(); p.move(to: a); p.addLine(to: b)
        context.stroke(p, with: .color(cSel), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
        for q in [a, b] {
            let rect = CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)
            context.fill(Circle().path(in: rect), with: .color(cSel))
        }
        let length = start.distance(to: end)
        if length >= 0.05 {
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 22)
            FloorPlanRenderer.drawPill(context, text: MeasurementFormat.meters(length),
                                       at: mid, fill: cSel, fontSize: 13, within: clamp)
        }
    }

    /// Screen point `distance` pts outside the wall's midpoint (away from the room).
    private func outwardPoint(_ wall: Wall, t: PlanGeometry.Transform, centroid: Point2D,
                              distance: CGFloat) -> CGPoint {
        let d = PlanGeometry.dimensionLabel(for: wall, interiorReference: centroid)
        let mid = t.apply(d.midpoint)
        let tip = t.apply(d.midpoint + d.outwardNormal)
        var nx = tip.x - mid.x, ny = tip.y - mid.y
        let nl = hypot(nx, ny)
        if nl > 0 { nx /= nl; ny /= nl }
        return CGPoint(x: mid.x + nx * distance, y: mid.y + ny * distance)
    }
}

#Preview("Rectangle") {
    FloorPlanView(room: .mock)
        .frame(height: 360)
        .background(Brand.surface)
}

#Preview("L-shaped + furniture") {
    FloorPlanView(room: .mockLShaped, furniture: [
        FurnitureCatalog.presets[0].instantiate(at: Point2D(x: 3.6, z: 3.8), rotation: .pi),
        FurnitureCatalog.presets[11].instantiate(at: Point2D(x: 1.2, z: 1.0)),
    ])
    .frame(height: 420)
    .background(Brand.surface)
}
