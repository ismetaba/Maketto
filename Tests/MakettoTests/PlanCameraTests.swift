#if canImport(SwiftUI) && !canImport(MakettoCore)
import CoreGraphics
import Testing
@testable import Maketto

@MainActor
struct PlanCameraTests {
    private let size = CGSize(width: 390, height: 700)

    private func transform(_ camera: PlanCamera, pinch: PinchState = PinchState()) throws -> PlanGeometry.Transform {
        let base = try #require(PlanGeometry.fit(.mockLShaped, in: size))
        let live = camera.live(pinch: pinch, drag: .zero, in: size)
        return base.composed(in: size, zoom: live.zoom, pan: live.pan)
    }

    @Test func pinchKeepsThePointBetweenTheFingersFixed() throws {
        let camera = PlanCamera()
        camera.commitPan(CGSize(width: 40, height: -25))
        let anchor = CGPoint(x: 120, y: 480)
        let world = try transform(camera).unapply(anchor)

        let pinch = PinchState(scale: 2.5, anchor: anchor)
        let during = try transform(camera, pinch: pinch).apply(world)
        #expect(abs(during.x - anchor.x) < 1e-6 && abs(during.y - anchor.y) < 1e-6)

        camera.commitPinch(pinch, in: size)
        let after = try transform(camera).apply(world)
        #expect(abs(after.x - anchor.x) < 1e-6 && abs(after.y - anchor.y) < 1e-6)
        #expect(abs(camera.zoom - 2.5) < 1e-9)
    }

    @Test func zoomIsClampedAndStillAnchored() throws {
        let camera = PlanCamera()
        let anchor = CGPoint(x: 300, y: 200)
        let world = try transform(camera).unapply(anchor)
        camera.commitPinch(PinchState(scale: 100, anchor: anchor), in: size)
        #expect(camera.zoom == PlanCamera.maxZoom)
        let after = try transform(camera).apply(world)
        #expect(abs(after.x - anchor.x) < 1e-6 && abs(after.y - anchor.y) < 1e-6)
    }
}
#endif
