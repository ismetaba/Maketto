import SwiftUI
import UIKit

/// Files handed to the system share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// UIActivityViewController for sharing exported files.
struct ShareSheet: UIViewControllerRepresentable {
    let item: ShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: item.urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Renders plans to shareable files: a print-quality PNG card and a JSON
/// export of the exact measurements (meters, the app's portable model).
@MainActor
enum PlanExporter {
    /// A titled, light-mode plan card as PNG. Returns nil if rendering failed.
    static func planImage(rooms: [RoomModel], furniture: [PlacedFurniture],
                          title: String, subtitle: String) -> URL? {
        let card = PlanShareCard(rooms: rooms, furniture: furniture, title: title, subtitle: subtitle)
            .frame(width: 1080, height: 1350)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        return write(data, name: "\(fileSafe(title)) Plan.png")
    }

    /// Machine-readable export of one room (+ its furniture).
    static func roomJSON(_ room: RoomModel, furniture: [PlacedFurniture]) -> URL? {
        struct Export: Encodable {
            let format = "maketto.room"
            let version = 1
            let exportedAt: Date
            let unit = "meters"
            let room: RoomModel
            let furniture: [PlacedFurniture]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Export(exportedAt: .now, room: room, furniture: furniture))
        else { return nil }
        return write(data, name: "\(fileSafe(room.name)).json")
    }

    private static func write(_ data: Data, name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func fileSafe(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Maketto" : String(cleaned.prefix(60))
    }
}

/// The exported plan card: brand header, the plan, and a scale note.
private struct PlanShareCard: View {
    let rooms: [RoomModel]
    let furniture: [PlacedFurniture]
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                MakettoLogo(size: 64, tint: Brand.evergreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.display(54)).foregroundStyle(Brand.ink).lineLimit(1)
                    Text(subtitle).font(.system(size: 24, weight: .semibold)).foregroundStyle(Brand.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 56)
            .padding(.top, 52)
            .padding(.bottom, 24)

            Group {
                if rooms.count == 1, let room = rooms.first {
                    FloorPlanView(room: room, furniture: furniture, interactive: false)
                } else {
                    WholeHomePlanView(rooms: rooms, furniture: furniture, interactive: false, showLabels: true)
                }
            }
            .padding(.horizontal, 32)

            HStack {
                Text("Ölçüler metre cinsindendir · Maketto ile çıkarıldı")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(Brand.muted)
                Spacer()
                Text(MeasurementFormat.shortDate(.now))
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(Brand.muted)
            }
            .padding(.horizontal, 56)
            .padding(.bottom, 40)
            .padding(.top, 16)
        }
        .background(Brand.bone)
    }
}
