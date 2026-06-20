import Foundation
import Observation

#if canImport(RoomPlan)
import RoomPlan
import ARKit
#endif

/// Drives a whole-home scan as ONE continuous capture: the user walks through the
/// whole home, taps "Bitir" once, and the software splits the result into rooms by
/// RoomPlan's detected sections. The user fixes names (or anything wrong) in review.
@MainActor
@Observable
final class HomeScanner {
    enum State: Equatable {
        case idle
        case scanning
        case processing
        case review([RoomModel])
        case failed(String)
        case unsupported
    }

    let isSupported: Bool
    private(set) var state: State
    /// roomModel.id -> exported USDZ (empty for the split flow until per-room export lands).
    private(set) var modelURLs: [UUID: URL] = [:]

    #if canImport(RoomPlan)
    @ObservationIgnored private(set) var arSession = ARSession()
    @ObservationIgnored private weak var captureSession: RoomCaptureSession?
    @ObservationIgnored private lazy var delegate = SessionDelegate(owner: self)
    @ObservationIgnored private var didConsumeCapture = false
    #endif

    init() {
        #if canImport(RoomPlan)
        isSupported = RoomCaptureSession.isSupported
        #else
        isSupported = false
        #endif
        state = isSupported ? .idle : .unsupported
    }

    #if canImport(RoomPlan)
    /// Wired by the capture view once it owns a RoomCaptureView/session.
    func bind(session: RoomCaptureSession) {
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
    }

    func reset() {
        captureSession?.stop()
        captureSession?.delegate = nil
        captureSession = nil
        arSession = ARSession()         // fresh AR world frame for the next scan
        didConsumeCapture = false
        modelURLs.removeAll()
        state = isSupported ? .idle : .unsupported
    }

    // Delivered on the main actor by the delegate hop.
    fileprivate func didEnd(_ data: CapturedRoomData) {
        guard case .processing = state, !didConsumeCapture else { return }
        didConsumeCapture = true
        Task { @MainActor in
            do {
                let captured = try await RoomBuilder(options: [.beautifyObjects])
                    .capturedRoom(from: data)
                let rooms = HomeGeometry.straightened(RoomModelConverter.splitRooms(from: captured))
                state = .review(RoomNaming.assignNames(rooms))
            } catch {
                state = .failed("Tarama işlenemedi. Lütfen evi yavaşça, tüm odaları kapsayarak tekrar tarayın.")
            }
        }
    }

    fileprivate func didFail(_ message: String) {
        guard !didConsumeCapture else { return }
        didConsumeCapture = true
        state = .failed(message)
    }
    #endif
}

#if canImport(RoomPlan)
/// Non-isolated so the SDK can call it on any thread; we hop to the main actor.
final class SessionDelegate: NSObject, RoomCaptureSessionDelegate {
    weak var owner: HomeScanner?

    init(owner: HomeScanner) {
        self.owner = owner
        super.init()
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData, error: (any Error)?) {
        let message = error?.localizedDescription
        Task { @MainActor [weak owner] in
            if let message {
                owner?.didFail(message)
            } else {
                owner?.didEnd(data)
            }
        }
    }
}
#endif
