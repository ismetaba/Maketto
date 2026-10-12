import SwiftUI

#if canImport(RoomPlan)
@preconcurrency import RoomPlan

/// Hosts RoomPlan's live coaching view over a SHARED ARSession so every room of
/// the home is captured in one world frame. We drive the session (not the view's
/// self-presenting result screen) via HomeScanner.
struct HomeCaptureViewRepresentable: UIViewRepresentable {
    let scanner: HomeScanner

    @MainActor
    final class Coordinator {
        /// RoomCaptureView holds its delegate weakly; keep it alive here.
        let viewDelegate = CaptureViewDelegate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero, arSession: scanner.arSession)
        view.delegate = context.coordinator.viewDelegate
        scanner.bind(session: view.captureSession)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
#endif
