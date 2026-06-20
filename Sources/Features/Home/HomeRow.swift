import SwiftUI

/// A home library card: whole-home plan thumbnail + name + room/area meta.
struct HomeRow: View {
    let home: HomeSummary

    var body: some View {
        HStack(spacing: 0) {
            thumbnail
                .frame(width: 132)
                .frame(maxHeight: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(home.name)
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
        .frame(height: 116)
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
        .shadow(color: Brand.ink.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    private var meta: String {
        let rooms = "\(home.roomCount) oda"
        if home.totalArea > 0 {
            return "\(rooms) · \(MeasurementFormat.squareMeters(home.totalArea))"
        }
        return rooms
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Brand.surfaceAlt
            if home.rooms.isEmpty {
                Image(systemName: "house")
                    .font(.system(size: 22))
                    .foregroundStyle(Brand.textFaint)
            } else {
                WholeHomePlanView(rooms: home.rooms, interactive: false)
                    .padding(10)
            }
        }
    }
}

#Preview {
    HomeRow(home: HomeSummary(
        id: UUID(), name: "Defne · Daire 1", createdAt: .now,
        roomCount: 2, totalArea: 31, rooms: [.mockLShaped]
    ))
    .padding()
    .background(Brand.surfaceAlt)
}
