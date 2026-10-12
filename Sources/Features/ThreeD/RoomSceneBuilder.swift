import SceneKit
import UIKit

/// Builds a SceneKit "dollhouse" straight from the portable RoomModel, so the
/// 3D view always matches the 2D plan exactly — edits and furniture included.
///
/// Frames: RoomModel's floor plane is world XZ (meters, Y up), the same as
/// SceneKit's, so points map 1:1. A plan yaw θ (from +X toward +Z) is a
/// SceneKit rotation of −θ about +Y.
@MainActor
enum RoomSceneBuilder {
    struct Palette {
        var background: UIColor
        var wallSide: UIColor
        var wallTop: UIColor
        var floor: UIColor
        var glass: UIColor
        var doorFrame: UIColor
    }

    struct Result {
        let scene: SCNScene
        /// Orbit centre and a camera distance that frames the whole model.
        let center: SCNVector3
        let radius: Float
    }

    static func palette(dark: Bool) -> Palette {
        if dark {
            return Palette(background: UIColor(red: 0.078, green: 0.125, blue: 0.102, alpha: 1),
                           wallSide: UIColor(red: 0.86, green: 0.83, blue: 0.76, alpha: 1),
                           wallTop: UIColor(red: 0.85, green: 0.75, blue: 0.53, alpha: 1),
                           floor: UIColor(red: 0.20, green: 0.24, blue: 0.21, alpha: 1),
                           glass: UIColor(red: 0.62, green: 0.78, blue: 0.80, alpha: 1),
                           doorFrame: UIColor(red: 0.78, green: 0.66, blue: 0.38, alpha: 1))
        }
        return Palette(background: UIColor(red: 0.988, green: 0.980, blue: 0.965, alpha: 1),
                       wallSide: UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1),
                       wallTop: UIColor(red: 0.17, green: 0.26, blue: 0.19, alpha: 1),
                       floor: UIColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 1),
                       glass: UIColor(red: 0.62, green: 0.78, blue: 0.80, alpha: 1),
                       doorFrame: UIColor(red: 0.60, green: 0.47, blue: 0.23, alpha: 1))
    }

    /// - Parameters:
    ///   - floorTints: optional per-room floor colours (same order as `rooms`).
    ///   - showScanObjects: also draw RoomPlan's detected objects as ghosts.
    static func build(rooms: [RoomModel], furniture: [PlacedFurniture],
                      floorTints: [UIColor]? = nil, showScanObjects: Bool = false,
                      dark: Bool) -> Result {
        let palette = palette(dark: dark)
        let scene = SCNScene()
        scene.background.contents = palette.background
        let root = scene.rootNode

        // Floors.
        for (i, room) in rooms.enumerated() {
            guard let poly = PlanGeometry.floorPolygon(room) else { continue }
            let color = floorTints.flatMap { i < $0.count ? $0[i] : nil } ?? palette.floor
            if let node = floorNode(poly, color: color) { root.addChildNode(node) }
        }

        // Walls — each physical wall once (shared walls appear in two rooms),
        // cut by the openings hosted on that very copy.
        let hosted = PlanGeometry.hostedOpenings(rooms)
        let wallGroup = SCNNode()
        for wall in PlanGeometry.mergedWalls(rooms) {
            let openings = hosted
                .filter { $0.opening.onWallId == wall.id && PlanGeometry.sameSegment($0.wall, wall) }
                .map(\.opening)
            addWall(wall, openings: openings, palette: palette, to: wallGroup)
        }
        root.addChildNode(wallGroup)

        // Furniture.
        for item in furniture { root.addChildNode(furnitureNode(item)) }
        if showScanObjects {
            for object in rooms.flatMap(\.detectedObjects) {
                root.addChildNode(ghostNode(object, dark: dark))
            }
        }

        addLights(to: root)

        // Framing.
        let bounds = PlanGeometry.worldBounds(rooms, includeObjects: false)
            ?? CGRect(x: -2, y: -2, width: 4, height: 4)
        let height = rooms.flatMap(\.walls).map(\.height).max() ?? 2.5
        let center = SCNVector3(Float(bounds.midX), Float(height * 0.25), Float(bounds.midY))
        let radius = Float(max(bounds.width, bounds.height, 2)) * 0.5
        return Result(scene: scene, center: center, radius: radius)
    }

    // MARK: - Pieces

    private static func floorNode(_ poly: [Point2D], color: UIColor) -> SCNNode? {
        let path = UIBezierPath()
        // Path (x, −z) rotated −90° about X lands on world (x, 0, z).
        path.move(to: CGPoint(x: poly[0].x, y: -poly[0].z))
        for p in poly.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: -p.z)) }
        path.close()
        let depth: CGFloat = 0.04
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.firstMaterial = material(color, roughness: 0.9)
        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = -.pi / 2
        node.position.y = Float(-depth / 2)
        return node
    }

    private static func addWall(_ wall: Wall, openings: [Opening], palette: Palette, to parent: SCNNode) {
        let length = wall.length
        guard length > 0.02 else { return }
        let height = wall.height > 0.3 ? wall.height : 2.5
        let thickness = max(wall.thickness, 0.08)
        let dir = wall.direction
        let yaw = Float(atan2(-dir.z, dir.x))

        var sized = wall
        sized.height = height
        let holes = WallMesh.holes(in: sized, openings: openings)
        let panels = WallMesh.panels(length: length, height: height, holes: holes.map(\.rect))

        let side = material(palette.wallSide, roughness: 0.85)
        let top = material(palette.wallTop, roughness: 0.6)
        for panel in panels {
            let box = SCNBox(width: CGFloat(panel.width), height: CGFloat(panel.height),
                             length: CGFloat(thickness), chamferRadius: 0)
            // SCNBox faces: front, right, back, left, top, bottom.
            box.materials = [side, side, side, side, top, side]
            let node = SCNNode(geometry: box)
            let along = wall.start + dir * ((panel.u0 + panel.u1) / 2)
            node.position = SCNVector3(Float(along.x), Float((panel.v0 + panel.v1) / 2), Float(along.z))
            node.eulerAngles.y = yaw
            parent.addChildNode(node)
        }

        for hole in holes {
            let along = wall.start + dir * ((hole.rect.u0 + hole.rect.u1) / 2)
            switch hole.kind {
            case .window:
                let pane = SCNBox(width: CGFloat(hole.rect.width), height: CGFloat(hole.rect.height),
                                  length: 0.015, chamferRadius: 0)
                let glass = material(palette.glass, roughness: 0.05)
                glass.transparency = 0.35
                glass.writesToDepthBuffer = false
                pane.materials = [glass]
                let node = SCNNode(geometry: pane)
                node.position = SCNVector3(Float(along.x), Float((hole.rect.v0 + hole.rect.v1) / 2), Float(along.z))
                node.eulerAngles.y = yaw
                node.renderingOrder = 10
                parent.addChildNode(node)
            case .door:
                // A slim frame reads as a doorway rather than a gap in the wall.
                let frame = SCNBox(width: CGFloat(hole.rect.width) + 0.06, height: 0.05,
                                   length: CGFloat(thickness) + 0.01, chamferRadius: 0)
                frame.materials = [material(palette.doorFrame, roughness: 0.6)]
                let node = SCNNode(geometry: frame)
                node.position = SCNVector3(Float(along.x), Float(hole.rect.v1) + 0.025, Float(along.z))
                node.eulerAngles.y = yaw
                parent.addChildNode(node)
            case .opening:
                break
            }
        }
    }

    private static func furnitureNode(_ item: PlacedFurniture) -> SCNNode {
        let group = SCNNode()
        group.position = SCNVector3(Float(item.center.x), 0, Float(item.center.z))
        group.eulerAngles.y = Float(-item.rotation)
        let color = UIColor(hex: item.resolvedColorHex)
        let body = material(color, roughness: 0.75)
        let topMaterial: SCNMaterial = {
            if let id = item.photoID, let photo = FurniturePhotoStore.image(for: id) {
                let m = material(.white, roughness: 0.8)
                m.diffuse.contents = photo
                return m
            }
            return material(color.lighter(0.08), roughness: 0.75)
        }()
        let height = CGFloat(max(item.height, 0.01))

        if item.shape == .round {
            let cylinder = SCNCylinder(radius: CGFloat(item.width / 2), height: height)
            cylinder.radialSegmentCount = 36
            cylinder.materials = [body, topMaterial, body]   // side, top, bottom
            let node = SCNNode(geometry: cylinder)
            node.position.y = Float(height / 2)
            node.scale.z = Float(item.depth / max(item.width, 0.01))
            group.addChildNode(node)
            return group
        }

        for box in FurnitureGeometry.localBoxes(item) {
            let chamfer = CGFloat(min(0.03, min(box.width, box.depth, Double(height)) * 0.2))
            let geometry = SCNBox(width: CGFloat(box.width), height: height,
                                  length: CGFloat(box.depth), chamferRadius: chamfer)
            geometry.materials = [body, body, body, body, topMaterial, body]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float(box.center.x), Float(height / 2), Float(box.center.z))
            group.addChildNode(node)
        }
        return group
    }

    private static func ghostNode(_ object: DetectedObject, dark: Bool) -> SCNNode {
        let box = SCNBox(width: CGFloat(max(object.width, 0.05)), height: CGFloat(max(object.height, 0.05)),
                         length: CGFloat(max(object.depth, 0.05)), chamferRadius: 0.01)
        let m = material(dark ? UIColor(white: 0.85, alpha: 1) : UIColor(white: 0.55, alpha: 1), roughness: 0.9)
        m.transparency = 0.35
        box.materials = [m]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float(object.center.x), Float(max(object.height, 0.05) / 2), Float(object.center.z))
        node.eulerAngles.y = Float(-object.rotation)
        return node
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(white: 1, alpha: 1)
        root.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 750
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowColor = UIColor(white: 0, alpha: 0.28)
        sun.light?.shadowRadius = 6
        sun.light?.shadowSampleCount = 8
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        root.addChildNode(sun)
    }

    private static func material(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }
}

extension UIColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Blend toward white by `amount` (0…1).
    func lighter(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount,
                       blue: b + (1 - b) * amount, alpha: a)
    }
}
