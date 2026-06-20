import Foundation

/// Display-only formatting. Storage stays in meters everywhere; all
/// human-facing conversions live here, out of the domain model.
enum MeasurementFormat {
    /// "3.00 m"
    static func meters(_ value: Double) -> String {
        String(format: "%.2f m", value)
    }

    /// "300 cm"
    static func centimeters(_ value: Double) -> String {
        String(format: "%.0f cm", value * 100)
    }

    /// "3.00 m · 300 cm"
    static func metersAndCentimeters(_ value: Double) -> String {
        "\(meters(value)) · \(centimeters(value))"
    }

    /// "12.4 m²"
    static func squareMeters(_ value: Double) -> String {
        String(format: "%.1f m²", value)
    }
}
