import SwiftUI

/// After a whole-home scan: the auto-split rooms on the map, with default names.
/// Tap a room to rename it; name the home; save.
struct ScanReviewView: View {
    let modelURLs: [UUID: URL]
    let onSave: ([RoomModel], String) -> Bool
    let onRescan: () -> Void

    @State private var rooms: [RoomModel]
    @State private var homeName = "Evim"
    @State private var selectedRoomID: UUID?
    @State private var saveFailed = false

    init(rooms: [RoomModel], modelURLs: [UUID: URL],
         onSave: @escaping ([RoomModel], String) -> Bool, onRescan: @escaping () -> Void) {
        _rooms = State(initialValue: rooms)
        self.modelURLs = modelURLs
        self.onSave = onSave
        self.onRescan = onRescan
    }

    private var totalArea: Double { rooms.reduce(0) { $0 + PlanGeometry.area(of: $1) } }

    var body: some View {
        ZStack(alignment: .top) {
            Brand.surface.ignoresSafeArea()

            WholeHomePlanView(rooms: rooms, selectedRoomID: selectedRoomID) { id in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedRoomID = id }
            }
            .ignoresSafeArea()

            summaryPill.padding(.top, 64)

            VStack { Spacer(); bottomCard }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Kaydedilemedi", isPresented: $saveFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Bir sorun oluştu. Lütfen tekrar deneyin.")
        }
    }

    private var summaryPill: some View {
        Text("\(rooms.count) oda · \(MeasurementFormat.squareMeters(totalArea))")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frostedChip()
    }

    private var bottomCard: some View {
        VStack(spacing: 12) {
            if let id = selectedRoomID, let idx = rooms.firstIndex(where: { $0.id == id }) {
                field(icon: "pencil", placeholder: "Oda adı", text: roomName(idx))
            } else {
                Text("Bir odaya dokunup adını düzenleyin")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }

            field(icon: "house", placeholder: "Ev adı", text: $homeName)

            Button { if !onSave(rooms, homeName) { saveFailed = true } } label: {
                HStack(spacing: 9) {
                    Text("Kaydet")
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EvergreenButtonStyle())

            Button { onRescan() } label: {
                Text("Yeniden tara")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(18)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Brand.hairline.opacity(0.7), lineWidth: 0.5)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func roomName(_ idx: Int) -> Binding<String> {
        Binding(get: { rooms[idx].name }, set: { rooms[idx].name = $0 })
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
