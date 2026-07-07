import SwiftUI

/// The home map, managed like a robot-vacuum app: the whole-home plan fills the
/// screen; tap a room (or its chip) to select it, and a floating card offers
/// the room's stats and actions. Zoom/fit controls dock at the trailing edge.
struct HomeDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    let homeID: UUID

    @State private var camera = PlanCamera()
    @State private var selectedRoomID: UUID?
    @State private var showVisualizeSoon = false

    @State private var renamingRoom: PlacedRoom?
    @State private var renamingHome = false
    @State private var renameText = ""
    @State private var showDeleteHome = false

    private var home: HomeModel? { store.homeModel(for: homeID) }

    var body: some View {
        let home = home
        ZStack {
            Brand.surface.ignoresSafeArea()
            if let home {
                content(home)
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
        .renameAlert("Odayı Yeniden Adlandır", placeholder: "Oda adı",
                     isPresented: roomRenamePresented, text: $renameText) {
            if let target = renamingRoom { store.renameRoom(id: target.id, to: renameText) }
            renamingRoom = nil
        }
        .renameAlert("Evi Yeniden Adlandır", placeholder: "Ev adı",
                     isPresented: $renamingHome, text: $renameText) {
            store.renameHome(id: homeID, to: renameText)
        }
        .deleteHomeDialog("Bu ev silinsin mi?", isPresented: $showDeleteHome) {
            store.deleteHome(id: homeID)
            router.pop()
        }
    }

    private var roomRenamePresented: Binding<Bool> {
        Binding(get: { renamingRoom != nil }, set: { if !$0 { renamingRoom = nil } })
    }

    // MARK: - Layout

    private func content(_ home: HomeModel) -> some View {
        ZStack {
            WholeHomePlanView(
                rooms: home.roomsInHomeFrame,
                selectedRoomID: selectedRoomID,
                camera: camera
            ) { id in
                withAnimation(.maketto) { selectedRoomID = id }
                if id != nil { Haptics.selection() }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(home)
                Spacer()
                bottomStack(home)
            }
        }
        .overlay(alignment: .trailing) {
            MapControlStack(camera: camera)
                .padding(.trailing, 12)
        }
    }

    private func topBar(_ home: HomeModel) -> some View {
        HStack(spacing: 8) {
            CircleIconButton("chevron.left", accessibilityLabel: "Geri") { router.pop() }
            Spacer()
            VStack(spacing: 1) {
                Text(home.name)
                    .font(.display(19)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Text(subtitle(home))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            Menu {
                Button {
                    renameText = home.name
                    renamingHome = true
                } label: {
                    Label("Evi Yeniden Adlandır", systemImage: "pencil")
                }
                Button { camera.reset() } label: {
                    Label("Haritaya Sığdır", systemImage: "viewfinder")
                }
                Divider()
                Button(role: .destructive) { showDeleteHome = true } label: {
                    Label("Evi Sil", systemImage: "trash")
                }
            } label: {
                CircleIcon(systemName: "ellipsis")
            }
            .accessibilityLabel("Ev seçenekleri")
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frostedChip(cornerRadius: 20)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func subtitle(_ home: HomeModel) -> String {
        let area = home.rooms.reduce(0.0) { $0 + PlanGeometry.area(of: $1.room) }
        return "\(home.rooms.count) oda · \(MeasurementFormat.squareMeters(area))"
    }

    @ViewBuilder
    private func bottomStack(_ home: HomeModel) -> some View {
        let ordered = home.orderedRooms
        VStack(spacing: 12) {
            HStack {
                Spacer()
                VisualizeFAB { showVisualizeSoon = true }
            }
            .padding(.horizontal, 18)

            if let sel = selectedRoomID,
               let idx = ordered.firstIndex(where: { $0.id == sel }) {
                roomCard(ordered[idx], index: idx)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(sel)
            }

            RoomChipsRow(
                entries: ordered.enumerated().map { i, placed in
                    RoomChipsRow.Entry(id: placed.id, name: placed.name,
                                       tint: RoomPalette.tint(i))
                },
                selectedID: selectedRoomID
            ) { id in
                withAnimation(.maketto) { selectedRoomID = id }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Room card (selection details + actions)

    private func roomCard(_ placed: PlacedRoom, index: Int) -> some View {
        let tint = RoomPalette.tint(index)
        let kind = placed.kind ?? .unidentified
        return VStack(spacing: 14) {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(tint.fill).frame(width: 42, height: 42)
                    Image(systemName: kind.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Overline(kind.displayName, color: Brand.textFaint, size: 10)
                    Text(placed.name)
                        .font(.display(22)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                }
                Spacer()
                CircleIconButton("xmark", size: 30, accessibilityLabel: "Seçimi kapat") {
                    withAnimation(.maketto) { selectedRoomID = nil }
                }
            }

            HStack(spacing: 14) {
                stat("ruler", MeasurementFormat.squareMeters(PlanGeometry.area(of: placed.room)))
                stat("lines.measurement.horizontal", "\(placed.room.walls.count) duvar")
                if !placed.room.openings.isEmpty {
                    stat("door.left.hand.open", "\(placed.room.openings.count) açıklık")
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    renameText = placed.name
                    renamingRoom = placed
                } label: {
                    Label("Ad Değiştir", systemImage: "pencil")
                }
                .buttonStyle(SoftButtonStyle())

                Button { router.push(.roomDetail(placed.id)) } label: {
                    HStack(spacing: 8) {
                        Text("Planı Aç")
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(EvergreenButtonStyle())
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: 26)
        .padding(.horizontal, 14)
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Brand.textSecondary)
    }

}
