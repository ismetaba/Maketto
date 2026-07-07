import SwiftUI
import UIKit

// MARK: - Logo

/// The Maketto mark: two nested arches + a brass dot. Drawn so we control color.
struct MakettoLogo: View {
    var size: CGFloat = 34
    var tint: Color = Brand.evergreenAdaptive

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 48
            let scale = CGAffineTransform(scaleX: s, y: s)

            var outer = Path()
            outer.move(to: CGPoint(x: 11, y: 41))
            outer.addLine(to: CGPoint(x: 11, y: 23.5))
            outer.addCurve(to: CGPoint(x: 23.5, y: 11),
                           control1: CGPoint(x: 11, y: 16.6), control2: CGPoint(x: 16.6, y: 11))
            outer.addCurve(to: CGPoint(x: 36, y: 23.5),
                           control1: CGPoint(x: 30.4, y: 11), control2: CGPoint(x: 36, y: 16.6))
            outer.addLine(to: CGPoint(x: 36, y: 41))

            var inner = Path()
            inner.move(to: CGPoint(x: 18, y: 41))
            inner.addLine(to: CGPoint(x: 18, y: 25.5))
            inner.addCurve(to: CGPoint(x: 23.5, y: 20),
                           control1: CGPoint(x: 18, y: 22.46), control2: CGPoint(x: 20.46, y: 20))
            inner.addCurve(to: CGPoint(x: 29, y: 25.5),
                           control1: CGPoint(x: 26.54, y: 20), control2: CGPoint(x: 29, y: 22.46))
            inner.addLine(to: CGPoint(x: 29, y: 41))

            let style = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round)
            ctx.stroke(outer.applying(scale), with: .color(tint), style: style)
            ctx.stroke(inner.applying(scale), with: .color(tint), style: style)
            let dot = CGRect(x: (23.5 - 2.1) * s, y: (13.2 - 2.1) * s, width: 4.2 * s, height: 4.2 * s)
            ctx.fill(Path(ellipseIn: dot), with: .color(Brand.brass))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Text bits

/// Tracked uppercase overline label (Mulish-style).
struct Overline: View {
    let text: String
    var color: Color = Brand.textSecondary
    var size: CGFloat = 11

    init(_ text: String, color: Color = Brand.textSecondary, size: CGFloat = 11) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold))
            .tracking(size * 0.16)
            .foregroundStyle(color)
    }
}

// MARK: - Button styles

/// Primary action — warm clay gradient pill (Taramayı Başlat, Tasarıma başla FAB).
struct ClayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .padding(.horizontal, 28)
            .background(Brand.clayGradient, in: Capsule())
            .shadow(color: Brand.clayDeep.opacity(0.5), radius: 16, x: 0, y: 12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary primary — deep evergreen pill.
struct EvergreenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Brand.bone100)
            .padding(.vertical, 15)
            .padding(.horizontal, 30)
            .background(Brand.evergreen, in: Capsule())
            .shadow(color: Brand.evergreen.opacity(0.45), radius: 14, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Frosted surface

extension View {
    /// Frosted glass chip/bar with a hairline border (used for chrome over the maket).
    func frostedChip(cornerRadius: CGFloat = 999) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Brand.hairline.opacity(0.7), lineWidth: 0.5)
            )
    }

    /// Floating glass sheet for bottom docks and room cards — frosted chip plus
    /// a soft lift shadow so panels read as chrome above the map.
    func glassPanel(cornerRadius: CGFloat = 26) -> some View {
        frostedChip(cornerRadius: cornerRadius)
            .shadow(color: Brand.ink.opacity(0.10), radius: 22, x: 0, y: 10)
    }
}

// MARK: - Circular chrome buttons

/// The visual for a floating circular icon button (glass over the map, or dark
/// over the camera). Usable directly as a `Menu` label.
struct CircleIcon: View {
    let systemName: String
    var size: CGFloat = 40
    var dark: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(dark ? Color.white : Brand.textPrimary)
            .frame(width: size, height: size)
            .background {
                if dark {
                    Circle().fill(Color.black.opacity(0.45))
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Circle().strokeBorder(
                    dark ? Color.white.opacity(0.14) : Brand.hairline.opacity(0.7),
                    lineWidth: 0.5
                )
            )
            .contentShape(Circle())
    }
}

