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

    // MARK: - Gestures

    /// Live (zoom, pan) for an in-flight pinch + drag. The pinch zooms about
    /// the point between the fingers (that world point stays under them):
    /// with the composition law, a point at view position A is fixed iff
    ///
    ///     pan' = (A − c)·(1 − m) + pan·m      (m = zoom ratio, c = view centre)
    ///
    /// The drag translation is added on top, unscaled.
    func live(pinch: PinchState, drag: CGSize, in size: CGSize) -> (zoom: CGFloat, pan: CGSize) {
        let z = Self.clamped(zoom * pinch.scale)
        let m = z / zoom
        let ax = pinch.anchor.x - size.width / 2
        let ay = pinch.anchor.y - size.height / 2
        return (z, CGSize(width: ax * (1 - m) + pan.width * m + drag.width,
                          height: ay * (1 - m) + pan.height * m + drag.height))
    }

    /// Commit a finished pinch (exactly what `live` showed, without the drag).
    func commitPinch(_ pinch: PinchState, in size: CGSize) {
        let result = live(pinch: pinch, drag: .zero, in: size)
        zoom = result.zoom
        pan = result.pan
    }

    func commitPan(_ translation: CGSize) {
        pan.width += translation.width
        pan.height += translation.height
    }

    static func clamped(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, minZoom), maxZoom)
    }
}

/// An in-flight pinch: magnification and where the fingers started (view pts).
struct PinchState: Equatable, Sendable {
    var scale: CGFloat = 1
    var anchor: CGPoint = .zero
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
