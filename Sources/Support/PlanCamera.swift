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
    var isIdentity: Bool { zoom == 1 && pan == .zero }

    // MARK: - Button controls (zoom about the view centre)

    func zoomIn() { setZoom(zoom * Self.zoomStep) }
    func zoomOut() { setZoom(zoom / Self.zoomStep) }
    func reset() { zoom = 1; pan = .zero }

    /// Keeps the world point currently at the view centre fixed while zooming:
    /// with `offset = c + (fit - c)·z + pan`, that point stays put iff the pan
    /// scales by the zoom ratio.
    private func setZoom(_ target: CGFloat) {
        let z = min(max(target, Self.minZoom), Self.maxZoom)
        guard z != zoom else { return }
        let ratio = z / zoom
        pan = CGSize(width: pan.width * ratio, height: pan.height * ratio)
        zoom = z
    }

    // MARK: - Gesture commits (anchor-free, matching the live gesture compose)

    func commitPinch(_ magnification: CGFloat) {
        zoom = min(max(zoom * magnification, Self.minZoom), Self.maxZoom)
    }

    func commitPan(_ translation: CGSize) {
        pan.width += translation.width
        pan.height += translation.height
    }
}
