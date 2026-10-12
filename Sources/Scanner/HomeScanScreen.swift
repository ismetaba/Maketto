import SwiftUI
import UIKit

/// Whole-home scan: walk room to room in ONE capture, then "Taramayı Bitir".
struct HomeScanScreen: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var scanner = HomeScanner()
    @State private var pulse = false
    @State private var showExitConfirm = false

    var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .task { await scanner.prepare() }
            // Leaving the screen (back, or after saving) always stops the camera.
            .onDisappear { scanner.cancel() }
            .persistentSystemOverlays(isCapturing ? .hidden : .automatic)
    }

    private var isCapturing: Bool {
        switch scanner.state {
        case .idle, .scanning, .processing: return true
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scanner.state {
        case .unsupported:
            messageScreen(icon: nil, title: "LiDAR gerekli",
                          body: "Ev taraması için LiDAR sensörlü bir cihaz gerekiyor (iPhone Pro / iPad Pro).",
                          button: "Geri") { router.pop() }
        case .preparing:
            Color.black.ignoresSafeArea()
        case .permissionDenied:
            messageScreen(icon: "camera.fill", title: "Kamera izni gerekli",
                          body: "Evinizi taramak için Maketto'nun kameraya erişmesi gerekiyor. Ayarlar'dan izin verebilirsiniz.",
                          button: "Ayarları Aç", secondary: "Geri", secondaryAction: { router.pop() }) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .idle, .scanning, .processing:
            captureView
        case .review(let rooms):
            ScanReviewView(
                rooms: rooms,
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
                          body: message, button: "Tekrar dene",
                          secondary: "Vazgeç", secondaryAction: { router.pop() }) {
                scanner.reset()
            }
        }
    }

    /// The live capture stays mounted through processing: tearing the view
    /// down would release the session before it delivers the scan.
    @ViewBuilder
    private var captureView: some View {
        #if canImport(RoomPlan)
        ZStack(alignment: .top) {
            HomeCaptureViewRepresentable(scanner: scanner).ignoresSafeArea()

            if scanner.state == .processing {
                processingView.transition(.opacity)
            } else {
                scanChrome
            }
        }
        .animation(.easeInOut(duration: 0.25), value: scanner.state == .processing)
        .confirmationDialog("Taramadan çıkılsın mı?", isPresented: $showExitConfirm,
                            titleVisibility: .visible) {
            Button("Çık", role: .destructive) { router.pop() }
            Button("Taramaya Devam", role: .cancel) {}
        } message: {
            Text("Bu tarama kaydedilmeden silinir.")
        }
        #else
        messageScreen(icon: "xmark.octagon", title: "RoomPlan yok",
                      body: "Bu cihazda ev taraması kullanılamıyor.", button: "Geri") { router.pop() }
        #endif
    }

    private var scanChrome: some View {
        ZStack(alignment: .top) {
            HStack {
                CircleIconButton("chevron.left", dark: true, accessibilityLabel: "Taramadan çık") {
                    if scanner.state == .scanning { showExitConfirm = true } else { router.pop() }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // The hint lives at the BOTTOM: RoomPlan draws its own coaching
            // text top-centre, and the two must never fight for the same spot.
            VStack {
                Spacer()
                hintPill.padding(.bottom, 14)
                Button { scanner.finish() } label: {
                    Label("Taramayı Bitir", systemImage: "checkmark")
                }
                .buttonStyle(ClayButtonStyle())
                .disabled(scanner.state != .scanning)
                .opacity(scanner.state == .scanning ? 1 : 0.5)
                .padding(.bottom, 30)
            }
        }
        .onAppear { pulse = true }
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
        .accessibilityElement(children: .combine)
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
            .accessibilityElement(children: .combine)
        }
    }

    private func messageScreen(icon: String?, title: String, body: String,
                               button: String, secondary: String? = nil,
                               secondaryAction: (() -> Void)? = nil,
                               action: @escaping () -> Void) -> some View {
        ZStack {
            Brand.surface.ignoresSafeArea()
            VStack(spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 38)).foregroundStyle(Brand.clay)
                } else {
                    MakettoLogo(size: 48)
                }
                Text(title).font(.display(30)).foregroundStyle(Brand.textPrimary)
                    .multilineTextAlignment(.center)
                Text(body)
                    .font(.system(size: 15)).foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 44)
                Button(action: action) { Text(button) }
                    .buttonStyle(EvergreenButtonStyle()).padding(.top, 8)
                if let secondary, let secondaryAction {
                    Button(secondary, action: secondaryAction)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.textSecondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: 520)
        }
    }
}
