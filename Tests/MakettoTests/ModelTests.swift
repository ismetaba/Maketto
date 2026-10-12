import Foundation
import Testing
#if canImport(MakettoCore)
@testable import MakettoCore
#else
@testable import Maketto
#endif

struct FurnitureTests {
    @Test func lSofaFootprint() {
        let sofa = FurnitureCatalog.presets.first { $0.id == "sofa.l" }!
            .instantiate(at: Point2D(x: 0, z: 0))
        let poly = FurnitureGeometry.footprint(sofa)
        #expect(poly.count == 6)
        let arm = sofa.armDepth!
        let expected = sofa.width * arm + arm * (sofa.depth - arm)
        #expect(approx(abs(FloorGeometry.signedArea(poly)), expected))
        // The boxes the 3D view builds cover exactly the same area.
        let boxes = FurnitureGeometry.localBoxes(sofa)
        #expect(approx(boxes.reduce(0) { $0 + $1.width * $1.depth }, expected))
        // The chaise is solid, the empty corner of the L is not.
        #expect(FurnitureGeometry.contains(sofa, Point2D(x: sofa.width / 2 - 0.2, z: sofa.depth / 2 - 0.2)))
        #expect(!FurnitureGeometry.contains(sofa, Point2D(x: -sofa.width / 2 + 0.2, z: sofa.depth / 2 - 0.2)))
    }

    @Test func mirroredLSofaFlipsTheChaise() {
        var sofa = FurnitureCatalog.presets.first { $0.id == "sofa.l" }!
            .instantiate(at: Point2D(x: 0, z: 0))
        sofa.mirrored = true
        #expect(FurnitureGeometry.contains(sofa, Point2D(x: -sofa.width / 2 + 0.2, z: sofa.depth / 2 - 0.2)))
        #expect(FloorGeometry.signedArea(FurnitureGeometry.footprint(sofa)) > 0)
    }

    @Test func rotationIsRigid() {
        let item = PlacedFurniture(name: "x", center: Point2D(x: 1, z: 2), width: 2, depth: 1, rotation: 0.6)
        let local = Point2D(x: 0.3, z: -0.2)
        let back = FurnitureGeometry.toLocal(FurnitureGeometry.toWorld(local, of: item), of: item)
        #expect(back.distance(to: local) < 1e-12)
    }

    @Test func rotatedPiecesDoNotWallSnap() {
        let item = PlacedFurniture(name: "x", center: Point2D(x: 2, z: 0.6), width: 1, depth: 1, rotation: 0.3)
        let snapped = FurnitureGeometry.snappedToWalls(item, walls: rectangleWalls(4, 3), tolerance: 0.5)
        #expect(snapped == item)
    }

    @Test func decodesSparsePayloads() throws {
        let json = #"{"center":{"x":1,"z":2},"width":0.5,"depth":0.4,"category":"spaceship"}"#
        let item = try JSONDecoder().decode(PlacedFurniture.self, from: Data(json.utf8))
        #expect(item.category == .other)
        #expect(item.shape == .rectangle)
        #expect(item.height == 0.8)
        let again = try JSONDecoder().decode(PlacedFurniture.self, from: JSONEncoder().encode(item))
        #expect(again == item)
    }

    @Test func importsScannedObjects() {
        let object = DetectedObject(category: "bed", center: Point2D(x: 1, z: 1),
                                    width: 1.6, depth: 2, height: 0.5, rotation: 0.1)
        let item = PlacedFurniture(detected: object)
        #expect(item.category == .bed)
        #expect(item.name == "Yatak")
        #expect(item.width == 1.6 && item.rotation == 0.1)
    }

    @Test func catalogSectionsCoverEveryPreset() {
        let total = FurnitureCatalog.sections.reduce(0) { $0 + $1.items.count }
        #expect(total == FurnitureCatalog.presets.count)
        #expect(Set(FurnitureCatalog.presets.map(\.id)).count == FurnitureCatalog.presets.count)
    }

    @Test func normalizesAngles() {
        #expect(approx(FurnitureGeometry.normalized(3 * .pi), .pi))
        #expect(approx(FurnitureGeometry.normalized(-.pi / 2 - 2 * .pi), -.pi / 2))
    }
}

