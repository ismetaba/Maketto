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
}
