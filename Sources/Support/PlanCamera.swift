import SwiftUI
import Observation

/// Shared pan/zoom state for a plan canvas, owned by the SCREEN rather than the
/// canvas so floating chrome (zoom buttons, "fit" control) and the canvas
/// gestures all drive one camera — the robot-vacuum-app map pattern.
@MainActor
@Observable
final class PlanCamera {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    static let minZoom: CGFloat = 0.4
    static let maxZoom: CGFloat = 8
    /// One tap of the +/- buttons.
    static let zoomStep: CGFloat = 1.4

    var canZoomIn: Bool { zoom < Self.maxZoom - 0.001 }
    var canZoomOut: Bool { zoom > Self.minZoom + 0.001 }

    // MARK: - Button controls (zoom about the view centre)

    /// Button-driven changes animate (the canvases interpolate zoom/pan via
    /// `AnimatedPlanCanvas`); gesture commits below stay 1:1 un-animated.
    func zoomIn() { withAnimation(.maketto) { setZoom(zoom * Self.zoomStep) } }
    func zoomOut() { withAnimation(.maketto) { setZoom(zoom / Self.zoomStep) } }
    func reset() { withAnimation(.maketto) { zoom = 1; pan = .zero } }

    /// Keeps the world point currently at the view centre fixed while zooming:
    /// under `Transform.composed(in:zoom:pan:)`, that point stays put iff the
    /// pan scales by the zoom ratio.
    private func setZoom(_ target: CGFloat) {
        let z = Self.clamped(target)
        guard z != zoom else { return }
        let ratio = z / zoom
        pan = CGSize(width: pan.width * ratio, height: pan.height * ratio)
        zoom = z
    }

    // MARK: - Gesture commits (anchor-free, matching the live gesture compose)

    func commitPinch(_ magnification: CGFloat) {
        zoom = Self.clamped(zoom * magnification)
    }

    func commitPan(_ translation: CGSize) {
        pan.width += translation.width
        pan.height += translation.height
    }

    private static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minZoom), maxZoom)
    }
}

// MARK: - Camera composition

extension PlanGeometry.Transform {
    /// Compose this base fit with a user camera: zoom about the view centre,
    /// then translate by the pan. The ONE place the composition law lives:
    ///
    ///     offset' = c + (offset - c)·zoom + pan
    ///
    /// (`PlanCamera.setZoom` relies on exactly this law to keep the view
    /// centre fixed while button-zooming.)
    func composed(in size: CGSize, zoom: CGFloat, pan: CGSize) -> PlanGeometry.Transform {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return PlanGeometry.Transform(
            origin: origin,
            scale: scale * zoom,
            offset: CGPoint(x: c.x + (offset.x - c.x) * zoom + pan.width,
                            y: c.y + (offset.y - c.y) * zoom + pan.height)
        )
    }
}
