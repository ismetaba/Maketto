import SwiftUI

/// The full-screen room editor: the maket fills the screen, chrome floats over
/// it. No measurement tables — tap a wall and its measure appears on the model.
/// Zoom/fit dock at the trailing edge; 2D/3D and stats live in the bottom dock.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    let roomID: UUID

    enum PlanMode: String, CaseIterable { case twoD = "2D", threeD = "3D" }
    @State private var planMode: PlanMode = .twoD
    @State private var camera = PlanCamera()
    @State private var showVisualizeSoon = false
    @State private var editable: EditableRoom?        // non-nil = edit mode
    @State private var editTool: PlanTool = .move
    @State private var showDiscard = false
    @State private var saveFailed = false
    @State private var showRename = false
    @State private var renameText = ""

    private var room: RoomModel? { store.roomModel(for: roomID) }
    private var isEditing: Bool { editable != nil }

    var body: some View {
        let room = room
        ZStack {
            Brand.surface.ignoresSafeArea()
            if let room {
                editor(room: room)
            } else {
                ContentUnavailableView("Oda bulunamadı", systemImage: "exclamationmark.triangle")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Görselleştirme yakında", isPresented: $showVisualizeSoon) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Yapay zekâ ile fotogerçekçi oda görselleri bir sonraki sürümde gelecek.")
        }
        .alert("Kaydedilemedi", isPresented: $saveFailed) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Düzenlemen kaydedilemedi. Lütfen tekrar dene.")
        }
        .renameAlert("Odayı Yeniden Adlandır", placeholder: "Oda adı",
                     isPresented: $showRename, text: $renameText) {
            store.renameRoom(id: roomID, to: renameText)
        }
        .confirmationDialog("Değişiklikleri at?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("At", role: .destructive) { closeEditor() }
            Button("Düzenlemeye dön", role: .cancel) {}
        } message: {
            Text("Kaydedilmemiş değişikliklerin kaybolacak.")
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func editor(room: RoomModel) -> some View {
        ZStack {
            canvas(room: room)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(room: room)
                // Controls live in the free region between the bars so they
                // can never collide with the docks or the FAB.
                Spacer()
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        if isEditing || planMode == .twoD {
                            MapControlStack(camera: camera)
                                .padding(.trailing, 12)
                        }
                    }
                if isEditing {
                    VStack(spacing: 10) {
                        editHint
                        editDock
                    }
                    .padding(.bottom, 14)
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            VisualizeFAB { showVisualizeSoon = true }
                        }
                        .padding(.horizontal, 18)
                        viewDock(room: room)
                    }
                    .padding(.bottom, 14)
                }
            }
        }
    }

    /// Regions of the full-bleed canvas covered by floating chrome (status bar
    /// + top bar above, docks + home indicator below) — keeps the measurement
    /// pill clamped into the visible map.
    private var chromeInsets: EdgeInsets {
        EdgeInsets(top: 112, leading: 10, bottom: 150, trailing: 10)
    }

    @ViewBuilder
    private func canvas(room: RoomModel) -> some View {
        if let editable {
            FloorPlanView(room: room, camera: camera, chromeInsets: chromeInsets,
                          editing: editable, editTool: editTool)
        } else {
            switch planMode {
            case .twoD:
                FloorPlanView(room: room, camera: camera, chromeInsets: chromeInsets)
            case .threeD:
                // The URL lookup stats the disk, so resolve it only when 3D shows.
                if let modelURL = store.modelURL(for: roomID) {
                    USDZSceneView(url: modelURL)
                } else {
                    ZStack {
                        Brand.surface
                        ContentUnavailableView("3D model yok", systemImage: "cube")
                    }
                }
            }
        }
    }

    // MARK: - Top bar

    private func topBar(room: RoomModel) -> some View {
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
                    Menu {
                        Button {
                            renameText = room.name
                            showRename = true
                        } label: {
                            Label("Yeniden Adlandır", systemImage: "pencil")
                        }
                        Button { camera.reset() } label: {
                            Label("Plana Sığdır", systemImage: "viewfinder")
                        }
                    } label: {
                        CircleIcon(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Oda seçenekleri")

                    CircleIconButton("pencil.and.ruler", accessibilityLabel: "Planı düzenle") { enterEdit() }
                }
            }
        }
        // Overlay with symmetric padding keeps the title truly centred even
        // though the two button sides have different widths.
        .overlay {
            VStack(spacing: 1) {
                Overline(isEditing ? "Düzenleniyor" : (room.kind ?? .unidentified).displayName,
                         color: isEditing ? Brand.clay : Brand.textSecondary, size: 9)
                HStack(spacing: 7) {
                    Text(room.name)
                        .font(.display(19))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    if !isEditing {
                        Text("v\(store.versionCount(for: roomID))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x453516))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Brand.gold, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 96)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .frostedChip(cornerRadius: 20)
        .padding(.horizontal, 12)
        .padding(.top, 6)
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
    }

    // MARK: - Bottom docks

    /// View mode: 2D/3D switch + live room stats in one glass dock.
    private func viewDock(room: RoomModel) -> some View {
        HStack(spacing: 12) {
            segment
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(MeasurementFormat.squareMeters(PlanGeometry.area(of: room)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.textPrimary)
                Text("\(room.walls.count) duvar · \(room.openings.count) açıklık")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
            }
            .padding(.trailing, 6)
        }
        .padding(6)
        .glassPanel(cornerRadius: 22)
    }

    private var segment: some View {
        HStack(spacing: 4) {
            ForEach(PlanMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { planMode = mode }
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
            }
        }
    }

    /// Edit mode: a one-line hint so the active tool is never a mystery.
    /// (Exhaustive switch — a future tool cannot ship without hint copy.)
    private var editHint: some View {
        let text: String
        switch editTool {
        case .move: text = "Köşeleri sürükleyerek planı düzeltin"
        case .delete: text = "Silmek için bir duvara dokunun"
        }
        return Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frostedChip()
    }

    private var editDock: some View {
        HStack(spacing: 4) {
            toolButton(.move, icon: "hand.draw", label: "Taşı")
            toolButton(.delete, icon: "trash", label: "Sil")
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 22).padding(.horizontal, 2)
            dockIcon("arrow.uturn.backward", label: "Geri al",
                     enabled: editable?.canUndo ?? false) { editable?.undo() }
            dockIcon("arrow.uturn.forward", label: "Yinele",
                     enabled: editable?.canRedo ?? false) { editable?.redo() }
        }
        .padding(4)
        .glassPanel(cornerRadius: 16)
    }

    private func toolButton(_ tool: PlanTool, icon: String, label: String) -> some View {
        let on = editTool == tool
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editTool = tool }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(on ? .white : Brand.textSecondary)
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background { if on { Capsule().fill(tool == .delete ? Brand.clay : Brand.evergreen) } }
        }
        .buttonStyle(.plain)
    }

    private func dockIcon(_ icon: String, label: String, enabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Brand.textPrimary : Brand.textSecondary.opacity(0.35))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - Edit lifecycle

    private func enterEdit() {
        guard let room = store.roomModel(for: roomID) else { return }
        planMode = .twoD
        editTool = .move
        camera.reset()   // always start editing from the fitted plan, handles on-screen
        Haptics.light()
        withAnimation(.maketto) {
            editable = EditableRoom(room)
        }
    }

    private func save() {
        guard let editable else { return }
        guard editable.isDirty else { closeEditor(); return }
        if store.saveEditedRoom(id: roomID, editedDisplayRoom: editable.flattened()) {
            Haptics.success()
            closeEditor()
        } else {
            saveFailed = true
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
        withAnimation(.maketto) { editable = nil }
        camera.reset()
    }
}
