import SwiftUI

/// After a whole-home scan: the auto-split rooms on the tinted map, with
/// default names. Select a room (on the map or via its chip) to rename it and
/// fix its type; name the home; save.
struct ScanReviewView: View {
    let modelURLs: [UUID: URL]
    let onSave: ([RoomModel], String) -> Bool
    let onRescan: () -> Void

    @State private var rooms: [RoomModel]
    @State private var homeName = "Evim"
    @State private var selectedRoomID: UUID?
    @State private var saveFailed = false
    @State private var camera = PlanCamera()

    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.85)

    init(rooms: [RoomModel], modelURLs: [UUID: URL],
         onSave: @escaping ([RoomModel], String) -> Bool, onRescan: @escaping () -> Void) {
        _rooms = State(initialValue: rooms)
        self.modelURLs = modelURLs
        self.onSave = onSave
        self.onRescan = onRescan
    }

    private var totalArea: Double { rooms.reduce(0) { $0 + PlanGeometry.area(of: $1) } }
    private var selectedIndex: Int? {
        selectedRoomID.flatMap { id in rooms.firstIndex { $0.id == id } }
    }

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            WholeHomePlanView(rooms: rooms, selectedRoomID: selectedRoomID, camera: camera) { id in
                withAnimation(spring) { selectedRoomID = id }
                if id != nil { Haptics.selection() }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                summaryPill.padding(.top, 10)
                Spacer()
                VStack(spacing: 12) {
                    chipsRow
                    bottomCard
                }
                .padding(.bottom, 6)
            }
        }
        .overlay(alignment: .trailing) {
            MapControlStack(camera: camera).padding(.trailing, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Kaydedilemedi", isPresented: $saveFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Bir sorun oluştu. Lütfen tekrar deneyin.")
        }
    }

    // MARK: - Pieces

    private var summaryPill: some View {
        VStack(spacing: 2) {
            Overline("Tarama Sonucu", color: Brand.clay, size: 9)
            Text("\(rooms.count) oda · \(MeasurementFormat.squareMeters(totalArea))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.textPrimary)
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .frostedChip(cornerRadius: 18)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { i, room in
                    RoomChip(
                        name: room.name,
                        tint: RoomPalette.tint(i),
                        selected: room.id == selectedRoomID
                    ) {
                        withAnimation(spring) {
                            selectedRoomID = (room.id == selectedRoomID) ? nil : room.id
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var bottomCard: some View {
        VStack(spacing: 12) {
            if let idx = selectedIndex {
                HStack(spacing: 10) {
                    field(icon: "pencil", placeholder: "Oda adı", text: roomName(idx))
                    kindMenu(idx)
                }
            } else {
                Text("Bir odaya dokunup adını ve türünü düzenleyin")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            field(icon: "house", placeholder: "Ev adı", text: $homeName)

            Button {
                if onSave(rooms, homeName) {
                    Haptics.success()
                } else {
                    saveFailed = true
                }
            } label: {
                HStack(spacing: 9) {
                    Text("Evi Kaydet")
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EvergreenButtonStyle())

            Button { onRescan() } label: {
                Text("Yeniden Tara")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(18)
        .padding(.bottom, 10)
        .glassPanel(cornerRadius: 26)
        .padding(.horizontal, 14)
    }

    private func roomName(_ idx: Int) -> Binding<String> {
        Binding(get: { rooms[idx].name }, set: { rooms[idx].name = $0 })
    }

    /// Room-type picker. Fixing the type also refreshes the auto default name —
    /// but never a name the user already customised.
    private func kindMenu(_ idx: Int) -> some View {
        let kind = rooms[idx].kind ?? .unidentified
        return Menu {
            ForEach(RoomKind.allCases, id: \.self) { k in
                Button { setKind(k, at: idx) } label: {
                    Label(k.displayName, systemImage: k.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.icon).font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, 13)
            .frame(height: 50)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            )
        }
        .accessibilityLabel("Oda türü")
    }

    private func setKind(_ kind: RoomKind, at idx: Int) {
        let oldBase = RoomNaming.defaultName(for: rooms[idx].kind ?? .unidentified)
        let name = rooms[idx].name
        rooms[idx].kind = kind
        if name == oldBase || name.hasPrefix(oldBase + " ") {
            rooms[idx].name = RoomNaming.defaultName(for: kind)
        }
        Haptics.selection()
    }

    private func field(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Brand.textFaint)
            TextField(placeholder, text: text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
    }
}

#Preview {
    ScanReviewView(
        rooms: RoomNaming.assignNames([
            { var r = RoomModel.mockLShaped; r.kind = .livingRoom; return r }(),
            { var r = HomeGeometry.transform(.mock, by: Pose2D(translation: Point2D(x: 5.2, z: 0))); r.kind = .bedroom; return r }()
        ]),
        modelURLs: [:], onSave: { _, _ in true }, onRescan: {}
    )
}
