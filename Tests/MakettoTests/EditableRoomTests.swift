import Foundation
import Testing
#if canImport(MakettoCore)
@testable import MakettoCore
#else
@testable import Maketto
#endif

@MainActor
struct EditableRoomTests {
    private func cornerID(_ ed: EditableRoom, _ x: Double, _ z: Double) throws -> UUID {
        try #require(ed.corner(near: Point2D(x: x, z: z), within: 0.01))
    }

    @Test func entersClean() {
        let ed = EditableRoom(.mockLShaped)
        #expect(!ed.isDirty)
        #expect(!ed.canUndo)
        #expect(ed.corners.count == 6)
        #expect(ed.edges.count == 6)
        #expect(ed.flattened().walls.count == 6)
    }

    @Test func droppingACornerOnItsNeighbourWeldsThem() throws {
        let ed = EditableRoom(.mock)
        let c1 = try cornerID(ed, 4, 0)
        ed.beginCornerDrag()
        ed.dragCorner(c1, to: Point2D(x: 4.01, z: 2.98))
        ed.endCornerDrag(c1)
        #expect(ed.corners.count == 3)
        #expect(ed.edges.count == 3)          // the collapsed 3 m wall is gone
        #expect(ed.canUndo)
        ed.undo()
        #expect(ed.corners.count == 4)
        #expect(!ed.isDirty)
    }

    @Test func noOpDragLeavesNoUndoStep() throws {
        let ed = EditableRoom(.mock)
        let c = try cornerID(ed, 0, 0)
        ed.beginCornerDrag()
        ed.dragCorner(c, to: Point2D(x: 0, z: 0))
        ed.endCornerDrag(c)
        #expect(!ed.canUndo)
        #expect(!ed.isDirty)
    }

    @Test func dragSnapsToNeighbourAxes() throws {
        let ed = EditableRoom(.mock)
        let c = try cornerID(ed, 4, 3)
        ed.beginCornerDrag()
        ed.dragCorner(c, to: Point2D(x: 4.03, z: 3.6), snapTolerance: 0.05)
        #expect(ed.cornerPosition(c)?.x == 4)        // aligned with (4, 0)
        #expect(ed.snapGuides.x == 4)
        ed.endCornerDrag(c)
        #expect(ed.snapGuides == .none)
    }

    @Test func openingsKeepTheirWorldPositionWhenTheWallStretches() throws {
        let room = RoomModel.mockLShaped
        let ed = EditableRoom(room)
        let door = try #require(room.openings.first { $0.type == .door })
        let wallAB = try #require(room.wall(door.onWallId))
        let doorWorld = wallAB.point(atOffset: door.offset)       // (2.5, 0)

        // Move the wall's START corner (0,0) further out along the wall.
        let a = try cornerID(ed, 0, 0)
        ed.beginCornerDrag()
        ed.dragCorner(a, to: Point2D(x: -1, z: 0))
        ed.endCornerDrag(a)

        let flat = ed.flattened()
        let movedDoor = try #require(flat.openings.first { $0.id == door.id })
        let movedWall = try #require(flat.wall(door.onWallId))
        #expect(movedWall.point(atOffset: movedDoor.offset).distance(to: doorWorld) < 1e-9)
    }

    @Test func deletingAWallDropsItsOpeningsAndUndoRestoresThem() throws {
        let room = RoomModel.mockLShaped
        let ed = EditableRoom(room)
        let door = try #require(room.openings.first { $0.type == .door })
        ed.deleteWall(door.onWallId)
        #expect(!ed.openings.contains { $0.id == door.id })
        #expect(ed.flattened().floorOutline == nil)     // room is open now
        ed.undo()
        #expect(ed.openings.contains { $0.id == door.id })
        #expect(!ed.isDirty)
        ed.redo()
        #expect(!ed.openings.contains { $0.id == door.id })
    }

