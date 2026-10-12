#if DEBUG
import Foundation

/// DEBUG-only launch hooks for screenshots and UI review: `-uiDemo <screen>`
/// starts the app on a throw-away in-memory store seeded with a realistic
/// home and opens the requested screen in the requested state. Never touches
/// the user's data and is compiled out of Release builds.
enum DemoScreen: String, CaseIterable {
    case list, empty, about, scan, scanReview
    case home, homeRoom, home3D
    case room, room3D, edit, editFurniture, editWall, catalog, creator, versions
}

enum DemoLaunch {
    /// The requested screen, or nil for a normal launch.
    static let screen: DemoScreen? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiDemo"), i + 1 < args.count else { return nil }
        return DemoScreen(rawValue: args[i + 1])
    }()

    static var isActive: Bool { screen != nil }

    static func `is`(_ candidates: DemoScreen...) -> Bool {
        guard let screen else { return false }
        return candidates.contains(screen)
    }
}

/// A believable apartment: an L-shaped living room, bedroom, kitchen and
/// bathroom with doors, windows and furniture, plus a second, smaller home.
@MainActor
enum DemoContent {
    struct Seeded {
        var homeID: UUID?
        var roomID: UUID?
    }

    static func seed(_ store: RoomStore, library: FurnitureLibrary) -> Seeded {
        library.add(name: "Antika Konsol", category: .storage, shape: .rectangle,
                    width: 1.2, depth: 0.4, height: 0.85, photoID: nil)

        let summer = [
            room("Salon", .livingRoom, x0: 0, z0: 0, x1: 5, z1: 4, door: (3, 1.2), window: (0, 2.5)),
            room("Yatak Odası", .bedroom, x0: 5.2, z0: 0, x1: 8.7, z1: 3, door: (3, 1), window: (1, 1.5)),
        ]
        store.saveScannedHome(summer, homeName: "Yazlık")

        let rooms = [livingRoom(), bedroom(), kitchen(), bathroom()]
        guard let homeID = store.saveScannedHome(rooms, homeName: "Defne Residence"),
              let home = store.homeModel(for: homeID) else { return Seeded() }

        let furniture: [String: [PlacedFurniture]] = [
            "Salon": livingFurniture(), "Yatak Odası": bedroomFurniture(), "Mutfak": kitchenFurniture(),
        ]
        for placed in home.rooms {
            guard let items = furniture[placed.name] else { continue }
            store.saveEditedRoom(id: placed.id, editedDisplayRoom: placed.room, furniture: items,
                                 label: "Mobilya yerleşimi")
        }
        return Seeded(homeID: homeID, roomID: home.orderedRooms.first?.id)
    }

    /// Unsaved scan result for the review screen.
    static func reviewRooms() -> [RoomModel] {
        var rooms = [livingRoom(), bedroom(), kitchen(), bathroom()]
        rooms[3].name = "Oda"
        rooms[3].kind = .unidentified
        return rooms
    }

    // MARK: - Rooms

    private static func t(_ name: String) -> FurnitureTemplate {
        FurnitureCatalog.presets.first { $0.id == name }!
    }

    private static func livingRoom() -> RoomModel {
        let p = [Point2D(x: 0, z: 0), Point2D(x: 6, z: 0), Point2D(x: 6, z: 5),
                 Point2D(x: 2.5, z: 5), Point2D(x: 2.5, z: 2.5), Point2D(x: 0, z: 2.5)]
        let walls = loop(p)
        return RoomModel(name: "Salon", walls: walls,
                             openings: [
                                 Opening(type: .door, onWallId: walls[5].id, offset: 1.25, width: 0.9, height: 2.05),
                                 Opening(type: .window, onWallId: walls[0].id, offset: 1.5, width: 1.4,
                                         height: 1.3, sillHeight: 0.9),
                                 Opening(type: .window, onWallId: walls[1].id, offset: 2.5, width: 1.8,
                                         height: 1.4, sillHeight: 0.8),
                                 Opening(type: .opening, onWallId: walls[3].id, offset: 1.4, width: 1.0, height: 2.1),
                             ],
                             detectedObjects: [
                                 DetectedObject(category: "sofa", center: Point2D(x: 4.3, z: 4.4),
                                                width: 2.3, depth: 0.95, height: 0.85, rotation: .pi),
                                 DetectedObject(category: "table", center: Point2D(x: 4.3, z: 2.5),
                                                width: 1.0, depth: 0.6, height: 0.45, rotation: 0),
                             ],
                             floorOutline: p, source: .roomplan, kind: .livingRoom)
    }

