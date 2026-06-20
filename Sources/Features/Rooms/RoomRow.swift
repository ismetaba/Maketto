import SwiftUI

/// A room library card: plan thumbnail + name + meta.
struct RoomRow: View {
    let summary: RoomSummary

    var body: some View {
        HStack(spacing: 0) {
            thumbnail
                .frame(width: 120)
                .frame(maxHeight: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.name)
                    .font(.display(23))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(height: 104)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
        .shadow(color: Brand.ink.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    private var meta: String {
        "\(summary.wallCount) duvar · \(summary.createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Brand.surfaceAlt
            if let plan = summary.plan {
                FloorPlanView(room: plan, interactive: false)
                    .padding(10)
            } else {
                Image(systemName: "square.split.bottomrightquarter")
                    .font(.system(size: 22))
                    .foregroundStyle(Brand.textFaint)
            }
        }
    }
}

#Preview {
    RoomRow(summary: RoomSummary(
        id: UUID(), name: "Defne · Daire 1", createdAt: .now,
        wallCount: 4, thumbnail: nil, plan: .mockLShaped
    ))
    .padding()
    .background(Brand.surfaceAlt)
}
