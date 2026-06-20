import SwiftUI

/// Whole-home scan: walk room to room, "Sonraki Oda" between, "Bitir" to merge.
struct HomeScanScreen: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    @State private var scanner = HomeScanner()

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
                darkCircle("chevron.left") { router.pop() }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            VStack {
                hintPill.padding(.top, 64)
                Spacer()
                Button { scanner.finish() } label: { Text("Bitir") }
                    .buttonStyle(ClayButtonStyle())
                    .padding(.bottom, 44)
            }
        }
        #else
        ContentUnavailableView("RoomPlan yok", systemImage: "xmark.octagon")
        #endif
    }

    private var hintPill: some View {
        HStack(spacing: 9) {
            Circle().fill(Color(hex: 0xA7E8C6)).frame(width: 8, height: 8)
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
