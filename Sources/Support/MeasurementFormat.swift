import Foundation

/// Display-only formatting. Storage stays in meters everywhere; all
/// human-facing conversions live here, out of the domain model. The UI copy is
/// hardcoded Turkish, so numbers and dates format with the Turkish locale too
/// ("3,00 m", "7 Tem 2026") instead of mixing POSIX decimals into TR text.
enum MeasurementFormat {
    static let locale = Locale(identifier: "tr_TR")

    /// "3,00 m"
    static func meters(_ value: Double) -> String {
        String(format: "%.2f m", locale: locale, value)
    }

    /// "300 cm"
    static func centimeters(_ value: Double) -> String {
        String(format: "%.0f cm", locale: locale, value * 100)
    }

    /// "3,00 m · 300 cm"
    static func metersAndCentimeters(_ value: Double) -> String {
        "\(meters(value)) · \(centimeters(value))"
    }

    /// "12,4 m²"
    static func squareMeters(_ value: Double) -> String {
        String(format: "%.1f m²", locale: locale, value)
    }

    /// "7 Tem 2026"
    static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
    }

    /// "7 Tem 2026 14:05"
    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
    }

    /// Editable centimetre text for a length in meters: "345" or "345,5".
    static func centimeterInput(_ meters: Double) -> String {
        let cm = (meters * 1000).rounded() / 10
        if abs(cm - cm.rounded()) < 0.05 { return String(Int(cm.rounded())) }
        return String(format: "%.1f", locale: locale, cm)
    }

    /// Parse a user-typed centimetre value ("345", "345,5", "345.5 cm") into
    /// meters. Returns nil for anything that is not a positive number.
    static func parseCentimeters(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasSuffix("cm") { t = String(t.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        t = t.replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let value = Double(t), value.isFinite, value > 0 else { return nil }
        return value / 100
    }

    /// Integer degrees for a yaw in radians, in 0…359: "90".
    static func degreesInput(_ radians: Double) -> String {
        var d = Int((radians * 180 / .pi).rounded()) % 360
        if d < 0 { d += 360 }
        return String(d)
    }

    /// Parse typed degrees ("90", "-45", "22,5") into radians.
    static func parseDegrees(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let value = Double(t), value.isFinite else { return nil }
        return value * .pi / 180
    }

    /// Uppercase with Turkish casing rules ("Giriş" → "GİRİŞ", not "GIRIŞ").
    static func uppercased(_ text: String) -> String {
        text.uppercased(with: locale)
    }
}
