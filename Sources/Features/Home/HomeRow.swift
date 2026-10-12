import SwiftUI

/// A home library card: hero map thumbnail on top; name, meta and an actions
/// menu below (rename/delete must be visible, not long-press-only).
struct HomeRow: View {
    let home: HomeSummary
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            thumbnail
                .frame(height: 164)
                .frame(maxWidth: .infinity)
                .clipped()

            footer
        }
        .background(Brand.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
        .shadow(color: Brand.ink.opacity(0.07), radius: 18, x: 0, y: 8)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            Brand.surface   // matches the map paper, so the plan floats seamlessly
            if home.rooms.isEmpty {
                Image(systemName: "house")
                    .font(.system(size: 26))
                    .foregroundStyle(Brand.textFaint)
            } else {
                WholeHomePlanView(rooms: home.rooms, interactive: false)
                    .padding(14)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(home.name)
                    .font(.display(23))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    metaItem("square.split.bottomrightquarter", "\(home.roomCount) oda")
                    if home.totalArea > 0 {
                        metaItem("ruler", MeasurementFormat.squareMeters(home.totalArea))
                    }
                    metaItem("calendar", MeasurementFormat.shortDate(home.createdAt))
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button { onRename() } label: {
                    Label("Yeniden Adlandır", systemImage: "pencil")
                }
                Button(role: .destructive) { onDelete() } label: {
                    Label("Evi Sil", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Brand.surfaceAlt, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Ev seçenekleri")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Brand.hairline.frame(height: 0.5) }
    }

    private func metaItem(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12.5, weight: .medium))
        }
        .foregroundStyle(Brand.textSecondary)
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
