import SwiftUI
import UIKit

// MARK: - Color helpers

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Adaptive color that resolves differently in light vs dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Brand palette & type (ported from the Maketto / "Defne Residence" design system)

/// Warm natural-premium palette: evergreen, clay, brass, bone, ink.
/// "The maket is the hero; information lives on the model, not in tables."
enum Brand {
    // Core palette
    static let evergreen      = Color(hex: 0x2C4230)   // primary deep green
    static let evergreenSoft  = Color(hex: 0x5E7E61)
    static let evergreenDeep  = Color(hex: 0x18241A)
    static let clay           = Color(hex: 0xB5734E)   // warm accent
    static let clayLight      = Color(hex: 0xC68A67)
    static let clayDeep       = Color(hex: 0xA8623F)
    static let brass          = Color(hex: 0xB8954C)   // metallic line/detail
    static let gold           = Color(hex: 0xC8A862)
    static let bone           = Color(hex: 0xFCFAF6)   // warm surface
    static let bone100        = Color(hex: 0xF7F2EA)
    static let bone200        = Color(hex: 0xEFE8DB)
    static let ink            = Color(hex: 0x1E231D)
    static let inkDeep        = Color(hex: 0x14201A)
    static let borderLine     = Color(hex: 0xE2D9C8)
    static let muted          = Color(hex: 0x6E7367)
    static let mutedSoft      = Color(hex: 0x8C9083)

    // Semantic adaptive (light / dark)
    static let surface        = Color(light: bone,            dark: inkDeep)
    static let surfaceAlt      = Color(light: bone100,         dark: Color(hex: 0x101A14))
    static let card           = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1B2620))
    static let textPrimary    = Color(light: ink,             dark: Color(hex: 0xF7F2EA))
    static let textSecondary  = Color(light: muted,           dark: Color(hex: 0xAFC4A9))
    static let textFaint      = Color(light: mutedSoft,       dark: Color(hex: 0x7E907F))
    static let hairline       = Color(light: borderLine,      dark: Color(hex: 0x2A3A2E))
    static let accent         = clay

    /// Clay gradient used on the primary "scan / visualize" actions.
    static let clayGradient = LinearGradient(
        colors: [clayLight, clayDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Fonts

extension Font {
    /// Cormorant Garamond display serif (bundled variable font; falls back to
    /// the system serif if the custom font is unavailable).
    static func display(_ size: CGFloat) -> Font {
        .custom("Cormorant Garamond", size: size).weight(.medium)
    }

    static func displayItalic(_ size: CGFloat) -> Font {
        .custom("Cormorant Garamond", size: size).weight(.medium).italic()
    }

    /// Body / UI sans — system (SF), a clean stand-in for Mulish.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Uppercase label style (tracked) — pair with `.tracking()` + `.textCase(.uppercase)`.
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold)
    }
}
