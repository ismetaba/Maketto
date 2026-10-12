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
    @State private var show3D = false
    @State private var sceneResetToken = 0
    @State private var share: ShareItem?
    @State private var exportFailed = false

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
                VStack(spacing: 18) {
                    ContentUnavailableView("Ev bulunamadı", systemImage: "exclamationmark.triangle",
                                           description: Text("Bu ev silinmiş olabilir."))
                    Button("Geri Dön") { router.pop() }
                        .buttonStyle(EvergreenButtonStyle())
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $share) { item in
            ShareSheet(item: item).ignoresSafeArea()
        }
        .alert("Dışa aktarılamadı", isPresented: $exportFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Plan görseli oluşturulamadı. Lütfen tekrar deneyin.")
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
            if show3D {
                RoomSceneView(rooms: home.roomsInHomeFrame, furniture: home.furnitureInHomeFrame,
                              floorTints: home.orderedRooms.indices.map { RoomPalette.tint($0).fill },
                              resetToken: sceneResetToken)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                WholeHomePlanView(
                    rooms: home.roomsInHomeFrame,
                    furniture: home.furnitureInHomeFrame,
                    selectedRoomID: selectedRoomID,
                    camera: camera
                ) { id in
                    withAnimation(.maketto) { selectedRoomID = id }
                    if id != nil { Haptics.selection() }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar(home)
                // The controls live in the free region BETWEEN the bars, so
                // they can never collide with the card/chips on short screens.
                Spacer()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        Group {
                            if show3D {
                                CircleIconButton("viewfinder", accessibilityLabel: "Görünümü sıfırla") {
                                    sceneResetToken += 1
                                    Haptics.light()
                                }
                            } else {
                                MapControlStack(camera: camera)
                            }
                        }
                        .padding(.trailing, 12)
                    }
                bottomStack(home)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: show3D)
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
                Button { sharePlan(home) } label: {
                    Label("Planı Paylaş", systemImage: "square.and.arrow.up")
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
        "\(home.rooms.count) oda · \(MeasurementFormat.squareMeters(home.totalArea))"
    }

    private func sharePlan(_ home: HomeModel) {
        guard let url = PlanExporter.planImage(rooms: home.roomsInHomeFrame,
                                               furniture: home.furnitureInHomeFrame,
                                               title: home.name, subtitle: subtitle(home)) else {
            exportFailed = true
            return
        }
        share = ShareItem(urls: [url])
    }

    @ViewBuilder
    private func bottomStack(_ home: HomeModel) -> some View {
        let ordered = home.orderedRooms
        VStack(spacing: 12) {
            HStack {
                Spacer()
                viewToggle
            }
            .padding(.horizontal, 18)

            if !show3D, let sel = selectedRoomID,
               let idx = ordered.firstIndex(where: { $0.id == sel }) {
                roomCard(ordered[idx], index: idx)
                    .frame(maxWidth: 468)   // don't stretch edge-to-edge on iPad
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !show3D {
                chips(ordered)
            }
        }
        .padding(.bottom, 12)
    }

    /// 2D map ⇄ 3D dollhouse of the whole home.
    private var viewToggle: some View {
        Button {
            withAnimation(.maketto) {
                show3D.toggle()
                if show3D { selectedRoomID = nil }
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: show3D ? "map" : "cube")
                    .font(.system(size: 15, weight: .bold))
                Text(show3D ? "2D Plan" : "3D Görünüm")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Brand.clayGradient, in: Capsule())
            .shadow(color: Brand.clayDeep.opacity(0.45), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private func chips(_ ordered: [PlacedRoom]) -> some View {
        RoomChipsRow(
            entries: ordered.enumerated().map { i, placed in
                RoomChipsRow.Entry(id: placed.id, name: placed.name, tint: RoomPalette.tint(i))
            },
            selectedID: selectedRoomID
        ) { id in
            withAnimation(.maketto) { selectedRoomID = id }
        }
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
                if !placed.furniture.isEmpty {
                    stat("sofa", "\(placed.furniture.count) eşya")
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    renameText = placed.name
                    renamingRoom = placed
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                        .frame(width: 50, height: 50)
                        .background(Brand.card, in: Circle())
                        .overlay(Circle().strokeBorder(Brand.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yeniden Adlandır")

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

#Preview {
    let store = RoomStore.preview
    return NavigationStack { HomeDetailView(homeID: store.homes.first?.id ?? UUID()) }
        .environment(store)
        .environment(Router())
        .environment(FurnitureLibrary(fileURL: nil))
}
