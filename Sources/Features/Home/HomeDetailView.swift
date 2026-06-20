import SwiftUI

/// The home map: the whole-home plan fills the screen; tap a room to open it.
struct HomeDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    let homeID: UUID
    @State private var showVisualizeSoon = false

    private var home: HomeModel? { store.homeModel(for: homeID) }

    var body: some View {
        let home = home
        ZStack {
            Brand.surface.ignoresSafeArea()
            if let home {
                editor(home)
            } else {
                ContentUnavailableView("Ev bulunamadı", systemImage: "exclamationmark.triangle")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Görselleştirme yakında", isPresented: $showVisualizeSoon) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Yapay zekâ ile fotogerçekçi oda görselleri bir sonraki sürümde gelecek.")
        }
    }

    @ViewBuilder
    private func editor(_ home: HomeModel) -> some View {
        ZStack {
            WholeHomePlanView(rooms: home.roomsInHomeFrame) { roomID in
                router.push(.roomDetail(roomID))
            }
            .ignoresSafeArea()

            VStack {
                topBar(home)
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    fab.padding(.trailing, 18).padding(.bottom, 30)
                }
            }
        }
    }

    private func topBar(_ home: HomeModel) -> some View {
        HStack {
            circleButton("chevron.left") { router.pop() }
            Spacer()
            VStack(spacing: 1) {
                Overline("Maketto", color: Brand.textSecondary, size: 9)
                Text(home.name)
                    .font(.display(19)).foregroundStyle(Brand.textPrimary).lineLimit(1)
            }
            Spacer()
            circleButton("slider.horizontal.3") {}
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frostedChip(cornerRadius: 20)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var fab: some View {
        Button { showVisualizeSoon = true } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Brand.clayGradient, in: Circle())
                .shadow(color: Brand.clayDeep.opacity(0.6), radius: 16, x: 0, y: 10)
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
