import SwiftUI

/// The full-screen editor: the maket fills the screen, chrome floats over it.
/// No measurement tables — tap a wall and its measure appears on the model.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    let roomID: UUID

    enum PlanMode: String, CaseIterable { case twoD = "2D", threeD = "3D" }
    @State private var planMode: PlanMode = .twoD
    @State private var showVisualizeSoon = false

    private var room: RoomModel? { store.roomModel(for: roomID) }

    var body: some View {
        let room = room
        let modelURL = store.modelURL(for: roomID)
        ZStack {
            Brand.surface.ignoresSafeArea()
            if let room {
                editor(room: room, modelURL: modelURL)
            } else {
                ContentUnavailableView("Oda bulunamadı", systemImage: "exclamationmark.triangle")
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
    private func editor(room: RoomModel, modelURL: URL?) -> some View {
        ZStack {
            canvas(room: room, modelURL: modelURL)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(room: room)
                Spacer()
                segment
                    .padding(.bottom, 36)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    fab.padding(.trailing, 18).padding(.bottom, 110)
                }
            }
        }
    }

    @ViewBuilder
    private func canvas(room: RoomModel, modelURL: URL?) -> some View {
        switch planMode {
        case .twoD:
            FloorPlanView(room: room)
        case .threeD:
            if let modelURL {
                USDZSceneView(url: modelURL)
            } else {
                ZStack {
                    Brand.surface
                    ContentUnavailableView("3B model yok", systemImage: "cube")
                }
            }
        }
    }

    private func topBar(room: RoomModel) -> some View {
        HStack {
            circleButton("chevron.left") { router.pop() }
            Spacer()
            VStack(spacing: 1) {
                Overline("Maketto", color: Brand.textSecondary, size: 9)
                HStack(spacing: 7) {
                    Text(room.name)
                        .font(.display(19))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    Text("v1")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Brand.gold, in: Capsule())
                }
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

    private var segment: some View {
        HStack(spacing: 4) {
            ForEach(PlanMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { planMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(planMode == mode ? .white : Brand.textSecondary)
                        .padding(.vertical, 8).padding(.horizontal, 18)
                        .background {
                            if planMode == mode { Capsule().fill(Brand.clay) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frostedChip(cornerRadius: 14)
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
