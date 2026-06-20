import SwiftUI

/// The "reveal" after a scan: the maket appears, you name it and start designing.
/// Tap any wall to verify its measure against a tape (the F1 acceptance check).
struct ScanResultView: View {
    let room: RoomModel
    let modelURL: URL?
    let onSave: (String) -> Void
    let onRetry: () -> Void

    @State private var name: String

    init(room: RoomModel, modelURL: URL?, onSave: @escaping (String) -> Void, onRetry: @escaping () -> Void) {
        self.room = room
        self.modelURL = modelURL
        self.onSave = onSave
        self.onRetry = onRetry
        _name = State(initialValue: room.name)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Brand.surface.ignoresSafeArea()
            FloorPlanView(room: room).ignoresSafeArea()

            readyPill.padding(.top, 64)

            VStack {
                Spacer()
                bottomCard
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var readyPill: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(Brand.evergreenSoft)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            Text("Maketiniz hazır").font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.textPrimary)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .frostedChip()
    }

    private var bottomCard: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(Brand.textFaint)
                TextField("Oda adı", text: $name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            )

            Button { onSave(name) } label: {
                HStack(spacing: 9) {
                    Text("Tasarıma başla")
                    Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EvergreenButtonStyle())

            Button { onRetry() } label: {
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
}

#Preview {
    ScanResultView(room: .mockLShaped, modelURL: nil, onSave: { _ in }, onRetry: {})
}
