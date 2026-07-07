import SwiftUI

/// Whole-home scan: walk room to room in ONE capture, then "Taramayı Bitir".
struct HomeScanScreen: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    @State private var scanner = HomeScanner()
    @State private var pulse = false

    var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if !scanner.isSupported {
            messageScreen(icon: nil, title: "LiDAR gerekli",
                          body: "Ev taraması için LiDAR sensörlü bir cihaz gerekiyor (iPhone Pro / iPad Pro).",
                          button: "Geri") { router.pop() }
        } else {
            switch scanner.state {
            case .idle, .scanning:
                scanningView
            case .processing:
                processingView
            case .review(let rooms):
                ScanReviewView(
                    rooms: rooms,
                    modelURLs: scanner.modelURLs,
                    onSave: { edited, homeName in
                        guard let id = store.saveScannedHome(edited, homeName: homeName,
                                                             modelURLs: scanner.modelURLs) else {
                            return false
                        }
                        router.popToRoot()
                        router.push(.homeDetail(id))
                        return true
                    },
                    onRescan: { scanner.reset() }
                )
            case .failed(let message):
                messageScreen(icon: "exclamationmark.triangle", title: "Tarama başarısız",
                              body: message, button: "Tekrar dene") { scanner.reset() }
            case .unsupported:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var scanningView: some View {
        #if canImport(RoomPlan)
        ZStack(alignment: .top) {
            HomeCaptureViewRepresentable(scanner: scanner).ignoresSafeArea()

            HStack {
                CircleIconButton("chevron.left", dark: true, accessibilityLabel: "Geri") {
                    router.pop()
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            VStack {
                hintPill.padding(.top, 64)
                Spacer()
                Button { scanner.finish() } label: {
                    Label("Taramayı Bitir", systemImage: "checkmark")
                }
                .buttonStyle(ClayButtonStyle())
                .padding(.bottom, 44)
            }
        }
        .onAppear { pulse = true }
        #else
        ContentUnavailableView("RoomPlan yok", systemImage: "xmark.octagon")
        #endif
    }

    private var hintPill: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color(hex: 0xA7E8C6))
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.35 : 1)
                .scaleEffect(pulse ? 0.75 : 1.1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text("Tüm evi dolaşın — Maketto odalara böler")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color.black.opacity(0.5), in: Capsule())
    }

    private var processingView: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()
            VStack(spacing: 18) {
                MakettoLogo(size: 46)
                ProgressView().controlSize(.large).tint(Brand.clay)
                Text("Eviniz birleştiriliyor…")
                    .font(.display(26)).foregroundStyle(Brand.textPrimary)
                Text("Odalar tek bir haritada hizalanıyor.")
                    .font(.system(size: 15)).foregroundStyle(Brand.textSecondary)
            }
        }
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
}
