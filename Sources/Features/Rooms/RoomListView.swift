import SwiftUI

/// F0 home — the room library. "Odalarım" with warm cards and a bottom bar.
struct RoomListView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ZStack(alignment: .bottom) {
            Brand.surfaceAlt.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if store.rooms.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.rooms) { summary in
                                Button {
                                    router.push(.roomDetail(summary.id))
                                } label: {
                                    RoomRow(summary: summary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 116)
                    }
                }
            }

            bottomBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Overline("Maketto", color: Brand.clay)
                Text("Odalarım")
                    .font(.display(34))
                    .foregroundStyle(Brand.textPrimary)
            }
            Spacer()
            Button { router.push(.scan) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.bone100)
                    .frame(width: 44, height: 44)
                    .background(Brand.evergreen, in: Circle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            MakettoLogo(size: 52)
            Text("Henüz maket yok")
                .font(.display(33))
                .foregroundStyle(Brand.textPrimary)
                .padding(.top, 22)
            Text("Odanızı yaklaşık 30 saniyede tarayın. Gerisini Maketto halleder.")
                .font(.system(size: 16))
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .padding(.top, 10)
            Button { router.push(.scan) } label: {
                Label("Taramayı Başlat", systemImage: "viewfinder")
            }
            .buttonStyle(ClayButtonStyle())
            .padding(.top, 28)
            Overline("LiDAR · iPhone Pro", color: Brand.textFaint)
                .padding(.top, 18)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tab("Odalar", "house.fill", active: true) {}
            tab("Tara", "viewfinder", active: false) { router.push(.scan) }
            tab("Profil", "person", active: false) {}
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(Brand.hairline.frame(height: 0.5), alignment: .top)
    }

    private func tab(_ title: String, _ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: active ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10, weight: active ? .bold : .medium))
            }
            .foregroundStyle(active ? Brand.evergreen : Brand.textFaint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { RoomListView() }
        .environment(RoomStore.preview)
        .environment(Router())
}
