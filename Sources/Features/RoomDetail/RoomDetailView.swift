import SwiftUI
import UIKit

/// Detail of a saved room: a 3D / 2D-plan toggle on top, measurements below.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    let roomID: UUID

    enum PlanMode: String, CaseIterable { case threeD = "3D", twoD = "2D" }
    @State private var planMode: PlanMode = .threeD
    @State private var didChooseInitialMode = false

    private var room: RoomModel? { store.roomModel(for: roomID) }

    var body: some View {
        // Resolve once per render — roomModel(for:) does a fetch + JSON decode.
        let room = room
        let modelURL = store.modelURL(for: roomID)
        return Group {
            if let room {
                VStack(spacing: 0) {
                    visualBand(room: room, modelURL: modelURL)
                    measurements(room: room)
                }
            } else {
                ContentUnavailableView(
                    "Room Not Found",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle(room?.name ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Default to the 2D plan when the room has no 3D model, so it never
            // opens on a dead "No 3D Model" placeholder. One-shot: don't stomp the
            // user's later choice.
            if !didChooseInitialMode {
                didChooseInitialMode = true
                if store.modelURL(for: roomID) == nil { planMode = .twoD }
            }
        }
    }

    // MARK: - Visual band (3D model / 2D plan)

    private func visualBand(room: RoomModel, modelURL: URL?) -> some View {
        ZStack(alignment: .topTrailing) {
            switch planMode {
            case .threeD:
                if let modelURL {
                    USDZSceneView(url: modelURL)
                } else {
                    ContentUnavailableView("No 3D Model", systemImage: "cube")
                }
            case .twoD:
                FloorPlanView(room: room)
            }

            Picker("View", selection: $planMode) {
                ForEach(PlanMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Measurements

    private func measurements(room: RoomModel) -> some View {
        List {
            Section("Walls") {
                ForEach(room.wallMeasurements) { measurement in
                    HStack {
                        Text(measurement.label)
                        Spacer()
                        Text(MeasurementFormat.metersAndCentimeters(measurement.meters))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Summary") {
                LabeledContent("Walls", value: "\(room.walls.count)")
                LabeledContent("Openings", value: "\(room.openings.count)")
                LabeledContent("Detected objects", value: "\(room.detectedObjects.count)")
                LabeledContent("Total wall length",
                               value: MeasurementFormat.meters(room.totalWallLength))
            }
        }
    }
}
