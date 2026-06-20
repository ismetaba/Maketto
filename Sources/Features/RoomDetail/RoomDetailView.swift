import SwiftUI

/// The full-screen editor: the maket fills the screen, chrome floats over it.
/// No measurement tables — tap a wall and its measure appears on the model.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    @Environment(Router.self) private var router
    let roomID: UUID

    enum PlanMode: String, CaseIterable { case twoD = "2D", threeD = "3D" }
    @State private var planMode: PlanMode = .twoD
    @State private var showVisualizeSoon = false
    @State private var editable: EditableRoom?        // non-nil = edit mode
    @State private var editTool: PlanTool = .move
    @State private var showDiscard = false
    @State private var saveFailed = false

    private var room: RoomModel? { store.roomModel(for: roomID) }
    private var isEditing: Bool { editable != nil }

    var body: some View {
        let room = room
        let modelURL = store.modelURL(for: roomID)
        ZStack {
            Brand.surface.ignoresSafeArea()
            if let room {
                editor(room: room, modelURL: modelURL)
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
        .confirmationDialog("Değişiklikleri at?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("At", role: .destructive) { editable = nil }
            Button("Düzenlemeye dön", role: .cancel) {}
        } message: {
            Text("Kaydedilmemiş değişikliklerin kaybolacak.")
        }
    }

    @ViewBuilder
    private func editor(room: RoomModel, modelURL: URL?) -> some View {
        ZStack {
            canvas(room: room, modelURL: modelURL)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(room: room)
                Spacer()
                Group {
                    if isEditing { editDock } else { segment }
                }
                .padding(.bottom, 36)
            }

            if !isEditing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fab.padding(.trailing, 18).padding(.bottom, 110)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func canvas(room: RoomModel, modelURL: URL?) -> some View {
        if let editable {
            FloorPlanView(room: room, editing: editable, editTool: editTool)
        } else {
            switch planMode {
            case .twoD:
                FloorPlanView(room: room)
            case .threeD:
                if let modelURL {
                    USDZSceneView(url: modelURL)
                } else {
                    ZStack {
                        Brand.surface
                        ContentUnavailableView("3B model yok", systemImage: "cube")
                    }
                }
            }
        }
    }

    private func topBar(room: RoomModel) -> some View {
        HStack {
            if isEditing {
                circleButton("xmark") { attemptCancel() }
            } else {
                circleButton("chevron.left") { router.pop() }
            }
            Spacer()
            VStack(spacing: 1) {
                Overline(isEditing ? "Düzenleniyor" : "Maketto", color: Brand.textSecondary, size: 9)
                HStack(spacing: 7) {
                    Text(room.name)
                        .font(.display(19))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    if !isEditing {
                        Text("v\(store.versionCount(for: roomID))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Brand.gold, in: Capsule())
                    }
                }
            }
            Spacer()
            if isEditing {
                saveButton
            } else {
                circleButton("slider.horizontal.3") { enterEdit() }
            }
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

    private var editDock: some View {
        HStack(spacing: 4) {
            toolButton(.move, icon: "hand.draw", label: "Taşı")
            toolButton(.delete, icon: "trash", label: "Sil")
            Rectangle().fill(Brand.hairline).frame(width: 1, height: 22).padding(.horizontal, 2)
            dockIcon("arrow.uturn.backward", enabled: editable?.canUndo ?? false) { editable?.undo() }
            dockIcon("arrow.uturn.forward", enabled: editable?.canRedo ?? false) { editable?.redo() }
        }
        .padding(4)
        .frostedChip(cornerRadius: 14)
    }

    private func toolButton(_ tool: PlanTool, icon: String, label: String) -> some View {
        let on = editTool == tool
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { editTool = tool }
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

    private func dockIcon(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Brand.textPrimary : Brand.textSecondary.opacity(0.35))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Edit lifecycle

    private func enterEdit() {
        guard let room = store.roomModel(for: roomID) else { return }
        planMode = .twoD
        editTool = .move
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            editable = EditableRoom(room)
        }
    }

    private func save() {
        guard let editable else { return }
        guard editable.isDirty else { self.editable = nil; return }
        if store.saveEditedRoom(id: roomID, editedDisplayRoom: editable.flattened()) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.editable = nil }
        } else {
            saveFailed = true
        }
    }

    private func attemptCancel() {
        if editable?.isDirty ?? false {
            showDiscard = true
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { editable = nil }
        }
    }

    private var segment: some View {
        HStack(spacing: 4) {
            ForEach(PlanMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { planMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(planMode == mode ? .white : Brand.textSecondary)
                        .padding(.vertical, 8).padding(.horizontal, 18)
                        .background {
                            if planMode == mode { Capsule().fill(Brand.clay) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frostedChip(cornerRadius: 14)
    }

    private var fab: some View {
        Button { showVisualizeSoon = true } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Brand.clayGradient, in: Circle())
                .shadow(color: Brand.clayDeep.opacity(0.6), radius: 16, x: 0, y: 10)
        }
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
