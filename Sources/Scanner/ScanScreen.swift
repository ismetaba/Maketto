import SwiftUI

/// F1 entry screen. Gates on LiDAR support, hosts the capture view while
/// scanning, then swaps to the verification/result UI.
struct ScanScreen: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    @State private var scanner = RoomScanner()

    var body: some View {
        content
            .navigationTitle("Scan Room")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if !scanner.isSupported {
            ContentUnavailableView {
                Label("LiDAR Required", systemImage: "camera.metering.unknown")
            } description: {
                Text("Room scanning needs a device with a LiDAR sensor (iPhone Pro or iPad Pro).")
            }
        } else {
            switch scanner.state {
            case .idle, .scanning, .processing:
                scanningView
            case .finished(let room):
                ScanResultView(
                    room: room,
                    modelURL: scanner.modelURL,
                    onSave: { name in
                        if let id = store.saveScannedRoom(room, name: name, modelURL: scanner.modelURL) {
                            router.popToRoot()
                            router.push(.roomDetail(id))
                        } else {
                            scanner.fail("Couldn't save this scan. Please try scanning again.")
                        }
                    },
                    onRetry: { scanner.reset() }
                )
            case .failed(let message):
                ContentUnavailableView {
                    Label("Scan Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { scanner.reset() }
                }
            case .unsupported:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var scanningView: some View {
        #if canImport(RoomPlan)
        RoomCaptureViewRepresentable(scanner: scanner)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) { scanControls }
            .onAppear { scanner.startScanning() }
        #else
        ContentUnavailableView("RoomPlan Unavailable", systemImage: "xmark.octagon")
        #endif
    }

    @ViewBuilder
    private var scanControls: some View {
        if case .processing = scanner.state {
            ProgressView("Processing scan…")
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 28)
        } else {
            Button {
                scanner.finishScanning()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
    }
}
