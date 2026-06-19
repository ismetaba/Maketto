import SwiftUI
import SceneKit
import UIKit

/// Interactive 3D preview of a USDZ file (orbit / pinch / pan) — used to show
/// the RoomPlan scan's own 3D model alongside the measurements.
struct USDZSceneView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .secondarySystemBackground
        view.scene = try? SCNScene(url: url)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene == nil {
            uiView.scene = try? SCNScene(url: url)
        }
    }
}
