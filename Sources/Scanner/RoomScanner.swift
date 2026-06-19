import Foundation
import Observation

#if canImport(RoomPlan)
import RoomPlan
#endif

/// Main-actor state machine driving the F1 scan flow. Receives the finished
/// CapturedRoom from the representable's coordinator and converts it (off the
/// RoomPlan type, onto our portable RoomModel).
@MainActor
@Observable
final class RoomScanner {
    enum ScanState {
        case idle
        case scanning
        case processing
        case finished(RoomModel)
        case failed(String)
        case unsupported
    }

    /// Capability gate (LiDAR present). Constant for the object's lifetime.
    let isSupported: Bool

    private(set) var state: ScanState

    /// Wired up by the capture view; stops the RoomPlan session when the user
    /// taps Done. The processed result then arrives via the delegate.
    @ObservationIgnored var onFinishRequested: (() -> Void)?

    /// Exported USDZ of the last finished scan (temporary file), shown in 3D.
    private(set) var modelURL: URL?

    init() {
        #if canImport(RoomPlan)
        isSupported = RoomCaptureSession.isSupported
        #else
        isSupported = false
        #endif
        state = isSupported ? .idle : .unsupported
    }

    func startScanning() {
        guard isSupported else { return }
        if case .idle = state { state = .scanning }
    }

    /// User tapped Done — stop the session; the finished room arrives via the
    /// delegate (didStartProcessing -> didFinish).
    func finishScanning() {
        guard case .scanning = state else { return }
        state = .processing
        onFinishRequested?()
    }

    func didStartProcessing() {
        state = .processing
    }

    func didFail(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    /// Surface a non-Error failure (e.g. a save that returned nil).
    func fail(_ message: String) {
        state = .failed(message)
    }

    func reset() {
        modelURL = nil
        state = isSupported ? .idle : .unsupported
    }

    #if canImport(RoomPlan)
    func didFinish(_ captured: CapturedRoom) {
        let model = RoomModelConverter.makeRoomModel(from: captured, name: defaultRoomName())
        modelURL = exportUSDZ(captured)
        state = .finished(model)
    }

    /// Export the parametric room model to a temporary USDZ for 3D preview.
    private func exportUSDZ(_ captured: CapturedRoom) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).usdz")
        do {
            try captured.export(to: url, exportOptions: .parametric)
            return url
        } catch {
            return nil
        }
    }
    #endif

    private func defaultRoomName() -> String {
        // Include the time so rooms scanned on the same day get distinct defaults.
        "Room \(Date.now.formatted(date: .abbreviated, time: .shortened))"
    }
}
