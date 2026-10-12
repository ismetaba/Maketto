import SwiftUI
import SceneKit
import UIKit

/// Interactive native 3D "dollhouse" of one room or a whole home, built from
/// the same RoomModel as the 2D plan (orbit, pinch, pan). Rebuilds only when
/// its inputs change; bump `resetToken` to glide the camera back home.
struct RoomSceneView: UIViewRepresentable {
    let rooms: [RoomModel]
    var furniture: [PlacedFurniture] = []
    var floorTints: [Color]? = nil
    var showScanObjects: Bool = false
    var resetToken: Int = 0

    @Environment(\.colorScheme) private var colorScheme

    final class Coordinator {
        var signature: Int?
        var resetToken = 0
        var home: SCNVector3 = SCNVector3Zero
        var radius: Float = 3
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.maximumVerticalAngle = 88
        view.defaultCameraController.minimumVerticalAngle = 4
        view.accessibilityLabel = "3B görünüm"
        context.coordinator.resetToken = resetToken
        rebuildIfNeeded(view, context: context)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        rebuildIfNeeded(view, context: context)
        if context.coordinator.resetToken != resetToken {
            context.coordinator.resetToken = resetToken
            frameCamera(view, coordinator: context.coordinator, animated: true)
        }
    }

    private var dark: Bool { colorScheme == .dark }

    private func rebuildIfNeeded(_ view: SCNView, context: Context) {
        var hasher = Hasher()
        hasher.combine(rooms)
        hasher.combine(furniture)
        hasher.combine(showScanObjects)
        hasher.combine(dark)
        hasher.combine(floorTints?.count ?? -1)
        let signature = hasher.finalize()
        guard signature != context.coordinator.signature else { return }
        let firstBuild = context.coordinator.signature == nil
        context.coordinator.signature = signature

        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let tints = floorTints?.map { UIColor($0).resolvedColor(with: traits) }
        let result = RoomSceneBuilder.build(rooms: rooms, furniture: furniture, floorTints: tints,
                                            showScanObjects: showScanObjects, dark: dark)
        // Keep the user's current viewpoint across edits; frame on first build.
        let keptCamera = firstBuild ? nil : view.pointOfView
        view.scene = result.scene
        context.coordinator.home = result.center
        context.coordinator.radius = result.radius
        if let keptCamera {
            result.scene.rootNode.addChildNode(keptCamera)
            view.pointOfView = keptCamera
        } else {
            frameCamera(view, coordinator: context.coordinator, animated: false)
        }
        view.defaultCameraController.target = result.center
    }

    /// An architect's three-quarter view that frames the whole model.
    private func frameCamera(_ view: SCNView, coordinator: Coordinator, animated: Bool) {
        guard let scene = view.scene else { return }
        let node: SCNNode
        if let existing = view.pointOfView, existing.camera != nil {
            node = existing
        } else {
            node = SCNNode()
            node.camera = SCNCamera()
            scene.rootNode.addChildNode(node)
        }
        node.camera?.fieldOfView = 45
        node.camera?.zNear = 0.05
        node.camera?.zFar = 400
        let c = coordinator.home
        let distance = coordinator.radius * 2.6 + 1.5
        let elevation: Float = .pi / 3.4
        let azimuth: Float = .pi / 5
        let target = SCNVector3(
            c.x + distance * cos(elevation) * sin(azimuth),
            c.y + distance * sin(elevation),
            c.z + distance * cos(elevation) * cos(azimuth)
        )
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.45 : 0
        node.position = target
        node.look(at: c)
        SCNTransaction.commit()
        view.pointOfView = node
        view.defaultCameraController.target = c
    }
}

#Preview {
    RoomSceneView(rooms: [.mockLShaped], furniture: [
        FurnitureCatalog.presets[0].instantiate(at: Point2D(x: 3.4, z: 3.6), rotation: .pi)
    ])
}
