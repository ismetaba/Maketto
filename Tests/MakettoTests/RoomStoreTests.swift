#if canImport(SwiftData)
import Foundation
import Testing
@testable import Maketto

@MainActor
struct RoomStoreTests {
    /// A two-room home whose walls are skewed, so the display (straightened)
    /// frame differs from the stored raw frame.
    private func makeStore() throws -> (RoomStore, UUID) {
        let store = RoomStore.inMemory()
        let skew = Pose2D(rotation: 0.15, translation: Point2D(x: 1, z: 2))
        var a = HomeGeometry.transform(.mockLShaped, by: skew)
        a.name = "Salon"
        var b = HomeGeometry.transform(
            HomeGeometry.transform(.mock, by: Pose2D(translation: Point2D(x: 5.2, z: 0))), by: skew)
        b.name = "Yatak Odası"
        let id = try #require(store.saveScannedHome([a, b], homeName: "  Daire  "))
        return (store, id)
    }

    @Test func savesAScannedHome() throws {
        let (store, id) = try makeStore()
        #expect(store.homes.count == 1)
        #expect(store.homes[0].name == "Daire")
        #expect(store.homes[0].roomCount == 2)
        let home = try #require(store.homeModel(for: id))
        #expect(home.rooms.map(\.name) == ["Salon", "Yatak Odası"])
        // The map, chips, cards and navigation all use the same (Room) id.
        #expect(home.roomsInHomeFrame.map(\.id) == home.orderedRooms.map(\.id))
        for placed in home.rooms {
            #expect(store.document(for: placed.id)?.room.id == placed.id)
        }
        // The display frame is straightened to the axes.
        for wall in home.rooms[0].room.walls { #expect(PlanGeometry.offAxis(wall) < 1e-6) }
    }

    @Test func editingCreatesAVersionAndRestoreGoesBack() throws {
        let (store, homeID) = try makeStore()
        let roomID = try #require(store.homeModel(for: homeID)?.rooms.first?.id)
        let original = try #require(store.document(for: roomID))
        #expect(original.versionNumber == 1)
        #expect(original.versionLabel == RoomStore.firstVersionLabel)

        // Edit in the display frame: stretch a wall and add furniture.
        let editor = EditableRoom(original.room, furniture: original.furniture)
        let wall = try #require(editor.edges.first?.id)
        let before = try #require(editor.wall(wall)).length
        #expect(editor.setLength(of: wall, to: before + 0.5))
        let sofa = FurnitureCatalog.presets[1].instantiate(at: Point2D(x: 2, z: 1), rotation: 0.3)
        editor.addFurniture(sofa)
        let revision = store.revision
        #expect(store.saveEditedRoom(id: roomID, editedDisplayRoom: editor.flattened(),
                                     furniture: editor.furniture))
        #expect(store.revision != revision)

        let edited = try #require(store.document(for: roomID))
        #expect(edited.versionNumber == 2)
        #expect(edited.versionCount == 2)
        #expect(edited.versionLabel == RoomStore.editVersionLabel)
        // The round trip through the raw frame is rigid: lengths, and the
        // sofa's position relative to the wall it was placed by, survive.
        // (The display frame itself may re-centre when the home's bounds change.)
        let storedWall = try #require(edited.room.wall(wall))
        #expect(abs(storedWall.length - (before + 0.5)) < 1e-9)
        let storedSofa = try #require(edited.furniture.first)
        let editedWall = try #require(editor.wall(wall))
        let relBefore = sofa.center - editedWall.start
        let relAfter = storedSofa.center - storedWall.start
        #expect(relBefore.distance(to: relAfter) < 1e-9)
        #expect(abs(storedSofa.rotation - sofa.rotation) < 1e-9)

        // v1 comes back exactly as it was.
        let v1 = try #require(store.versions(for: roomID).last)
        #expect(v1.number == 1)
        #expect(store.restoreVersion(roomID: roomID, versionID: v1.id))
        let restored = try #require(store.document(for: roomID))
        #expect(restored.versionNumber == 1)
        #expect(restored.room.walls == original.room.walls)
        #expect(restored.furniture.isEmpty)
        // Nothing was lost.
        #expect(store.versions(for: roomID).count == 2)
    }

    @Test func versionManagementGuards() throws {
        let (store, homeID) = try makeStore()
        let roomID = try #require(store.homeModel(for: homeID)?.rooms.first?.id)
        let current = try #require(store.document(for: roomID)?.versionID)
        #expect(!store.deleteVersion(roomID: roomID, versionID: current))     // the only / current one
        #expect(!store.renameVersion(roomID: roomID, versionID: current, to: "   "))
        #expect(store.renameVersion(roomID: roomID, versionID: current, to: "İlk tarama"))
        #expect(store.document(for: roomID)?.versionLabel == "İlk tarama")

        let doc = try #require(store.document(for: roomID))
        #expect(store.saveEditedRoom(id: roomID, editedDisplayRoom: doc.room, furniture: []))
        #expect(store.deleteVersion(roomID: roomID, versionID: current))       // no longer current
        #expect(store.versions(for: roomID).count == 1)
    }

    @Test func renameAndDelete() throws {
        let (store, homeID) = try makeStore()
        let rooms = try #require(store.homeModel(for: homeID)?.rooms)
        #expect(store.renameRoom(id: rooms[0].id, to: "  Oturma  "))
        #expect(store.homeModel(for: homeID)?.rooms[0].name == "Oturma")
        #expect(!store.renameRoom(id: rooms[0].id, to: ""))
        #expect(store.renameHome(id: homeID, to: "Yazlık"))
        #expect(store.homes.first?.name == "Yazlık")

        #expect(store.deleteRoom(id: rooms[1].id))
        #expect(store.homeModel(for: homeID)?.rooms.count == 1)
        #expect(store.document(for: rooms[1].id) == nil)
        #expect(!store.deleteRoom(id: rooms[0].id))      // the last room stays
        #expect(store.document(for: rooms[0].id)?.canDeleteRoom == false)

        #expect(store.deleteHome(id: homeID))
        #expect(store.homes.isEmpty)
        #expect(store.homeModel(for: homeID) == nil)
    }

    @Test func legacyLabelsReadInTurkish() {
        #expect(RoomStore.displayLabel("Version 3") == "Sürüm 3")
        #expect(RoomStore.displayLabel("Version x") == "Version x")
        #expect(RoomStore.displayLabel("Mutfak yenileme") == "Mutfak yenileme")
    }

    @Test func emptyScanIsRejected() {
        let store = RoomStore.inMemory()
        #expect(store.saveScannedHome([], homeName: "x") == nil)
        #expect(store.homes.isEmpty)
    }
}
#endif