    @Test func settingALengthPushesTheSquareWall() throws {
        let ed = EditableRoom(.mock)
        let bottom = try #require(ed.wall(near: Point2D(x: 2, z: 0), within: 0.01))
        #expect(ed.setLength(of: bottom, to: 5))
        let flat = ed.flattened()
        let lengths = flat.walls.map(\.length).sorted()
        #expect(approx(lengths[0], 3) && approx(lengths[1], 3))
        #expect(approx(lengths[2], 5) && approx(lengths[3], 5))
        #expect(approx(PlanGeometry.area(of: flat), 15))
        #expect(!ed.setLength(of: bottom, to: 0.01))     // rejected
    }

    @Test func drawingAWallClosesAnOpenRoom() throws {
        let ed = EditableRoom(.mock)
        let left = try #require(ed.wall(near: Point2D(x: 0, z: 1.5), within: 0.01))
        ed.deleteWall(left)
        #expect(ed.flattened().floorOutline == nil)
        let id = ed.addWall(from: Point2D(x: 0.02, z: 3.01), to: Point2D(x: -0.01, z: 0.02), snapRadius: 0.1)
        #expect(id != nil)
        #expect(ed.corners.count == 4)
        #expect(ed.flattened().floorOutline?.count == 4)
    }

    @Test func drawingFromAWallSplitsIt() throws {
        let ed = EditableRoom(.mock)
        let before = ed.edges.count
        let id = ed.addWall(from: Point2D(x: 2, z: 0.01), to: Point2D(x: 2, z: 1.5), snapRadius: 0.1)
        #expect(id != nil)
        #expect(ed.edges.count == before + 2)      // split half + the new wall
        #expect(ed.corners.count == 6)
        ed.undo()
        #expect(ed.edges.count == before)
        #expect(!ed.isDirty)
    }

    @Test func splittingKeepsOpeningsOnTheirHalf() throws {
        let room = RoomModel.mockLShaped
        let ed = EditableRoom(room)
        let door = try #require(room.openings.first { $0.type == .door })   // AB, centre x = 2.5
        let wall = try #require(room.wall(door.onWallId))
        let world = wall.point(atOffset: door.offset)
        _ = ed.addWall(from: Point2D(x: 1, z: 0), to: Point2D(x: 1, z: 1.5), snapRadius: 0.05)
        let flat = ed.flattened()
        let moved = try #require(flat.openings.first { $0.id == door.id })
        let host = try #require(flat.wall(moved.onWallId))
        #expect(host.point(atOffset: moved.offset).distance(to: world) < 1e-9)
    }

    @Test func duplicateWallsAreRejected() throws {
        let ed = EditableRoom(.mock)
        #expect(ed.addWall(from: Point2D(x: 0, z: 0), to: Point2D(x: 4, z: 0), snapRadius: 0.05) == nil)
        #expect(!ed.canUndo)
    }

    @Test func furnitureLifecycle() throws {
        let ed = EditableRoom(.mock)
        let sofa = FurnitureCatalog.presets.first { $0.id == "sofa.3" }!
            .instantiate(at: Point2D(x: 2, z: 1.5))
        ed.addFurniture(sofa)
        #expect(ed.isDirty)
        #expect(ed.furnitureID(at: Point2D(x: 2, z: 1.5)) == sofa.id)

        // Drag next to the top wall (z = 0): snaps flush against its face.
        ed.beginFurnitureDrag()
        ed.dragFurniture(sofa.id, to: Point2D(x: 2, z: 0.55), snapTolerance: 0.1)
        ed.endFurnitureDrag()
        let placed = try #require(ed.furnitureItem(sofa.id))
        #expect(approx(placed.center.z, 0.05 + sofa.depth / 2))

        ed.rotateFurniture(sofa.id, by: .pi / 2)
        #expect(approx(ed.furnitureItem(sofa.id)!.rotation, .pi / 2))

        let copy = try #require(ed.duplicateFurniture(sofa.id))
        #expect(ed.furniture.count == 2)
        ed.deleteFurniture(copy)
        #expect(ed.furniture.count == 1)

        ed.updateFurniture(sofa.id) { $0.width = -3 }   // clamped, never negative
        #expect(ed.furnitureItem(sofa.id)!.width >= 0.05)

        while ed.canUndo { ed.undo() }
        #expect(ed.furniture.isEmpty)
        #expect(!ed.isDirty)
    }
}
