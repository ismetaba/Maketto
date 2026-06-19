import Foundation

extension RoomModel {
    /// A closed 4×3 m rectangular room with known wall lengths (4, 3, 4, 3),
    /// for previews and unit tests — no device needed.
    static var mock: RoomModel {
        let c0 = Point2D(x: 0, z: 0)
        let c1 = Point2D(x: 4, z: 0)
        let c2 = Point2D(x: 4, z: 3)
        let c3 = Point2D(x: 0, z: 3)
        let walls = [
            Wall(start: c0, end: c1),   // 4.0 m
            Wall(start: c1, end: c2),   // 3.0 m
            Wall(start: c2, end: c3),   // 4.0 m
            Wall(start: c3, end: c0),   // 3.0 m
        ]
        return RoomModel(
            name: "Mock Room",
            walls: walls,
            floorOutline: [c0, c1, c2, c3],
            source: .manual
        )
    }

    /// An L-shaped room with a door, a window, a plain opening and two objects
    /// (one rotated) — exercises poché corners, all opening symbols, yaw
    /// orientation, and outside-dimension placement in the F2 plan preview.
    static var mockLShaped: RoomModel {
        let a = Point2D(x: 0, z: 0)
        let b = Point2D(x: 5, z: 0)
        let c = Point2D(x: 5, z: 5)
        let d = Point2D(x: 2, z: 5)
        let e = Point2D(x: 2, z: 2)
        let f = Point2D(x: 0, z: 2)

        let wAB = Wall(start: a, end: b, thickness: 0.12, height: 2.5)
        let wBC = Wall(start: b, end: c, thickness: 0.12, height: 2.5)
        let wCD = Wall(start: c, end: d, thickness: 0.12, height: 2.5)
        let wDE = Wall(start: d, end: e, thickness: 0.12, height: 2.5)
        let wEF = Wall(start: e, end: f, thickness: 0.12, height: 2.5)
        let wFA = Wall(start: f, end: a, thickness: 0.12, height: 2.5)

        let openings = [
            Opening(type: .door, onWallId: wAB.id, offset: 2.5, width: 0.9, height: 2.05),
            Opening(type: .window, onWallId: wBC.id, offset: 2.5, width: 1.2, height: 1.2, sillHeight: 0.9),
            Opening(type: .opening, onWallId: wEF.id, offset: 1.0, width: 0.8, height: 2.1),
        ]
        let objects = [
            DetectedObject(category: "sofa", center: Point2D(x: 1.4, z: 1.0),
                           width: 2.0, depth: 0.9, height: 0.8, rotation: 0),
            DetectedObject(category: "table", center: Point2D(x: 3.4, z: 3.4),
                           width: 1.2, depth: 0.8, height: 0.5, rotation: .pi / 6),
        ]
        return RoomModel(
            name: "L-Shaped Room",
            walls: [wAB, wBC, wCD, wDE, wEF, wFA],
            openings: openings,
            detectedObjects: objects,
            floorOutline: [a, b, c, d, e, f],
            source: .manual
        )
    }
}

extension VersionSnapshot {
    static var mock: VersionSnapshot { VersionSnapshot(room: .mock) }
}
