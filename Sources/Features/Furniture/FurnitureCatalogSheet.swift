import SwiftUI

/// "Eşya Ekle": the furniture catalog. Built-in, real-sized presets grouped by
/// room, the user's own pieces (with photos), and a one-tap import of the
/// furniture RoomPlan detected during the scan.
struct FurnitureCatalogSheet: View {
    /// Detected objects not yet imported into this room.
    let importableCount: Int
    let onPick: (FurnitureTemplate) -> Void
    let onImportScanned: () -> Void

    @Environment(FurnitureLibrary.self) private var library
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showCreator = false
    @State private var deleteTarget: FurnitureTemplate?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if query.isEmpty, importableCount > 0 { importCard }
                    customSection
                    ForEach(filteredSections, id: \.title) { section in
                        sectionView(section.title, items: section.items)
                    }
                    if !query.isEmpty, filteredSections.isEmpty, filteredCustom.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Brand.surfaceAlt.ignoresSafeArea())
            .navigationTitle("Eşya Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Eşya ara")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreator) {
                FurnitureCreatorSheet { template in
                    onPick(template)
                    dismiss()
                }
            }
            .confirmationDialog("\u{201C}\(deleteTarget?.name ?? "")\u{201D} silinsin mi?",
                                isPresented: deletePresented, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    if let target = deleteTarget { delete(target) }
                    deleteTarget = nil
                }
                Button("Vazgeç", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Eşya listenizden kaldırılır. Plana daha önce yerleştirdikleriniz kalır.")
            }
        }
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private func delete(_ template: FurnitureTemplate) {
        guard let photoID = library.delete(id: template.id) else { return }
        // Keep the photo while any saved plan still shows it.
        if !store.isPhotoReferenced(photoID) { FurniturePhotoStore.delete(photoID) }
    }

    // MARK: - Filtering

    private func matches(_ t: FurnitureTemplate) -> Bool {
        query.isEmpty
            || t.name.localizedStandardContains(query)
            || t.category.displayName.localizedStandardContains(query)
    }

    private var filteredCustom: [FurnitureTemplate] { library.custom.filter(matches) }

    private var filteredSections: [(title: String, items: [FurnitureTemplate])] {
        FurnitureCatalog.sections
            .map { ($0.title, $0.items.filter(matches)) }
            .filter { !$0.1.isEmpty }
    }

    // MARK: - Pieces

    private var importCard: some View {
        Button {
            onImportScanned()
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Brand.clayGradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Taramadaki eşyaları ekle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Taramada bulunan \(importableCount) eşya plana yerleştirilir; sonra taşıyabilirsiniz.")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Brand.clay)
            }
            .padding(14)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var customSection: some View {
        if query.isEmpty || !filteredCustom.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Overline("Benim Eşyalarım", color: Brand.clay)
                LazyVGrid(columns: columns, spacing: 12) {
                    if query.isEmpty {
                        Button { showCreator = true } label: { newItemCard }
                            .buttonStyle(.plain)
                    }
                    ForEach(filteredCustom) { template in
                        Button { pick(template) } label: { FurnitureCard(template: template) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { deleteTarget = template } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private var newItemCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Brand.clay)
                .frame(width: 46, height: 46)
                .background(Brand.clay.opacity(0.12), in: Circle())
            Text("Yeni Eşya")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.textPrimary)
            Text("Ölçü + fotoğraf")
                .font(.system(size: 12))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Brand.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Brand.clay.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }

    private func sectionView(_ title: String, items: [FurnitureTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Overline(title)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { template in
                    Button { pick(template) } label: { FurnitureCard(template: template) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ template: FurnitureTemplate) {
        Haptics.selection()
        onPick(template)
        dismiss()
    }
}

/// One catalog tile: photo (or a tinted icon), name and real size.
struct FurnitureCard: View {
    let template: FurnitureTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                let tint = Color(hex: UInt(template.colorHex ?? template.category.defaultColorHex))
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.16))
                if let id = template.photoID, let photo = FurniturePhotoStore.image(for: id) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: template.category.icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            .frame(height: 82)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                Text(template.sizeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Brand.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(template.name), \(template.sizeLabel)")
    }
}
