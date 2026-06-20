import Foundation
import Observation

#if canImport(RoomPlan)
import RoomPlan
import ARKit
#endif

/// Drives a whole-home scan: ONE persistent ARSession, walk room-to-room ending
/// each with stop(pauseARSession:false) to keep the world frame, accumulate
/// CapturedRoomData, then merge offline (RoomBuilder + StructureBuilder) into
/// per-room RoomModels with default names.
@MainActor
@Observable
final class HomeScanner {
    enum State: Equatable {
        case idle
        case scanning(roomCount: Int)   // rooms already captured
        case processing
        case review([RoomModel])
        case failed(String)
        case unsupported
    }

    let isSupported: Bool
    private(set) var state: State
    /// roomModel.id -> exported temporary USDZ.
    private(set) var modelURLs: [UUID: URL] = [:]

    #if canImport(RoomPlan)
    @ObservationIgnored let arSession = ARSession()
    @ObservationIgnored private weak var captureSession: RoomCaptureSession?
    @ObservationIgnored private var capturedData: [CapturedRoomData] = []
    @ObservationIgnored private lazy var delegate = SessionDelegate(owner: self)
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
        runRoom()
    }

    private func runRoom() {
        captureSession?.run(configuration: RoomCaptureSession.Configuration())
        state = .scanning(roomCount: capturedData.count)
    }

    /// "Sonraki Oda" — finish this room (keep AR tracking) and continue.
    func nextRoom() {
        captureSession?.stop(pauseARSession: false)
        // delegate.didEnd appends, then we re-run for the next room.
    }

    /// "Bitir" — finish the last room and merge everything.
    func finish() {
        state = .processing
        captureSession?.stop(pauseARSession: false)
    }

    func reset() {
        capturedData.removeAll()
        modelURLs.removeAll()
        state = isSupported ? .idle : .unsupported
    }

    // Called by the delegate (main actor).
    fileprivate func didEnd(_ data: CapturedRoomData) {
        capturedData.append(data)
        if case .processing = state {
            process()
        } else {
            runRoom()   // continue with the next room
        }
    }

    fileprivate func didFail(_ error: Error) {
        state = .failed(error.localizedDescription)
    }

    private func process() {
        let datas = capturedData
        Task { @MainActor in
            do {
                let roomBuilder = RoomBuilder(options: [.beautifyObjects])
                var rooms: [CapturedRoom] = []
                for data in datas {
                    rooms.append(try await roomBuilder.capturedRoom(from: data))
                }
                let structure = try await StructureBuilder(options: [.beautifyObjects])
                    .capturedStructure(from: rooms)

                var models: [RoomModel] = []
                var urls: [UUID: URL] = [:]
                for captured in structure.rooms {
                    let model = RoomModelConverter.makeRoomModel(from: captured, name: "")
                    if let url = try? exportUSDZ(captured) { urls[model.id] = url }
                    models.append(model)
                }
                modelURLs = urls
                state = .review(RoomNaming.assignNames(models))
            } catch {
                state = .failed("Odalar birleştirilemedi — odaları kapılardan geçerek ardışık tarayın.")
            }
        }
    }

    private func exportUSDZ(_ room: CapturedRoom) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).usdz")
        try room.export(to: url, exportOptions: .parametric)
        return url
    }
    #endif
}

#if canImport(RoomPlan)
/// RoomCaptureSessionDelegate is delivered on the main thread; the conformance is
/// @preconcurrency to bridge the SDK's pre-concurrency protocol.
@MainActor
final class SessionDelegate: NSObject, @preconcurrency RoomCaptureSessionDelegate {
    weak var owner: HomeScanner?

    init(owner: HomeScanner) {
        self.owner = owner
        super.init()
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData, error: (any Error)?) {
        if let error {
            owner?.didFail(error)
        } else {
            owner?.didEnd(data)
        }
    }
}
#endif
