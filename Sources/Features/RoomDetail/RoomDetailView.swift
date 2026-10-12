import SwiftUI

/// The full-screen room editor: the maket fills the screen, chrome floats over
/// it. No measurement tables — tap a wall and its measure appears on the model.
///
/// View mode: 2D plan / native 3D, room stats, version history, share.
/// Edit mode: select (drag corners & furniture), draw walls, erase; add
/// furniture from the catalog; every change is undoable and saved as a new
/// version.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    let roomID: UUID

    enum PlanMode: String, CaseIterable { case twoD = "2D", threeD = "3D" }

    @State private var planMode: PlanMode = .twoD
    @State private var camera = PlanCamera()
    @State private var sceneResetToken = 0
    @State private var showScanObjects = false
    @State private var editable: EditableRoom?        // non-nil = edit mode
    @State private var editTool: PlanTool = .select
    @State private var selection: PlanSelection?

    @State private var showCatalog = false
    @State private var showVersions = false
    @State private var showDiscard = false
    @State private var showDeleteRoom = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var notice: Notice?
    @State private var share: ShareItem?

    @State private var showLength = false
    @State private var lengthTarget: UUID?
    @State private var lengthText = ""

    @State private var showSize = false
    @State private var sizeTarget: UUID?
    @State private var widthText = ""
    @State private var depthText = ""
    @State private var heightText = ""
    @State private var angleText = ""

    private enum Notice: String, Identifiable {
        case saveFailed, needsWalls, invalidLength, invalidSize, exportFailed, deleteFailed
        var id: String { rawValue }

        var title: String {
            switch self {
            case .saveFailed: return "Kaydedilemedi"
            case .needsWalls: return "Plan boş"
            case .invalidLength: return "Geçersiz uzunluk"
            case .invalidSize: return "Geçersiz ölçü"
            case .exportFailed: return "Dışa aktarılamadı"
            case .deleteFailed: return "Silinemedi"
            }
        }

        var message: String {
            switch self {
            case .saveFailed: return "Düzenlemeniz kaydedilemedi. Lütfen tekrar deneyin."
            case .needsWalls: return "Kaydetmek için planda en az bir duvar olmalı. Geri alarak silinen duvarları getirebilirsiniz."
            case .invalidLength: return "Uzunluğu 5 ile 10000 cm arasında bir sayı olarak girin."
            case .invalidSize: return "Genişlik ve derinlik 5–2000 cm, yükseklik 0,5–600 cm olmalı."
            case .exportFailed: return "Dosya oluşturulamadı. Lütfen tekrar deneyin."
            case .deleteFailed: return "Oda silinemedi. Lütfen tekrar deneyin."
            }
        }
    }

    private var isEditing: Bool { editable != nil }

    var body: some View {
        let document = store.document(for: roomID)
        ZStack {
            Brand.surface.ignoresSafeArea()
            if let document {
                screen(document)
            } else {
                missingRoom
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showCatalog) {
            FurnitureCatalogSheet(
                importableCount: editable.map { importableObjects($0).count } ?? 0,
                onPick: { place($0) },
                onImportScanned: { importScanned() }
            )
        }
        .sheet(isPresented: $showVersions) {
            VersionHistorySheet(roomID: roomID)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $share) { item in
            ShareSheet(item: item).ignoresSafeArea()
        }
        .alert(notice?.title ?? "", isPresented: noticePresented, presenting: notice) { _ in
            Button("Tamam", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .renameAlert("Odayı Yeniden Adlandır", placeholder: "Oda adı",
                     isPresented: $showRename, text: $renameText) {
            store.renameRoom(id: roomID, to: renameText)
        }
        .alert("Duvar Uzunluğu", isPresented: $showLength, presenting: lengthTarget) { wallID in
            TextField("Santimetre", text: $lengthText)
                .keyboardType(.decimalPad)
            Button("Uygula") { applyLength(wallID) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Yeni uzunluğu santimetre olarak girin. Duvarın bitiş köşesi taşınır; ona dik bağlı duvar da birlikte kayar.")
        }
        .alert("Ölçü ve Açı", isPresented: $showSize, presenting: sizeTarget) { itemID in
            TextField("Genişlik (cm)", text: $widthText).keyboardType(.decimalPad)
            TextField("Derinlik (cm)", text: $depthText).keyboardType(.decimalPad)
            TextField("Yükseklik (cm)", text: $heightText).keyboardType(.decimalPad)
            TextField("Açı (°)", text: $angleText).keyboardType(.numbersAndPunctuation)
            Button("Uygula") { applySize(itemID) }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Genişlik, derinlik ve yüksekliği santimetre; açıyı derece olarak girin.")
        }
        .confirmationDialog("Değişiklikler atılsın mı?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Değişiklikleri At", role: .destructive) { closeEditor() }
            Button("Düzenlemeye Dön", role: .cancel) {}
        } message: {
            Text("Kaydedilmemiş değişiklikleriniz kaybolacak.")
        }
        .confirmationDialog("Bu oda silinsin mi?", isPresented: $showDeleteRoom, titleVisibility: .visible) {
            Button("Odayı Sil", role: .destructive) { deleteRoom() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Oda tüm sürümleriyle birlikte evden kaldırılır. Bu işlem geri alınamaz.")
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private var missingRoom: some View {
        VStack(spacing: 18) {
            ContentUnavailableView("Oda bulunamadı", systemImage: "exclamationmark.triangle",
                                   description: Text("Bu oda silinmiş olabilir."))
            Button("Geri Dön") { router.pop() }
                .buttonStyle(EvergreenButtonStyle())
        }
    }

    // MARK: - Layout

    private func screen(_ document: RoomDocument) -> some View {
        ZStack {
            canvas(document)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(document)
                // Controls live in the free region between the bars so they
                // can never collide with the docks.
                Spacer()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) { trailingControls.padding(.trailing, 12) }
                if let editable {
                    editBottom(editable).padding(.bottom, 14)
                } else {
                    viewBottom(document).padding(.bottom, 14)
                }
            }
        }
    }

    /// Regions of the full-bleed canvas covered by floating chrome (status bar
    /// + top bar above, docks + home indicator below) — keeps pills visible.
    private var chromeInsets: EdgeInsets {
        EdgeInsets(top: 112, leading: 10, bottom: isEditing ? 190 : 150, trailing: 64)
    }

    @ViewBuilder
    private func canvas(_ document: RoomDocument) -> some View {
        if let editable {
            FloorPlanView(room: document.room, showScanObjects: showScanObjects,
                          camera: camera, chromeInsets: chromeInsets,
                          editing: editable, editTool: editTool, selection: $selection)
        } else {
            switch planMode {
            case .twoD:
                FloorPlanView(room: document.room, furniture: document.furniture,
                              showScanObjects: showScanObjects, camera: camera,
                              chromeInsets: chromeInsets, selection: $selection)
            case .threeD:
                RoomSceneView(rooms: [document.room], furniture: document.furniture,
                              showScanObjects: showScanObjects, resetToken: sceneResetToken)
            }
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isEditing || planMode == .twoD {
            MapControlStack(camera: camera)
        } else {
            CircleIconButton("viewfinder", accessibilityLabel: "Görünümü sıfırla") {
                sceneResetToken += 1
                Haptics.light()
            }
        }
    }

    // MARK: - Top bar

    private func topBar(_ document: RoomDocument) -> some View {
        HStack(spacing: 8) {
            if isEditing {
                CircleIconButton("xmark", accessibilityLabel: "Düzenlemeden çık") { attemptCancel() }
            } else {
                CircleIconButton("chevron.left", accessibilityLabel: "Geri") { router.pop() }
            }
            Spacer()
            if isEditing {
                saveButton
            } else {
                HStack(spacing: 6) {
                    roomMenu(document)
                    CircleIconButton("pencil.and.ruler", accessibilityLabel: "Planı düzenle") { enterEdit() }
                }
            }
        }
        // Overlay with symmetric padding keeps the title truly centred even
        // though the two button sides have different widths.
        .overlay { title(document).padding(.horizontal, 96) }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frostedChip(cornerRadius: 20)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func title(_ document: RoomDocument) -> some View {
        VStack(spacing: 1) {
            Overline(isEditing ? "Düzenleniyor" : (document.room.kind ?? .unidentified).displayName,
                     color: isEditing ? Brand.clay : Brand.textSecondary, size: 9)
            HStack(spacing: 7) {
                Text(document.room.name)
                    .font(.display(19))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                if !isEditing {
                    Button { showVersions = true } label: {
                        Text("v\(document.versionNumber)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x453516))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Brand.gold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sürüm \(document.versionNumber) / \(document.versionCount), \(document.versionLabel)")
                    .accessibilityHint("Sürüm geçmişini açar")
                }
            }
        }
    }

    private func roomMenu(_ document: RoomDocument) -> some View {
        Menu {
            Button {
                renameText = document.room.name
                showRename = true
            } label: {
                Label("Yeniden Adlandır", systemImage: "pencil")
            }
            Button { showVersions = true } label: {
                Label("Sürümler (\(document.versionCount))", systemImage: "clock.arrow.circlepath")
            }
            Toggle(isOn: $showScanObjects) {
                Label("Taranan Eşyaları Göster", systemImage: "viewfinder")
            }
            Divider()
            Button { sharePlan(document) } label: {
                Label("Planı Paylaş", systemImage: "square.and.arrow.up")
            }
            Button { shareData(document) } label: {
                Label("Ölçüleri Dışa Aktar (JSON)", systemImage: "doc.text")
            }
            if document.canDeleteRoom {
                Divider()
                Button(role: .destructive) { showDeleteRoom = true } label: {
                    Label("Odayı Sil", systemImage: "trash")
                }
            }
        } label: {
            CircleIcon(systemName: "ellipsis")
        }
        .accessibilityLabel("Oda seçenekleri")
    }

    private var saveButton: some View {
        let dirty = editable?.isDirty ?? false
        return Button { save() } label: {
            Text("Kaydet")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(dirty ? Brand.clay : Brand.clay.opacity(0.4), in: Capsule())
        }
        .disabled(!dirty)
        .accessibilityHint(dirty ? "Değişiklikleri yeni bir sürüm olarak kaydeder" : "Kaydedilecek değişiklik yok")
    }

    // MARK: - View mode bottom

    private func viewBottom(_ document: RoomDocument) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button { enterEdit(openCatalog: true) } label: {
                    Label("Eşya Ekle", systemImage: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                        .background(Brand.clayGradient, in: Capsule())
                        .shadow(color: Brand.clayDeep.opacity(0.45), radius: 14, x: 0, y: 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            viewDock(document)
        }
    }

    /// 2D/3D switch + live room stats in one glass dock.
    private func viewDock(_ document: RoomDocument) -> some View {
        HStack(spacing: 12) {
            segment
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(MeasurementFormat.squareMeters(PlanGeometry.area(of: document.room)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.textPrimary)
                Text(stats(document))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(1)
            }
            .padding(.trailing, 6)
        }
        .padding(6)
        .glassPanel(cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    private func stats(_ document: RoomDocument) -> String {
        var parts = ["\(document.room.walls.count) duvar"]
        if !document.room.openings.isEmpty { parts.append("\(document.room.openings.count) açıklık") }
        if !document.furniture.isEmpty { parts.append("\(document.furniture.count) eşya") }
        return parts.joined(separator: " · ")
    }

    private var segment: some View {
        HStack(spacing: 4) {
            ForEach(PlanMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { planMode = mode }
                    selection = nil
                    Haptics.selection()
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(planMode == mode ? .white : Brand.textSecondary)
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .background {
                            if planMode == mode { Capsule().fill(Brand.clay) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(planMode == mode ? .isSelected : [])
            }
        }
    }

    // MARK: - Edit mode bottom

    private func editBottom(_ editable: EditableRoom) -> some View {
        VStack(spacing: 10) {
            Group {
                if case .wall(let id) = selection, editTool == .select, let wall = editable.wall(id) {
                    wallCard(wall)
                } else if case .furniture(let id) = selection, editTool == .select,
                          let item = editable.furnitureItem(id) {
                    furnitureCard(item, editable: editable)
                } else {
                    editHint
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            editDock(editable)
        }
        .animation(.maketto, value: selection)
        .animation(.maketto, value: editTool)
    }

    /// One line of guidance so the active tool is never a mystery.
    /// (Exhaustive switch — a future tool cannot ship without hint copy.)
    private var editHint: some View {
        let text: String
        switch editTool {
        case .select: text = "Köşeleri ve eşyaları sürükleyin; ölçü için bir duvara dokunun"
        case .draw: text = "Yeni duvar için sürükleyin; uçlar köşelere ve duvarlara bağlanır"
        case .erase: text = "Silmek için bir duvara ya da eşyaya dokunun"
        }
        return Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Brand.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frostedChip(cornerRadius: 16)
            .padding(.horizontal, 20)
    }

    private func wallCard(_ wall: Wall) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.diagonal")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.clay)
                .frame(width: 38, height: 38)
                .background(Brand.clay.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Overline("Duvar", color: Brand.textFaint, size: 10)
                Text(MeasurementFormat.meters(wall.length))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Brand.textPrimary)
            }
            Spacer(minLength: 4)
            Button {
                lengthTarget = wall.id
                lengthText = MeasurementFormat.centimeterInput(wall.length)
                showLength = true
            } label: {
                Label("Uzunluk", systemImage: "ruler")
            }
            .buttonStyle(SoftButtonStyle())
            Button {
                withAnimation(.maketto) {
                    editable?.deleteWall(wall.id)
                    selection = nil
                }
                Haptics.light()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.clay)
                    .frame(width: 44, height: 44)
                    .background(Brand.card, in: Circle())
                    .overlay(Circle().strokeBorder(Brand.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Duvarı sil")
        }
        .padding(12)
        .glassPanel(cornerRadius: 22)
        .padding(.horizontal, 14)
        .frame(maxWidth: 520)
    }

    private func furnitureCard(_ item: PlacedFurniture, editable: EditableRoom) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                let tint = Color(hex: UInt(item.resolvedColorHex))
                Image(systemName: item.category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    Text("\(item.sizeLabel) · \(MeasurementFormat.degreesInput(item.rotation))°")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer(minLength: 0)
                CircleIconButton("xmark", size: 30, accessibilityLabel: "Seçimi kapat") {
                    withAnimation(.maketto) { selection = nil }
                }
            }
            HStack(spacing: 0) {
                cardAction("rotate.left", "90° Sola") { editable.rotateFurniture(item.id, by: -.pi / 2) }
                cardAction("rotate.right", "90° Sağa") { editable.rotateFurniture(item.id, by: .pi / 2) }
                cardAction("ruler", "Ölçü") { beginSizeEdit(item) }
                if item.shape == .lShape {
                    cardAction("arrow.left.and.right", "Çevir") {
                        editable.updateFurniture(item.id) { $0.mirrored.toggle() }
                    }
                }
                cardAction("plus.square.on.square", "Çoğalt") {
                    if let copy = editable.duplicateFurniture(item.id) {
                        withAnimation(.maketto) { selection = .furniture(copy) }
                    }
                }
                cardAction("trash", "Sil", destructive: true) {
                    withAnimation(.maketto) {
                        editable.deleteFurniture(item.id)
                        selection = nil
                    }
                }
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 22)
        .padding(.horizontal, 14)
        .frame(maxWidth: 520)
    }

    private func cardAction(_ icon: String, _ label: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.light()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(destructive ? Brand.clay : Brand.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func editDock(_ editable: EditableRoom) -> some View {
        ViewThatFits(in: .horizontal) {
            dock(editable, compact: false)
            dock(editable, compact: true)
        }
        .padding(.horizontal, 12)
    }

    private func dock(_ editable: EditableRoom, compact: Bool) -> some View {
        HStack(spacing: 2) {
            toolButton(.select, icon: "hand.point.up.left", label: "Seç", compact: compact)
            toolButton(.draw, icon: "pencil.line", label: "Çiz", compact: compact)
            toolButton(.erase, icon: "eraser", label: "Sil", compact: compact)
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 22).padding(.horizontal, 3)
            Button { showCatalog = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    if !compact { Text("Eşya").font(.system(size: 13, weight: .bold)) }
                }
                .foregroundStyle(.white)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(Brand.clayGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eşya ekle")
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 22).padding(.horizontal, 3)
            dockIcon("arrow.uturn.backward", label: "Geri al", enabled: editable.canUndo) {
                withAnimation(.maketto) { editable.undo(); validateSelection(editable) }
            }
            dockIcon("arrow.uturn.forward", label: "Yinele", enabled: editable.canRedo) {
                withAnimation(.maketto) { editable.redo(); validateSelection(editable) }
            }
        }
        .padding(4)
        .glassPanel(cornerRadius: 18)
        .fixedSize()
    }

    private func toolButton(_ tool: PlanTool, icon: String, label: String, compact: Bool) -> some View {
        let on = editTool == tool
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                editTool = tool
                if tool != .select { selection = nil }
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                if !compact { Text(label).font(.system(size: 13, weight: .bold)) }
            }
            .foregroundStyle(on ? .white : Brand.textSecondary)
            .padding(.vertical, 8).padding(.horizontal, compact ? 10 : 11)
            .background { if on { Capsule().fill(tool == .erase ? Brand.clay : Brand.evergreen) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func dockIcon(_ icon: String, label: String, enabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Brand.textPrimary : Brand.textSecondary.opacity(0.35))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - Edit lifecycle

    private func enterEdit(openCatalog: Bool = false) {
        guard editable == nil, let document = store.document(for: roomID) else { return }
        planMode = .twoD
        editTool = .select
        selection = nil
        camera.reset()   // always start editing from the fitted plan, handles on-screen
        Haptics.light()
        withAnimation(.maketto) {
            editable = EditableRoom(document.room, furniture: document.furniture)
        }
        if openCatalog { showCatalog = true }
    }

    private func save() {
        guard let editable else { return }
        guard editable.isDirty else { closeEditor(); return }
        guard !editable.edges.isEmpty else { notice = .needsWalls; return }
        if store.saveEditedRoom(id: roomID, editedDisplayRoom: editable.flattened(),
                                furniture: editable.furniture) {
            Haptics.success()
            closeEditor()
        } else {
            notice = .saveFailed
        }
    }

    private func attemptCancel() {
        if editable?.isDirty ?? false {
            showDiscard = true
        } else {
            closeEditor()
        }
    }

    /// Leave edit mode and return to the fitted overview.
    private func closeEditor() {
        withAnimation(.maketto) {
            editable = nil
            selection = nil
        }
        camera.reset()
    }

    /// Drop a selection whose wall/piece no longer exists (after undo/redo).
    private func validateSelection(_ editable: EditableRoom) {
        switch selection {
        case .wall(let id) where editable.wall(id) == nil: selection = nil
        case .furniture(let id) where editable.furnitureItem(id) == nil: selection = nil
        default: break
        }
    }

    // MARK: - Furniture

    private func place(_ template: FurnitureTemplate) {
        guard let editable else { return }
        let item = template.instantiate(at: freeSpot(in: editable))
        withAnimation(.maketto) {
            editable.addFurniture(item)
            editTool = .select
            selection = .furniture(item.id)
        }
        Haptics.success()
    }

    /// The room's centre, nudged diagonally past pieces already sitting there.
    private func freeSpot(in editable: EditableRoom) -> Point2D {
        let base = PlanGeometry.roomCenter(editable.flattened()) ?? Point2D(x: 0, z: 0)
        var spot = base
        var step = 0
        while step < 12, editable.furniture.contains(where: { $0.center.distance(to: spot) < 0.2 }) {
            step += 1
            spot = base + Point2D(x: 0.3 * Double(step), z: 0.3 * Double(step))
        }
        return spot
    }

    private func importableObjects(_ editable: EditableRoom) -> [DetectedObject] {
        let imported = Set(editable.furniture.compactMap(\.templateID))
        return editable.detectedObjects.filter {
            !imported.contains(PlacedFurniture.detectedTemplateID($0))
        }
    }

    private func importScanned() {
        guard let editable else { return }
        let items = importableObjects(editable).map(PlacedFurniture.init(detected:))
        guard !items.isEmpty else { return }
        withAnimation(.maketto) {
            editable.addFurniture(items)
            editTool = .select
            selection = nil
        }
        Haptics.success()
    }

    private func beginSizeEdit(_ item: PlacedFurniture) {
        sizeTarget = item.id
        widthText = MeasurementFormat.centimeterInput(item.width)
        depthText = MeasurementFormat.centimeterInput(item.depth)
        heightText = MeasurementFormat.centimeterInput(item.height)
        angleText = MeasurementFormat.degreesInput(item.rotation)
        showSize = true
    }

    private func applySize(_ itemID: UUID) {
        guard let editable,
              let w = MeasurementFormat.parseCentimeters(widthText), (0.05...20).contains(w),
              let d = MeasurementFormat.parseCentimeters(depthText), (0.05...20).contains(d),
              let h = MeasurementFormat.parseCentimeters(heightText), (0.005...6).contains(h),
              let angle = MeasurementFormat.parseDegrees(angleText) else {
            notice = .invalidSize
            return
        }
        editable.updateFurniture(itemID) {
            $0.width = w
            $0.depth = d
            $0.height = h
            $0.rotation = FurnitureGeometry.normalized(angle)
            if $0.shape == .lShape, let arm = $0.armDepth { $0.armDepth = min(arm, min(w, d) * 0.6) }
        }
        Haptics.success()
    }

    private func applyLength(_ wallID: UUID) {
        guard let editable, let meters = MeasurementFormat.parseCentimeters(lengthText),
              (0.05...100).contains(meters) else {
            notice = .invalidLength
            return
        }
        if editable.setLength(of: wallID, to: meters) { Haptics.success() }
    }

    // MARK: - Room actions

    private func deleteRoom() {
        if store.deleteRoom(id: roomID) {
            router.pop()
        } else {
            notice = .deleteFailed
        }
    }

    private func sharePlan(_ document: RoomDocument) {
        let subtitle = "\(MeasurementFormat.squareMeters(PlanGeometry.area(of: document.room))) · v\(document.versionNumber) · \(document.versionLabel)"
        guard let url = PlanExporter.planImage(rooms: [document.room], furniture: document.furniture,
                                               title: document.room.name, subtitle: subtitle) else {
            notice = .exportFailed
            return
        }
        share = ShareItem(urls: [url])
    }

    private func shareData(_ document: RoomDocument) {
        guard let url = PlanExporter.roomJSON(document.room, furniture: document.furniture) else {
            notice = .exportFailed
            return
        }
        share = ShareItem(urls: [url])
    }
}

#Preview {
    let store = RoomStore.preview
    let roomID = store.homes.first.flatMap { store.homeModel(for: $0.id)?.rooms.first?.id } ?? UUID()
    return NavigationStack { RoomDetailView(roomID: roomID) }
        .environment(store)
        .environment(Router())
        .environment(FurnitureLibrary(fileURL: nil))
}
