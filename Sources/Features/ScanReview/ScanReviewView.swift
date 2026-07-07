import SwiftUI

/// After a whole-home scan: the auto-split rooms on the tinted map, with
/// default names. Select a room (on the map or via its chip) to rename it and
/// fix its type; name the home; save.
struct ScanReviewView: View {
    let modelURLs: [UUID: URL]
    let onSave: ([RoomModel], String) -> Bool
    let onRescan: () -> Void

    @State private var rooms: [RoomModel]
    /// The auto-assigned name per room — a name still matching it was never
    /// touched by the user, so a kind change may refresh it.
    @State private var autoNames: [UUID: String]
    @State private var homeName = "Evim"
    @State private var selectedRoomID: UUID?
    @State private var saveFailed = false
    @State private var showRescanConfirm = false
    @State private var camera = PlanCamera()

    init(rooms: [RoomModel], modelURLs: [UUID: URL],
         onSave: @escaping ([RoomModel], String) -> Bool, onRescan: @escaping () -> Void) {
        _rooms = State(initialValue: rooms)
        _autoNames = State(initialValue: Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.name) }))
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
                withAnimation(.maketto) { selectedRoomID = id }
                if id != nil { Haptics.selection() }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topRow
                // The controls live between the bars so they can never collide
                // with the chips/card on short screens.
                Spacer()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        MapControlStack(camera: camera).padding(.trailing, 12)
                    }
                VStack(spacing: 12) {
                    chipsRow
                    bottomCard
                }
                .frame(maxWidth: 468)   // don't stretch edge-to-edge on iPad
                .padding(.bottom, 6)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Kaydedilemedi", isPresented: $saveFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Bir sorun oluştu. Lütfen tekrar deneyin.")
        }
        .confirmationDialog("Yeniden taransın mı?", isPresented: $showRescanConfirm,
                            titleVisibility: .visible) {
            Button("Yeniden Tara", role: .destructive) { onRescan() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu tarama ve yaptığınız tüm düzenlemeler silinir.")
        }
    }

    // MARK: - Pieces

    /// Rescan on the left, scan summary centred, ghost slot balancing the row.
    private var topRow: some View {
        HStack(spacing: 8) {
            CircleIconButton("arrow.counterclockwise", accessibilityLabel: "Yeniden tara") {
                showRescanConfirm = true
            }
            Spacer()
            summaryPill
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

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
        RoomChipsRow(
            entries: rooms.enumerated().map { i, room in
                RoomChipsRow.Entry(id: room.id, name: room.name, tint: RoomPalette.tint(i))
            },
            selectedID: selectedRoomID
        ) { id in
            withAnimation(.maketto) { selectedRoomID = id }
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
        }
        .padding(18)
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
        let room = rooms[idx]
        rooms[idx].kind = kind
        // Refresh the default name only while it is still the auto-assigned
        // one — a name the user typed is never overwritten.
        if room.name == autoNames[room.id] {
            let fresh = RoomNaming.defaultName(for: kind)
            rooms[idx].name = fresh
            autoNames[room.id] = fresh
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
