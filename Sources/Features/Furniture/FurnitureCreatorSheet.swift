import SwiftUI
import PhotosUI

/// Create a custom piece: name, type, shape, real size (cm) and an optional
/// photo. Saved to the user's library and handed back for placement.
struct FurnitureCreatorSheet: View {
    let onCreated: (FurnitureTemplate) -> Void

    @Environment(FurnitureLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: FurnitureCategory = .sofa
    @State private var shape: FurnitureShape = .rectangle
    @State private var widthText = "200"
    @State private var depthText = "90"
    @State private var heightText = "80"
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var loadingPhoto = false
    @State private var saveFailed = false

    private var width: Double? { MeasurementFormat.parseCentimeters(widthText) }
    private var depth: Double? { MeasurementFormat.parseCentimeters(depthText) }
    private var height: Double? { MeasurementFormat.parseCentimeters(heightText) }

    private var isValid: Bool {
        guard let width, let depth, let height else { return false }
        return (0.05...20).contains(width) && (0.05...20).contains(depth) && (0.005...6).contains(height)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(hex: UInt(category.defaultColorHex)).opacity(0.16))
                                if let photo {
                                    Image(uiImage: photo).resizable().scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else if loadingPhoto {
                                    ProgressView()
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Brand.clay)
                                }
                            }
                            .frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo == nil ? "Fotoğraf ekle" : "Fotoğrafı değiştir")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Brand.textPrimary)
                                Text("Planda eşyanın üstünde görünür")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Brand.textSecondary)
                            }
                        }
                    }
                    if photo != nil {
                        Button("Fotoğrafı kaldır", role: .destructive) {
                            photo = nil
                            photoItem = nil
                        }
                    }
                }

                Section("Bilgiler") {
                    TextField("Ad (örn. Kanepe)", text: $name)
                        .textInputAutocapitalization(.sentences)
                    Picker("Tür", selection: $category) {
                        ForEach(FurnitureCategory.allCases, id: \.self) { c in
                            Label(c.displayName, systemImage: c.icon).tag(c)
                        }
                    }
                    Picker("Biçim", selection: $shape) {
                        Text("Dikdörtgen").tag(FurnitureShape.rectangle)
                        Text("Yuvarlak").tag(FurnitureShape.round)
                        Text("L Köşe").tag(FurnitureShape.lShape)
                    }
                }

                Section {
                    sizeRow("Genişlik", text: $widthText)
                    sizeRow("Derinlik", text: $depthText)
                    sizeRow("Yükseklik", text: $heightText)
                } header: {
                    Text("Ölçüler")
                } footer: {
                    if !isValid {
                        Text("Genişlik ve derinlik 5–2000 cm, yükseklik 0,5–600 cm olmalı.")
                            .foregroundStyle(Brand.clay)
                    } else {
                        Text("Gerçek ölçüleri santimetre olarak girin; plan ölçeğe sadık çizilir.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Yeni Eşya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { save() }
                        .fontWeight(.bold)
                        .disabled(!isValid || loadingPhoto)
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .alert("Eşya kaydedilemedi", isPresented: $saveFailed) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text("Lütfen tekrar deneyin.")
            }
        }
    }

    private func sizeRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text("cm").foregroundStyle(Brand.textSecondary)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingPhoto = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            loadingPhoto = false
            if let data, let image = UIImage(data: data) { photo = image }
        }
    }

    private func save() {
        guard isValid, let width, let depth, let height else { return }
        let photoID = photo.flatMap { FurniturePhotoStore.save($0) }
        guard let template = library.add(name: name, category: category, shape: shape,
                                         width: width, depth: depth, height: height,
                                         photoID: photoID) else {
            if let photoID { FurniturePhotoStore.delete(photoID) }
            saveFailed = true
            return
        }
        Haptics.success()
        onCreated(template)
        dismiss()
    }
}
