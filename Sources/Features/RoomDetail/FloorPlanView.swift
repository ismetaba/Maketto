import SwiftUI
import UIKit

/// Blueprint-style top-down floor plan of ONE room (Maketto visual language).
/// Tap a wall → it highlights and its measurement appears as a pill ON the model.
/// Pinch to zoom, drag to pan, the fit button re-centers. A dynamic metric grid
/// sits behind. Per-room drawing is shared with the whole-home plan via
/// `FloorPlanRenderer`.
struct FloorPlanView: View {
    let room: RoomModel
    var showFurniture: Bool = false
    /// When false (e.g. a library thumbnail) the plan is a static fitted render
    /// with no gestures or controls.
    var interactive: Bool = true

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var selectedWallID: UUID?
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragLive: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveZoom: CGFloat { zoom * pinch }
    private var effectivePan: CGSize {
        CGSize(width: pan.width + dragLive.width, height: pan.height + dragLive.height)
    }
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
                ContentUnavailableView("No Floor Plan", systemImage: "square.dashed")
            } else {
                Color.clear
            }
        } else if interactive {
            GeometryReader { geo in
                Canvas { context, size in
                    draw(context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(navigationGesture)
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        selectWall(at: value.location, in: geo.size)
                    }
                )
                .overlay(alignment: .bottomTrailing) { fitButton }
            }
        } else {
            Canvas { context, size in
                draw(context, size: size)
            }
            .allowsHitTesting(false)
        }
    }

    private var navigationGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = (zoom * value.magnification).clamped(0.4, 8) }
            .simultaneously(with:
                DragGesture()
                    .updating($dragLive) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                    }
            )
    }

    private var fitButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                zoom = 1; pan = .zero; selectedWallID = nil
            }
        } label: {
            Image(systemName: "viewfinder")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Brand.hairline, lineWidth: 0.5))
        }
        .padding(16)
    }

    // MARK: - Transform (shared by draw + hit-test)

    private func transform(base: PlanGeometry.Transform, size: CGSize) -> PlanGeometry.Transform {
        let z = effectiveZoom
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return PlanGeometry.Transform(
            origin: base.origin,
            scale: base.scale * z,
            offset: CGPoint(x: c.x + (base.offset.x - c.x) * z + effectivePan.width,
                            y: c.y + (base.offset.y - c.y) * z + effectivePan.height)
        )
    }

    private func selectWall(at point: CGPoint, in size: CGSize) {
        guard let base = PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240,
                                          includeObjects: showFurniture) else { return }
        let t = transform(base: base, size: size)
        let world = t.unapply(point)
        var best: (id: UUID, dist: Double)?
        for wall in room.walls {
            let d = FloorGeometry.distance(from: world, to: wall)
            if best == nil || d < best!.dist { best = (wall.id, d) }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let best, best.dist < 0.5 {
                selectedWallID = (selectedWallID == best.id) ? nil : best.id
            } else {
                selectedWallID = nil
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cPaper))
        guard let base = PlanGeometry.fit(room, in: size, padding: 28, maxScale: 240,
                                          includeObjects: showFurniture) else { return }
        let t = transform(base: base, size: size)

        FloorPlanRenderer.drawGrid(context, size: size, t: t, dark: dark)

        let ink = PlanInk(paper: cPaper, floor: cFloor, wall: cWall, door: cDoor, window: cWindow)
        FloorPlanRenderer.drawRoom(room, into: context, t: t, ink: ink, showFurniture: showFurniture)

        if let id = selectedWallID, let wall = room.walls.first(where: { $0.id == id }) {
            let centroid = PlanGeometry.centroid(room)
            drawSelection(context, wall: wall, t: t, centroid: centroid)
        }
    }

    private func drawSelection(_ context: GraphicsContext, wall: Wall,
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
        let pillCenter = CGPoint(x: mid.x + nx * 28, y: mid.y + ny * 28)

        let resolved = context.resolve(
            Text(d.text).font(.system(size: 14, weight: .heavy)).foregroundColor(.white)
        )
        let ts = resolved.measure(in: CGSize(width: 240, height: 60))
        let w = ts.width + 22, h = ts.height + 12
        let rect = CGRect(x: pillCenter.x - w / 2, y: pillCenter.y - h / 2, width: w, height: h)
        context.fill(Capsule().path(in: rect), with: .color(cSel))
        context.draw(resolved, at: pillCenter, anchor: .center)
    }

}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        self < lo ? lo : (self > hi ? hi : self)
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
