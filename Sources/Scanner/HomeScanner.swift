import Foundation
import Observation
import AVFoundation

#if canImport(RoomPlan)
@preconcurrency import RoomPlan
@preconcurrency import ARKit
#endif

/// Drives a whole-home scan as ONE continuous capture: the user walks through the
/// whole home, taps "Bitir" once, and the software splits the result into rooms by
/// RoomPlan's detected sections. The user fixes names (or anything wrong) in review.
@MainActor
@Observable
final class HomeScanner {
    enum State: Equatable {
        /// Checking / requesting camera permission.
        case preparing
        /// Permission granted; the capture view is about to start the session.
        case idle
        case scanning
        case processing
        case review([RoomModel])
        case failed(String)
        case permissionDenied
        case unsupported
    }

    let isSupported: Bool
    private(set) var state: State
    /// roomModel.id -> exported USDZ (empty for the split flow).
    private(set) var modelURLs: [UUID: URL] = [:]

    #if canImport(RoomPlan)
    @ObservationIgnored private(set) var arSession = ARSession()
    /// Held STRONGLY: the session must outlive the view's teardown until its
    /// final `didEndWith` callback arrives, or the scan is lost mid-processing.
    @ObservationIgnored private var captureSession: RoomCaptureSession?
    @ObservationIgnored private var sessionDelegate: SessionDelegate?
    /// Bumped per session; callbacks from an older session are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var didConsumeCapture = false
    #endif

    init() {
        #if canImport(RoomPlan)
        isSupported = RoomCaptureSession.isSupported
        #else
        isSupported = false
        #endif
        state = isSupported ? .preparing : .unsupported
    }

    /// Resolve camera permission before the capture view mounts, so a denial
    /// gets a clear screen instead of a cryptic session error.
    func prepare() async {
        guard state == .preparing else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .idle
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard state == .preparing else { return }
            state = granted ? .idle : .permissionDenied
        default:
            state = .permissionDenied
        }
    }

    #if canImport(RoomPlan)
    /// Wired by the capture view once it owns a RoomCaptureView/session.
    func bind(session: RoomCaptureSession) {
        guard captureSession !== session else { return }
        generation += 1
        didConsumeCapture = false
        let delegate = SessionDelegate(owner: self, generation: generation)
        sessionDelegate = delegate
        captureSession = session
        session.delegate = delegate
        session.run(configuration: RoomCaptureSession.Configuration())
        // Defer the observable mutation out of the SwiftUI view-update pass.
        Task { @MainActor in if case .idle = self.state { self.state = .scanning } }
    }

    /// "Bitir" — stop the single capture and split it into rooms.
    func finish() {
        guard case .scanning = state else { return }
        state = .processing
        captureSession?.stop()
        let expected = generation
        // Safety net: never leave the user on an endless spinner.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, self.generation == expected, case .processing = self.state else { return }
            self.didConsumeCapture = true
            self.state = .failed("Tarama işlenirken zaman aşımı oluştu. Lütfen tekrar deneyin.")
        }
    }

    /// Stop everything (leaving the screen). Late callbacks are ignored.
    func cancel() {
        generation += 1
        captureSession?.stop()
        captureSession?.delegate = nil
        captureSession = nil
        sessionDelegate = nil
        arSession.pause()
    }

    /// Start over with a fresh AR world frame.
    func reset() {
        cancel()
        arSession = ARSession()
        didConsumeCapture = false
        modelURLs.removeAll()
        state = isSupported ? .preparing : .unsupported
        Task { await prepare() }
    }

    // Delivered on the main actor by the delegate hop.
    fileprivate func didEnd(_ data: CapturedRoomData, generation: Int) {
        guard generation == self.generation, case .processing = state, !didConsumeCapture else { return }
        didConsumeCapture = true
        Task { @MainActor in
            do {
                let captured = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
                guard generation == self.generation else { return }
                let rooms = HomeGeometry.straightened(RoomModelConverter.splitRooms(from: captured))
                guard rooms.contains(where: { !$0.walls.isEmpty }) else {
                    state = .failed("Hiç duvar algılanamadı. Telefonu yavaşça gezdirip her duvarı kameraya gösterin.")
                    return
                }
                state = .review(RoomNaming.assignNames(rooms))
            } catch {
                guard generation == self.generation else { return }
                state = .failed("Tarama işlenemedi. Lütfen evi yavaşça, tüm odaları kapsayarak tekrar tarayın.")
            }
        }
    }

    fileprivate func didFail(generation: Int) {
        guard generation == self.generation, !didConsumeCapture else { return }
        didConsumeCapture = true
        // RoomPlan's localizedDescription is developer-facing; show our own copy.
        state = .failed("Tarama tamamlanamadı. Işığın yeterli olduğundan emin olun ve evi yavaşça, tüm odaları kapsayarak yeniden tarayın.")
    }
    #else
    func finish() {}
    func cancel() {}
    func reset() { state = isSupported ? .preparing : .unsupported }
    #endif
}

#if canImport(RoomPlan)
/// Non-isolated so the SDK can call it on any thread; we hop to the main actor.
final class SessionDelegate: NSObject, RoomCaptureSessionDelegate, @unchecked Sendable {
    private weak var owner: HomeScanner?
    private let generation: Int

    init(owner: HomeScanner, generation: Int) {
        self.owner = owner
        self.generation = generation
        super.init()
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData, error: (any Error)?) {
        let failed = error != nil
        let generation = self.generation
        let owner = self.owner
        let box = CaptureBox(data: data)
        Task { @MainActor in
            if failed {
                owner?.didFail(generation: generation)
            } else {
                owner?.didEnd(box.data, generation: generation)
            }
        }
    }
}

/// Carries the captured data across the actor hop (it is consumed exactly once,
/// on the main actor).
private struct CaptureBox: @unchecked Sendable {
    let data: CapturedRoomData
}

/// Keeps RoomCaptureView from running its own post-scan processing and result
/// screen — HomeScanner builds and presents the result itself.
final class CaptureViewDelegate: NSObject, RoomCaptureViewDelegate {
    override init() { super.init() }
    // RoomCaptureViewDelegate inherits NSCoding; nothing to encode.
    nonisolated required init?(coder: NSCoder) { super.init() }
    nonisolated func encode(with coder: NSCoder) {}

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        false
    }
}
#endif
