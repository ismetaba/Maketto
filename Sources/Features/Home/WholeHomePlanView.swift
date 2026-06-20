import SwiftUI
import UIKit

/// Whole-home blueprint plan: many rooms in one shared frame, each with a
/// type-keyed floor fill and a centred name + area label. Tap a room to select
/// (rename in review, open in home detail). Reuses FloorPlanRenderer.
struct WholeHomePlanView: View {
    let rooms: [RoomModel]
    var interactive: Bool = true
    var selectedRoomID: UUID?
    var onSelect: ((UUID) -> Void)?

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var dragLive: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    private var effectiveZoom: CGFloat { zoom * pinch }
    private var effectivePan: CGSize {
        CGSize(width: pan.width + dragLive.width, height: pan.height + dragLive.height)
    }
    private var dark: Bool { colorScheme == .dark }

    private var cWall: Color { Color(light: Brand.evergreen, dark: Color(hex: 0xD9C088)) }
    private var cDoor: Color { Color(light: Color(hex: 0x99793A), dark: Color(hex: 0xC8A862)) }
    private var cWindow: Color { Color(light: Color(hex: 0x5E7E61), dark: Color(hex: 0xA8BFAB)) }
    private var cSel: Color { Color(light: Brand.clay, dark: Color(hex: 0xE0B68F)) }
    private var cPaper: Color { Brand.surface }

    var body: some View {
        if PlanGeometry.worldBounds(rooms) == nil {
            if interactive {
                ContentUnavailableView("Plan yok", systemImage: "square.dashed")
            } else {
                Color.clear
            }
        } else if interactive {
            GeometryReader { geo in
                Canvas { context, size in draw(context, size: size) }
                    .contentShape(Rectangle())
                    .gesture(navigationGesture)
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            selectRoom(at: value.location, in: geo.size)
                        }
                    )
                    .overlay(alignment: .bottomTrailing) { fitButton }
            }
        } else {
            Canvas { context, size in draw(context, size: size) }
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { zoom = 1; pan = .zero }
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

    private func selectRoom(at point: CGPoint, in size: CGSize) {
        guard let base = PlanGeometry.fit(rooms, in: size, padding: 28, maxScale: 120) else { return }
        let t = transform(base: base, size: size)
        let world = t.unapply(point)

        // Among rooms whose polygon contains the tap, pick the smallest (innermost).
        var hit: (id: UUID, area: Double)?
        for room in rooms {
            if let poly = PlanGeometry.floorPolygon(room), PlanGeometry.contains(poly, world) {
                let a = PlanGeometry.area(of: room)
                if hit == nil || a < hit!.area { hit = (room.id, a) }
            }
        }
        if let hit { onSelect?(hit.id); return }

        // Fallback so every room stays tappable: nearest room centre to the tap.
        var nearest: (id: UUID, dist: Double)?
        for room in rooms {
            guard let c = PlanGeometry.roomCenter(room) else { continue }
            let d = c.distance(to: world)
            if nearest == nil || d < nearest!.dist { nearest = (room.id, d) }
        }
        if let nearest { onSelect?(nearest.id) }
    }

    private func draw(_ context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cPaper))
        guard let base = PlanGeometry.fit(rooms, in: size, padding: 28, maxScale: 120) else { return }
        let t = transform(base: base, size: size)

        FloorPlanRenderer.drawGrid(context, size: size, t: t, dark: dark)

        // Floor fills per room (type-keyed; selected room reads warmer).
        for room in rooms {
            FloorPlanRenderer.drawFloor(room, into: context, t: t,
                                        floor: floorColor(room.kind, selected: room.id == selectedRoomID))
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

        // Selection outline on top of all fills/walls.
        if let id = selectedRoomID, let room = rooms.first(where: { $0.id == id }),
           let poly = PlanGeometry.floorPolygon(room) {
            var p = Path(); p.addLines(poly.map { t.apply($0) }); p.closeSubpath()
            context.stroke(p, with: .color(cSel), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
        }

        // Labels last, so neighbouring fills never cover text.
        for room in rooms { drawLabel(context, room: room, t: t) }
    }

    private func drawLabel(_ context: GraphicsContext, room: RoomModel, t: PlanGeometry.Transform) {
        // Every detected room gets a label, even if its walls don't close.
        guard let centroid = PlanGeometry.roomCenter(room) else { return }
        let extent = (PlanGeometry.worldBounds(room).map { min($0.width, $0.height) } ?? 0) * t.scale
        let center = t.apply(centroid)

        let nameText = context.resolve(
            Text(room.name.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Brand.textSecondary)
        )
        if extent < 46 {
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

    private func floorColor(_ kind: RoomKind?, selected: Bool) -> Color {
        let base: Color
        switch kind ?? .unidentified {
        case .livingRoom, .diningRoom:
            base = Color(light: Color(hex: 0xF6EFE0), dark: Color(white: 1, opacity: 0.05))
        case .bedroom:
            base = Color(light: Color(hex: 0xF1ECF1), dark: Color(white: 1, opacity: 0.06))
        case .bathroom, .kitchen:
            base = Color(light: Color(hex: 0xE8F0EF), dark: Color(hex: 0x87A189).opacity(0.14))
        case .hallway:
            base = Color(light: Color(hex: 0xF3EEE3), dark: Color(white: 1, opacity: 0.04))
        case .balcony:
            base = Color(light: Color(hex: 0xEAF1EA), dark: Color(hex: 0x87A189).opacity(0.12))
        case .unidentified:
            base = Color(light: Color(hex: 0xF7F2EA), dark: Color(white: 1, opacity: 0.045))
        }
        // Selected room reads via its outline; nudge the fill a touch warmer.
        return selected ? Brand.clay.opacity(dark ? 0.16 : 0.12) : base
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        self < lo ? lo : (self > hi ? hi : self)
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