struct WallMeshTests {
    private func area(_ rects: [WallMesh.Rect]) -> Double { rects.reduce(0) { $0 + $1.width * $1.height } }

    @Test func solidWallIsOnePanel() {
        let panels = WallMesh.panels(length: 4, height: 2.5, holes: [])
        #expect(panels == [WallMesh.Rect(u0: 0, u1: 4, v0: 0, v1: 2.5)])
    }

    @Test func doorAndWindowAreCutOut() {
        let wall = Wall(start: Point2D(x: 0, z: 0), end: Point2D(x: 5, z: 0), height: 2.5)
        let openings = [
            Opening(type: .door, onWallId: wall.id, offset: 1, width: 0.9, height: 2.05),
            Opening(type: .window, onWallId: wall.id, offset: 3.5, width: 1.2, height: 1.2, sillHeight: 0.9),
            Opening(type: .window, onWallId: UUID(), offset: 2, width: 1, height: 1),   // other wall
        ]
        let holes = WallMesh.holes(in: wall, openings: openings)
        #expect(holes.count == 2)
        let panels = WallMesh.panels(length: 5, height: 2.5, holes: holes.map(\.rect))
        #expect(approx(area(panels), 5 * 2.5 - 0.9 * 2.05 - 1.2 * 1.2))
        // No panel overlaps a hole.
        for p in panels {
            for h in holes.map(\.rect) {
                let overlapU = min(p.u1, h.u1) - max(p.u0, h.u0)
                let overlapV = min(p.v1, h.v1) - max(p.v0, h.v0)
                #expect(!(overlapU > 1e-9 && overlapV > 1e-9))
            }
        }
    }

    @Test func overlappingAndOverflowingOpeningsStayValid() {
        let wall = Wall(start: Point2D(x: 0, z: 0), end: Point2D(x: 3, z: 0), height: 2.4)
        let openings = [
            Opening(type: .door, onWallId: wall.id, offset: 0.2, width: 1, height: 3),   // past both edges
            Opening(type: .opening, onWallId: wall.id, offset: 0.8, width: 1, height: 2),
        ]
        let holes = WallMesh.holes(in: wall, openings: openings).map(\.rect)
        let panels = WallMesh.panels(length: 3, height: 2.4, holes: holes)
        #expect(panels.allSatisfy { $0.width > 0 && $0.height > 0 && $0.v1 <= 2.4 && $0.u0 >= 0 })
        // Hole union: [0,0.7]×[0,2.4] ∪ [0.3,1.3]×[0,2] → 0.7·2.4 + 0.6·2.0
        #expect(approx(area(panels), 3 * 2.4 - (0.7 * 2.4 + 0.6 * 2.0)))
    }
}

struct SnapshotTests {
    @Test func legacySnapshotsWithoutNewFieldsDecode() throws {
        let room = try String(data: JSONEncoder().encode(RoomModel.mock), encoding: .utf8)!
        let legacy = #"{"schemaVersion":1,"room":"# + room + "}"
        let snap = try JSONDecoder().decode(VersionSnapshot.self, from: Data(legacy.utf8))
        #expect(snap.furniture.isEmpty)
        #expect(snap.renders.isEmpty)
        #expect(snap.room.walls.count == 4)
    }

    @Test func roundTripsFurniture() throws {
        let item = FurnitureCatalog.presets[0].instantiate(at: Point2D(x: 1, z: 1), rotation: 0.5)
        let snap = VersionSnapshot(room: .mockLShaped, furniture: [item])
        let back = try JSONDecoder().decode(VersionSnapshot.self, from: JSONEncoder().encode(snap))
        #expect(back == snap)
        #expect(back.schemaVersion == VersionSnapshot.currentSchemaVersion)
    }

    @Test func corruptFurnitureNeverHidesTheRoom() throws {
        let room = try String(data: JSONEncoder().encode(RoomModel.mock), encoding: .utf8)!
        let json = #"{"room":"# + room + #","furniture":[{"bogus":true}]}"#
        let snap = try JSONDecoder().decode(VersionSnapshot.self, from: Data(json.utf8))
        #expect(snap.furniture.isEmpty)
        #expect(snap.room.walls.count == 4)
    }
}