/// Floating circular icon button used across all map chrome.
struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 40
    var dark: Bool = false
    var accessibilityLabel: String
    var action: () -> Void

    init(_ systemName: String, size: CGFloat = 40, dark: Bool = false,
         accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.size = size
        self.dark = dark
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            CircleIcon(systemName: systemName, size: size, dark: dark)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Map controls

/// Robot-vacuum-style floating map controls: zoom in, zoom out, re-fit.
/// Docked at the trailing edge of every plan screen.
struct MapControlStack: View {
    let camera: PlanCamera

    var body: some View {
        VStack(spacing: 0) {
            control("plus", enabled: camera.canZoomIn, label: "Yakınlaştır") {
                camera.zoomIn()
            }
            divider
            control("minus", enabled: camera.canZoomOut, label: "Uzaklaştır") {
                camera.zoomOut()
            }
            divider
            control("viewfinder", enabled: true, label: "Haritaya sığdır") {
                camera.reset()
            }
        }
        .frame(width: 44)
        .frostedChip(cornerRadius: 22)
        .shadow(color: Brand.ink.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    private var divider: some View {
        Rectangle().fill(Brand.hairline.opacity(0.8)).frame(width: 20, height: 0.5)
    }

    private func control(_ icon: String, enabled: Bool, label: String,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Brand.textPrimary : Brand.textFaint.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Room chip

/// One room in the horizontally scrolling room strip under the map: color dot,
/// name, and a compact selected state. Mirrors the room's map tint.
struct RoomChip: View {
    let name: String
    let tint: RoomTint
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint.accent)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background {
                // Material stays underneath the tint so the selected chip keeps
                // its frosted backing (dark-mode tints are translucent).
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    if selected {
                        Capsule().fill(tint.fill)
                    }
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    selected ? tint.accent.opacity(0.55) : Brand.hairline.opacity(0.7),
                    lineWidth: selected ? 1.5 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Room chips row

/// Horizontally scrolling strip of room chips under a map. Selection toggles:
/// tapping the selected room's chip deselects it. Shared by the home map and
/// the scan review so the strips can never drift apart.
struct RoomChipsRow: View {
    struct Entry: Identifiable {
        let id: UUID
        let name: String
        let tint: RoomTint
    }

    let entries: [Entry]
    let selectedID: UUID?
    let onToggle: (UUID?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        RoomChip(name: entry.name, tint: entry.tint,
                                 selected: entry.id == selectedID) {
                            onToggle(entry.id == selectedID ? nil : entry.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.maketto) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear {
                if let id = selectedID { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

// MARK: - Visualize FAB

/// The clay "Görselleştir" floating action button (AI render entry point),
/// identical on the home map and the room editor.
struct VisualizeFAB: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Brand.clayGradient, in: Circle())
                .shadow(color: Brand.clayDeep.opacity(0.6), radius: 16, x: 0, y: 10)
        }
        .accessibilityLabel("Görselleştir")
    }
}

// MARK: - Shared dialogs

extension View {
    /// Rename alert with a seeded text field + Kaydet/Vazgeç. Callers seed
    /// `text` before presenting; blank input is rejected by the store.
    func renameAlert(_ title: String, placeholder: String, isPresented: Binding<Bool>,
                     text: Binding<String>, onSave: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            TextField(placeholder, text: text)
            Button("Kaydet", action: onSave)
            Button("Vazgeç", role: .cancel) {}
        }
    }

    /// Destructive confirm for deleting a home — one copy of the data-loss
    /// warning, shared by the library and the home map.
    func deleteHomeDialog(_ title: String, isPresented: Binding<Bool>,
                          onDelete: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button("Evi Sil", role: .destructive, action: onDelete)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Tüm odaları ve versiyonlarıyla birlikte silinir. Bu işlem geri alınamaz.")
        }
    }
}

// MARK: - Motion

extension Animation {
    /// The app's signature selection/panel spring.
    static var maketto: Animation { .spring(response: 0.35, dampingFraction: 0.85) }
}

// MARK: - Secondary button

/// Quiet secondary pill on cards (rename, secondary actions) — solid card
/// surface with a hairline, sized to pair with the primary pills.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brand.textPrimary)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background(Brand.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.hairline, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Haptics

/// Tiny wrapper so interaction feedback stays consistent app-wide. Generators
/// are shared and long-lived so the Taptic Engine isn't re-allocated per tap.
@MainActor
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func selection() { selectionGenerator.selectionChanged() }
    static func light() { impactGenerator.impactOccurred() }
    static func success() { notificationGenerator.notificationOccurred(.success) }
}
