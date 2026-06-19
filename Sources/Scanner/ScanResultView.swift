import SwiftUI

/// The F1 acceptance surface: shows each wall length in m and cm so the user
/// can verify the scan against a tape measure, then name + save the room.
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
        VStack(spacing: 0) {
            if let modelURL {
                USDZSceneView(url: modelURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
            }
            measurements
        }
        .navigationTitle("Scan Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(name) }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Rescan") { onRetry() }
            }
        }
    }

    private var measurements: some View {
        List {
            Section("Room Name") {
                TextField("Room name", text: $name)
            }

            Section {
                ForEach(room.wallMeasurements) { measurement in
                    HStack {
                        Text(measurement.label)
                        Spacer()
                        Text(MeasurementFormat.metersAndCentimeters(measurement.meters))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Wall Lengths")
            } footer: {
                Text("Compare these against a tape measure to verify scan accuracy.")
            }

            if !room.detectedObjects.isEmpty {
                Section("Detected Objects") {
                    ForEach(room.detectedObjects) { object in
                        Text(object.category.capitalized)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ScanResultView(room: .mock, modelURL: nil, onSave: { _ in }, onRetry: {})
    }
}
