import SwiftUI

#if canImport(RoomPlan)
import RoomPlan

/// Bridges RoomPlan's guided `RoomCaptureView` into SwiftUI. The coordinator
/// receives the finished, post-processed `CapturedRoom` and hands it to the scanner.
struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let scanner: RoomScanner

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        context.coordinator.captureView = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        // Let the SwiftUI "Done" button stop this session.
        scanner.onFinishRequested = { [weak view] in
            view?.captureSession.stop()
        }
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> RoomScanCoordinator {
        RoomScanCoordinator(scanner: scanner)
    }

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: RoomScanCoordinator) {
        uiView.captureSession.stop()
    }
}

/// Top-level (not nested) so the @objc/NSObject runtime name is stable.
/// RoomPlan delivers these delegate callbacks on the main thread, so the type is
/// @MainActor and the conformance is marked `@preconcurrency` — that bridges the
/// SDK's pre-concurrency delegate protocol with a runtime main-actor check.
@MainActor
final class RoomScanCoordinator: NSObject, @preconcurrency RoomCaptureViewDelegate {
    let scanner: RoomScanner
    weak var captureView: RoomCaptureView?

    init(scanner: RoomScanner) {
        self.scanner = scanner
        super.init()
    }

    // RoomCaptureViewDelegate inherits NSCoding. The coordinator is never
    // archived, so these are inert; `nonisolated` satisfies NSCoding's
    // nonisolated requirements without crossing actor isolation.
    nonisolated required init?(coder: NSCoder) {
        fatalError("RoomScanCoordinator is not archivable")
    }

    nonisolated func encode(with coder: NSCoder) {}

    /// Return true to run RoomPlan's post-processing and present results.
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        scanner.didStartProcessing()
        return true
    }

    /// Delivers the finished, post-processed room (or an error).
    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        captureView?.captureSession.stop()
        if let error {
            scanner.didFail(error)
        } else {
            scanner.didFinish(processedResult)
        }
    }
}
#endif
