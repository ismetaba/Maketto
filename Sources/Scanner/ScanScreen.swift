import SwiftUI

/// F1 scan flow: immersive live scan with a single confident "Bitti".
struct ScanScreen: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    @State private var scanner = RoomScanner()

    var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if !scanner.isSupported {
            unsupported
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
                            scanner.fail("Bu tarama kaydedilemedi. Lütfen tekrar tarayın.")
                        }
                    },
                    onRetry: { scanner.reset() }
                )
            case .failed(let message):
                messageScreen(icon: "exclamationmark.triangle", title: "Tarama başarısız",
                              body: message, button: "Tekrar dene") { scanner.reset() }
            case .unsupported:
                EmptyView()
            }
        }
    }

    // MARK: States

    private var unsupported: some View {
        messageScreen(icon: nil, title: "LiDAR gerekli",
                      body: "Oda tarama için LiDAR sensörlü bir cihaz gerekiyor (iPhone Pro / iPad Pro).",
                      button: "Geri") { router.pop() }
    }

    private func messageScreen(icon: String?, title: String, body: String,
                               button: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Brand.surface.ignoresSafeArea()
            VStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 38)).foregroundStyle(Brand.clay)
                } else {
                    MakettoLogo(size: 48)
                }
                Text(title).font(.display(30)).foregroundStyle(Brand.textPrimary)
                Text(body)
                    .font(.system(size: 15)).foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 50)
                Button(action: action) { Text(button) }
                    .buttonStyle(EvergreenButtonStyle()).padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var scanningView: some View {
        #if canImport(RoomPlan)
        ZStack(alignment: .top) {
            RoomCaptureViewRepresentable(scanner: scanner)
                .ignoresSafeArea()
                .onAppear { scanner.startScanning() }

            HStack {
                darkCircle("chevron.left") { router.pop() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            VStack {
                hintPill.padding(.top, 64)
                Spacer()
                scanControls.padding(.bottom, 48)
            }
        }
        #else
        ContentUnavailableView("RoomPlan yok", systemImage: "xmark.octagon")
        #endif
    }

    private var hintPill: some View {
        HStack(spacing: 9) {
            Circle().fill(Color(hex: 0xA7E8C6)).frame(width: 8, height: 8)
            Text("Odanın çevresinde yavaşça dönün")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color.black.opacity(0.5), in: Capsule())
    }

    @ViewBuilder
    private var scanControls: some View {
        if case .processing = scanner.state {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("İşleniyor…").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(Color.black.opacity(0.5), in: Capsule())
        } else {
            Button { scanner.finishScanning() } label: {
                Text("Bitti")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Brand.inkDeep)
                    .padding(.vertical, 16).padding(.horizontal, 56)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
        }
    }

    private func darkCircle(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.4), in: Circle())
        }
    }
}
