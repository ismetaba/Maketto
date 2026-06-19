import SwiftUI
import UIKit

/// A single room cell. Pure receiver of a value summary — no state.
struct RoomRow: View {
    let summary: RoomSummary

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name)
                    .font(.headline)
                Text("\(summary.wallCount) walls · \(summary.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = summary.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "square.split.bottomrightquarter")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    List {
        RoomRow(summary: RoomSummary(
            id: UUID(), name: "Living Room", createdAt: .now, wallCount: 4, thumbnail: nil
        ))
    }
}