    private static func bedroom() -> RoomModel {
        room("Yatak Odası", .bedroom, x0: 6.2, z0: 0, x1: 10.2, z1: 3.6, door: (2, 0.9), window: (1, 1.8))
    }

    private static func kitchen() -> RoomModel {
        room("Mutfak", .kitchen, x0: 6.2, z0: 3.8, x1: 10.2, z1: 6.6, door: (0, 1.1), window: (1, 1.4))
    }

    private static func bathroom() -> RoomModel {
        room("Banyo", .bathroom, x0: 0, z0: 2.7, x1: 2.3, z1: 5, door: (0, 1.15), window: (3, 1.1))
    }

    /// Rectangle with a door on wall `door.0` (at offset `door.1`) and a
    /// window on wall `window.0`. Walls: 0 top, 1 right, 2 bottom, 3 left.
    private static func room(_ name: String, _ kind: RoomKind, x0: Double, z0: Double,
                             x1: Double, z1: Double, door: (Int, Double), window: (Int, Double)) -> RoomModel {
        let p = [Point2D(x: x0, z: z0), Point2D(x: x1, z: z0), Point2D(x: x1, z: z1), Point2D(x: x0, z: z1)]
        let walls = loop(p)
        return RoomModel(name: name, walls: walls, openings: [
            Opening(type: .door, onWallId: walls[door.0].id, offset: door.1, width: 0.85, height: 2.05),
            Opening(type: .window, onWallId: walls[window.0].id, offset: window.1, width: 1.2,
                    height: 1.2, sillHeight: 0.9),
        ], floorOutline: p, source: .roomplan, kind: kind)
    }

    private static func loop(_ p: [Point2D]) -> [Wall] {
        p.indices.map { Wall(start: p[$0], end: p[($0 + 1) % p.count], thickness: 0.12, height: 2.6) }
    }

    // MARK: - Furniture

    private static func livingFurniture() -> [PlacedFurniture] {
        [
            t("rug").instantiate(at: Point2D(x: 4.3, z: 2.7), rotation: .pi / 2),
            t("sofa.l").instantiate(at: Point2D(x: 4.3, z: 3.94), rotation: .pi),
            t("table.coffee").instantiate(at: Point2D(x: 4.3, z: 2.45)),
            t("tv.unit").instantiate(at: Point2D(x: 4.3, z: 0.29)),
            t("armchair").instantiate(at: Point2D(x: 1.1, z: 1.4), rotation: .pi / 2),
            t("plant").instantiate(at: Point2D(x: 5.6, z: 0.5)),
        ]
    }

    private static func bedroomFurniture() -> [PlacedFurniture] {
        [
            t("bed.double").instantiate(at: Point2D(x: 8.3, z: 1.06)),
            t("nightstand").instantiate(at: Point2D(x: 7.2, z: 0.26)),
            t("nightstand").instantiate(at: Point2D(x: 9.4, z: 0.26)),
            t("wardrobe").instantiate(at: Point2D(x: 6.56, z: 2.3), rotation: -.pi / 2),
        ]
    }

    private static func kitchenFurniture() -> [PlacedFurniture] {
        [
            t("island").instantiate(at: Point2D(x: 8.5, z: 5.0)),
            t("fridge").instantiate(at: Point2D(x: 9.79, z: 4.25), rotation: .pi / 2),
            t("table.round").instantiate(at: Point2D(x: 6.95, z: 5.95)),
        ]
    }
}
#endif
