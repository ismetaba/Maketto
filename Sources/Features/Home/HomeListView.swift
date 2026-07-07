import SwiftUI

/// Home library — "Evlerim": every home you've scanned, with a hero map
/// thumbnail per card. Long-press a card to rename or delete; the scan CTA is
/// pinned at the bottom, thumb-reach first.
struct HomeListView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router

    @State private var renameTarget: HomeSummary?
    @State private var renameText = ""
    @State private var deleteTarget: HomeSummary?

    var body: some View {
        ZStack(alignment: .bottom) {
            Brand.surfaceAlt.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if store.homes.isEmpty {
                    emptyState
                } else {
                    homeList
                }
            }

            if !store.homes.isEmpty {
                scanBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Evi Yeniden Adlandır", isPresented: renamePresented) {
            TextField("Ev adı", text: $renameText)
            Button("Kaydet") {
                if let target = renameTarget { store.renameHome(id: target.id, to: renameText) }
                renameTarget = nil
            }
            Button("Vazgeç", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "\u{201C}\(deleteTarget?.name ?? "")\u{201D} silinsin mi?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Evi Sil", role: .destructive) {
                if let target = deleteTarget { store.deleteHome(id: target.id) }
                deleteTarget = nil
            }
            Button("Vazgeç", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Tüm odaları ve versiyonlarıyla birlikte silinir. Bu işlem geri alınamaz.")
        }
    }

    // MARK: - Alert plumbing

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private func beginRename(_ home: HomeSummary) {
        renameText = home.name
        renameTarget = home
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Overline("Maketto", color: Brand.clay)
                Text("Evlerim").font(.display(34)).foregroundStyle(Brand.textPrimary)
            }
            Spacer()
            MakettoLogo(size: 40)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var homeList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(store.homes) { home in
                    Button { router.push(.homeDetail(home.id)) } label: {
                        HomeRow(home: home)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { beginRename(home) } label: {
                            Label("Yeniden Adlandır", systemImage: "pencil")
                        }
                        Button(role: .destructive) { deleteTarget = home } label: {
                            Label("Evi Sil", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 128)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                MakettoLogo(size: 56)
                    .padding(.top, 48)
                Text("Henüz ev yok")
                    .font(.display(33)).foregroundStyle(Brand.textPrimary).padding(.top, 20)
                Text("Evinizi birkaç dakikada tarayın; Maketto haritasını çıkarıp odalara bölsün.")
                    .font(.system(size: 15.5)).foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 44).padding(.top, 10)

                VStack(alignment: .leading, spacing: 14) {
                    step("figure.walk", "Telefonla evi oda oda dolaşın")
                    step("square.split.bottomrightquarter", "Maketto planı odalara ayırır")
                    step("pencil.and.ruler", "Haritayı düzenleyin, tasarlayın")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Brand.hairline, lineWidth: 1)
                )
                .padding(.horizontal, 34)
                .padding(.top, 28)

                Button { router.push(.scanHome) } label: {
                    Label("Evi Tara", systemImage: "viewfinder")
                }
                .buttonStyle(ClayButtonStyle()).padding(.top, 28)
                Overline("LiDAR · iPhone Pro", color: Brand.textFaint).padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func step(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.evergreen)
                .frame(width: 34, height: 34)
                .background(Brand.evergreenSoft.opacity(0.15), in: Circle())
            Text(text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Brand.textPrimary)
        }
    }

    private var scanBar: some View {
        Button { router.push(.scanHome) } label: {
            Label("Evi Tara", systemImage: "viewfinder")
        }
        .buttonStyle(ClayButtonStyle())
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [Brand.surfaceAlt.opacity(0), Brand.surfaceAlt],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 130)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    NavigationStack { HomeListView() }
        .environment(RoomStore.preview)
        .environment(Router())
}
