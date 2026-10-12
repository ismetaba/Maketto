import SwiftUI

/// A room's saved versions (newest first), each with a plan preview. Restore
/// any version (nothing is lost — the one you leave stays in the list),
/// rename it, or delete versions you no longer need.
struct VersionHistorySheet: View {
    let roomID: UUID

    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var restoreTarget: VersionInfo?
    @State private var renameTarget: VersionInfo?
    @State private var renameText = ""
    @State private var deleteTarget: VersionInfo?
    @State private var failed = false

    var body: some View {
        let versions = store.versions(for: roomID)
        NavigationStack {
            List {
                Section {
                    ForEach(versions) { version in
                        row(version)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !version.isCurrent else { return }
                                restoreTarget = version
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !version.isCurrent {
                                    Button(role: .destructive) { deleteTarget = version } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                                Button { beginRename(version) } label: {
                                    Label("Adlandır", systemImage: "pencil")
                                }
                                .tint(Brand.evergreenSoft)
                            }
                            .contextMenu {
                                if !version.isCurrent {
                                    Button { restoreTarget = version } label: {
                                        Label("Bu Sürüme Dön", systemImage: "clock.arrow.circlepath")
                                    }
                                }
                                Button { beginRename(version) } label: {
                                    Label("Yeniden Adlandır", systemImage: "pencil")
                                }
                                if !version.isCurrent {
                                    Button(role: .destructive) { deleteTarget = version } label: {
                                        Label("Sil", systemImage: "trash")
                                    }
                                }
                            }
                    }
                } footer: {
                    Text("Planı her kaydettiğinizde yeni bir sürüm oluşur. Eski bir sürüme dönmek hiçbir şeyi silmez.")
                }
            }
            .navigationTitle("Sürümler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("\u{201C}\(restoreTarget?.label ?? "")\u{201D} sürümüne dönülsün mü?",
                                isPresented: binding($restoreTarget), titleVisibility: .visible) {
                Button("Bu Sürüme Dön") {
                    if let target = restoreTarget {
                        if store.restoreVersion(roomID: roomID, versionID: target.id) {
                            Haptics.success()
                            dismiss()
                        } else {
                            failed = true
                        }
                    }
                    restoreTarget = nil
                }
                Button("Vazgeç", role: .cancel) { restoreTarget = nil }
            } message: {
                Text("Şu anki plan sürümler listesinde kalır.")
            }
            .confirmationDialog("\u{201C}\(deleteTarget?.label ?? "")\u{201D} silinsin mi?",
                                isPresented: binding($deleteTarget), titleVisibility: .visible) {
                Button("Sürümü Sil", role: .destructive) {
                    if let target = deleteTarget,
                       !store.deleteVersion(roomID: roomID, versionID: target.id) {
                        failed = true
                    }
                    deleteTarget = nil
                }
                Button("Vazgeç", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Bu işlem geri alınamaz.")
            }
            .renameAlert("Sürümü Adlandır", placeholder: "Sürüm adı",
                         isPresented: binding($renameTarget), text: $renameText) {
                if let target = renameTarget,
                   !store.renameVersion(roomID: roomID, versionID: target.id, to: renameText) {
                    failed = true
                }
                renameTarget = nil
            }
            .alert("İşlem yapılamadı", isPresented: $failed) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text("Lütfen tekrar deneyin.")
            }
        }
    }

    private func beginRename(_ version: VersionInfo) {
        renameText = version.label
        renameTarget = version
    }

    private func binding(_ value: Binding<VersionInfo?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    private func row(_ version: VersionInfo) -> some View {
        HStack(spacing: 14) {
            FloorPlanView(room: version.room, furniture: version.furniture, interactive: false)
                .frame(width: 76, height: 76)
                .background(Brand.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(version.isCurrent ? Brand.clay : Brand.hairline,
                                  lineWidth: version.isCurrent ? 2 : 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(version.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    if version.isCurrent {
                        Text("Güncel")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Brand.clay, in: Capsule())
                    }
                }
                Text(MeasurementFormat.dateTime(version.createdAt))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                Text(summary(version))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.textFaint)
            }
            Spacer(minLength: 0)
            if !version.isCurrent {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint(version.isCurrent ? "" : "Bu sürüme dönmek için dokunun")
    }

    private func summary(_ version: VersionInfo) -> String {
        var parts = [MeasurementFormat.squareMeters(PlanGeometry.area(of: version.room)),
                     "\(version.room.walls.count) duvar"]
        if !version.furniture.isEmpty { parts.append("\(version.furniture.count) eşya") }
        return parts.joined(separator: " · ")
    }
}
