import SwiftUI

// MARK: - Logo

/// The Maketto mark: two nested arches + a brass dot. Drawn so we control color.
struct MakettoLogo: View {
    var size: CGFloat = 34
    var tint: Color = Brand.evergreen

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
}
