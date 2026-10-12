import Foundation

// MARK: - Category / shape

/// What a piece of furniture is — drives its icon, default color and the
/// catalog grouping. Stored as a String so new cases never break old payloads.
public enum FurnitureCategory: String, Codable, Sendable, CaseIterable {
    case sofa, armchair, bed, table, desk, chair, storage, rug, appliance, lighting, plant, decor, other

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FurnitureCategory(rawValue: raw) ?? .other
    }

    /// Turkish display name.
    public var displayName: String {
        switch self {
        case .sofa: return "Koltuk"
        case .armchair: return "Berjer"
        case .bed: return "Yatak"
        case .table: return "Masa"
        case .desk: return "Çalışma"
        case .chair: return "Sandalye"
        case .storage: return "Depolama"
        case .rug: return "Halı"
        case .appliance: return "Beyaz Eşya"
        case .lighting: return "Aydınlatma"
        case .plant: return "Bitki"
        case .decor: return "Dekor"
        case .other: return "Diğer"
        }
    }

    /// SF Symbol.
    public var icon: String {
        switch self {
        case .sofa: return "sofa"
        case .armchair: return "chair.lounge"
        case .bed: return "bed.double"
        case .table: return "table.furniture"
        case .desk: return "desktopcomputer"
        case .chair: return "chair"
        case .storage: return "cabinet"
        case .rug: return "square.dashed"
        case .appliance: return "refrigerator"
        case .lighting: return "lamp.floor"
        case .plant: return "leaf"
        case .decor: return "sparkles"
        case .other: return "shippingbox"
        }
    }

    /// Default material color (sRGB hex) — warm, muted, on-brand.
    public var defaultColorHex: Int {
        switch self {
        case .sofa: return 0xB98463
        case .armchair: return 0xC9956F
        case .bed: return 0x8E9FB0
        case .table: return 0xA67C52
        case .desk: return 0x9C7A55
        case .chair: return 0x8C6A4A
        case .storage: return 0xC2A878
        case .rug: return 0xB9A58C
        case .appliance: return 0xAEB4B8
        case .lighting: return 0xD8B45C
        case .plant: return 0x6E8F63
        case .decor: return 0xA48FB0
        case .other: return 0x9AA08F
        }
    }
}

/// Footprint outline of a piece. `.lShape` is a corner sofa: a back bar along
/// the full width plus a chaise down one side (see `FurnitureGeometry`).
public enum FurnitureShape: String, Codable, Sendable, CaseIterable {
    case rectangle, lShape, round

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FurnitureShape(rawValue: raw) ?? .rectangle
    }
}

// MARK: - Placed furniture

/// One piece of furniture placed in a room, stored in a version snapshot.
/// Local axes: +x = width, +z = depth (the FRONT faces local +z), yaw
/// `rotation` about +Y from world +X toward +Z — the RoomModel convention.
public struct PlacedFurniture: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var category: FurnitureCategory
    public var shape: FurnitureShape
    /// Footprint centre on the floor plane, meters.
    public var center: Point2D
    public var width: Double
    public var depth: Double
    public var height: Double
    /// Yaw in radians.
    public var rotation: Double
    /// Seat depth of an L sofa's back bar and chaise, meters.
    public var armDepth: Double?
    /// L sofa: chaise on the left instead of the right.
    public var mirrored: Bool
    /// sRGB hex; nil = the category default.
    public var colorHex: Int?
    /// File name of a user photo in the furniture photo store.
    public var photoID: String?
    /// Catalog template this piece was created from.
    public var templateID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        category: FurnitureCategory = .other,
        shape: FurnitureShape = .rectangle,
        center: Point2D,
        width: Double,
        depth: Double,
        height: Double = 0.8,
        rotation: Double = 0,
        armDepth: Double? = nil,
        mirrored: Bool = false,
        colorHex: Int? = nil,
        photoID: String? = nil,
        templateID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.shape = shape
        self.center = center
        self.width = width
        self.depth = depth
        self.height = height
        self.rotation = rotation
        self.armDepth = armDepth
        self.mirrored = mirrored
        self.colorHex = colorHex
        self.photoID = photoID
        self.templateID = templateID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, shape, center, width, depth, height, rotation
        case armDepth, mirrored, colorHex, photoID, templateID
    }

    /// Forward/backward compatible: every field but the geometry is optional
    /// on the wire, so older or newer payloads always decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try c.decodeIfPresent(FurnitureCategory.self, forKey: .category) ?? .other
        shape = try c.decodeIfPresent(FurnitureShape.self, forKey: .shape) ?? .rectangle
        center = try c.decode(Point2D.self, forKey: .center)
        width = try c.decode(Double.self, forKey: .width)
        depth = try c.decode(Double.self, forKey: .depth)
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0.8
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        armDepth = try c.decodeIfPresent(Double.self, forKey: .armDepth)
        mirrored = try c.decodeIfPresent(Bool.self, forKey: .mirrored) ?? false
        colorHex = try c.decodeIfPresent(Int.self, forKey: .colorHex)
        photoID = try c.decodeIfPresent(String.self, forKey: .photoID)
        templateID = try c.decodeIfPresent(String.self, forKey: .templateID)
    }

    public var resolvedColorHex: Int { colorHex ?? category.defaultColorHex }

    /// "260 × 200 cm"
    public var sizeLabel: String {
        "\(Int((width * 100).rounded())) × \(Int((depth * 100).rounded())) cm"
    }
}

extension PlacedFurniture {
    /// Import an object RoomPlan detected during the scan as editable furniture.
    init(detected object: DetectedObject) {
        let category = Self.category(forDetected: object.category)
        self.init(
            name: Self.name(forDetected: object.category, category: category),
            category: category,
            shape: .rectangle,
            center: object.center,
            width: max(object.width, 0.1),
            depth: max(object.depth, 0.1),
            height: max(object.height, 0.05),
            rotation: object.rotation,
            templateID: Self.detectedTemplateID(object)
        )
    }

    /// Marks a piece as imported from a specific scanned object, so the same
    /// object is never imported twice.
    static func detectedTemplateID(_ object: DetectedObject) -> String {
        "detected.\(object.id.uuidString)"
    }

    static func category(forDetected raw: String) -> FurnitureCategory {
        switch raw.lowercased() {
        case "sofa": return .sofa
        case "bed": return .bed
        case "table": return .table
        case "chair": return .chair
        case "storage", "fireplace": return .storage
        case "refrigerator", "stove", "oven", "dishwasher", "washerdryer", "sink", "toilet", "bathtub":
            return .appliance
        case "television": return .decor
        case "stairs": return .other
        default: return .other
        }
    }

    static func name(forDetected raw: String, category: FurnitureCategory) -> String {
        switch raw.lowercased() {
        case "sofa": return "Koltuk"
        case "bed": return "Yatak"
        case "table": return "Masa"
        case "chair": return "Sandalye"
        case "storage": return "Dolap"
        case "refrigerator": return "Buzdolabı"
        case "stove": return "Ocak"
        case "oven": return "Fırın"
        case "dishwasher": return "Bulaşık Makinesi"
        case "washerdryer": return "Çamaşır Makinesi"
        case "sink": return "Lavabo"
        case "toilet": return "Klozet"
        case "bathtub": return "Küvet"
        case "television": return "Televizyon"
        case "fireplace": return "Şömine"
        case "stairs": return "Merdiven"
        default: return category.displayName
        }
    }
}

// MARK: - Catalog

/// A catalog entry: a sized, named piece ready to drop into a room.
public struct FurnitureTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: FurnitureCategory
    public var shape: FurnitureShape
    public var width: Double
    public var depth: Double
    public var height: Double
    public var armDepth: Double?
    public var colorHex: Int?
    public var photoID: String?
    /// True for pieces the user created (editable, deletable).
    public var isCustom: Bool

    public init(id: String, name: String, category: FurnitureCategory,
                shape: FurnitureShape = .rectangle, width: Double, depth: Double,
                height: Double, armDepth: Double? = nil, colorHex: Int? = nil,
                photoID: String? = nil, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.shape = shape
        self.width = width
        self.depth = depth
        self.height = height
        self.armDepth = armDepth
        self.colorHex = colorHex
        self.photoID = photoID
        self.isCustom = isCustom
    }

    public func instantiate(at center: Point2D, rotation: Double = 0) -> PlacedFurniture {
        PlacedFurniture(name: name, category: category, shape: shape, center: center,
                        width: width, depth: depth, height: height, rotation: rotation,
                        armDepth: armDepth, colorHex: colorHex, photoID: photoID,
                        templateID: id)
    }

    /// "260 × 200 cm"
    public var sizeLabel: String {
        "\(Int((width * 100).rounded())) × \(Int((depth * 100).rounded())) cm"
    }
}

/// Built-in, real-world-sized pieces (cm in the comments).
public enum FurnitureCatalog {
    public static let presets: [FurnitureTemplate] = [
        // Oturma
        .init(id: "sofa.l", name: "L Koltuk", category: .sofa, shape: .lShape,
              width: 2.60, depth: 2.00, height: 0.85, armDepth: 0.95),          // 260×200
        .init(id: "sofa.3", name: "Üçlü Koltuk", category: .sofa,
              width: 2.20, depth: 0.95, height: 0.85),                          // 220×95
        .init(id: "sofa.2", name: "İkili Koltuk", category: .sofa,
              width: 1.60, depth: 0.90, height: 0.85),                          // 160×90
        .init(id: "armchair", name: "Berjer", category: .armchair,
              width: 0.80, depth: 0.85, height: 0.95),                          // 80×85
        .init(id: "pouf", name: "Puf", category: .armchair, shape: .round,
              width: 0.50, depth: 0.50, height: 0.45),                          // ⌀50
        // Yatak odası
        .init(id: "bed.double", name: "Çift Kişilik Yatak", category: .bed,
              width: 1.60, depth: 2.00, height: 0.50),                          // 160×200
        .init(id: "bed.king", name: "King Yatak", category: .bed,
              width: 1.80, depth: 2.00, height: 0.50),                          // 180×200
        .init(id: "bed.single", name: "Tek Kişilik Yatak", category: .bed,
              width: 0.90, depth: 1.90, height: 0.50),                          // 90×190
        .init(id: "nightstand", name: "Komodin", category: .storage,
              width: 0.50, depth: 0.40, height: 0.55),                          // 50×40
        .init(id: "wardrobe", name: "Gardırop", category: .storage,
              width: 2.00, depth: 0.60, height: 2.20),                          // 200×60
        .init(id: "dresser", name: "Şifonyer", category: .storage,
              width: 1.00, depth: 0.50, height: 0.90),                          // 100×50
        // Yemek & çalışma
        .init(id: "table.dining", name: "Yemek Masası", category: .table,
              width: 1.60, depth: 0.90, height: 0.75),                          // 160×90
        .init(id: "table.round", name: "Yuvarlak Masa", category: .table, shape: .round,
              width: 1.10, depth: 1.10, height: 0.75),                          // ⌀110
        .init(id: "table.coffee", name: "Orta Sehpa", category: .table,
              width: 1.00, depth: 0.60, height: 0.45),                          // 100×60
        .init(id: "desk", name: "Çalışma Masası", category: .desk,
              width: 1.20, depth: 0.60, height: 0.75),                          // 120×60
        .init(id: "chair", name: "Sandalye", category: .chair,
              width: 0.45, depth: 0.50, height: 0.85),                          // 45×50
        // Depolama & dekor
        .init(id: "tv.unit", name: "TV Ünitesi", category: .storage,
              width: 1.80, depth: 0.45, height: 0.50),                          // 180×45
        .init(id: "bookcase", name: "Kitaplık", category: .storage,
              width: 0.80, depth: 0.35, height: 2.00),                          // 80×35
        .init(id: "rug", name: "Halı", category: .rug,
              width: 2.00, depth: 3.00, height: 0.01),                          // 200×300
        .init(id: "plant", name: "Saksı Bitki", category: .plant, shape: .round,
              width: 0.45, depth: 0.45, height: 1.20),                          // ⌀45
        .init(id: "lamp.floor", name: "Lambader", category: .lighting, shape: .round,
              width: 0.40, depth: 0.40, height: 1.60),                          // ⌀40
        // Mutfak & banyo
        .init(id: "fridge", name: "Buzdolabı", category: .appliance,
              width: 0.70, depth: 0.70, height: 1.85),                          // 70×70
        .init(id: "washer", name: "Çamaşır Makinesi", category: .appliance,
              width: 0.60, depth: 0.60, height: 0.85),                          // 60×60
        .init(id: "dishwasher", name: "Bulaşık Makinesi", category: .appliance,
              width: 0.60, depth: 0.60, height: 0.85),                          // 60×60
        .init(id: "island", name: "Ada Tezgâh", category: .table,
              width: 1.80, depth: 0.90, height: 0.90),                          // 180×90
    ]

    /// Presets grouped for the catalog sheet, in a stable, room-by-room order.
    public static let sections: [(title: String, items: [FurnitureTemplate])] = {
        let order: [(String, Set<FurnitureCategory>)] = [
            ("Oturma", [.sofa, .armchair]),
            ("Yatak Odası", [.bed]),
            ("Masa & Sandalye", [.table, .desk, .chair]),
            ("Depolama", [.storage]),
            ("Mutfak & Banyo", [.appliance]),
            ("Dekor", [.rug, .plant, .lighting, .decor, .other]),
        ]
        return order.map { title, cats in (title, presets.filter { cats.contains($0.category) }) }
    }()
}

// MARK: - Geometry

/// Pure footprint geometry for placed furniture (world XZ meters).
public enum FurnitureGeometry {
    /// Outline in LOCAL coordinates (x ∈ ±width/2, z ∈ ±depth/2; back at −z).
    public static func localOutline(_ f: PlacedFurniture) -> [Point2D] {
        let hw = f.width / 2, hd = f.depth / 2
        switch f.shape {
        case .rectangle:
            return [Point2D(x: -hw, z: -hd), Point2D(x: hw, z: -hd),
                    Point2D(x: hw, z: hd), Point2D(x: -hw, z: hd)]
        case .round:
            let n = 28
            return (0..<n).map { i in
                let a = Double(i) / Double(n) * 2 * .pi
                return Point2D(x: hw * cos(a), z: hd * sin(a))
            }
        case .lShape:
            // Back bar along −z, chaise down the +x side (−x when mirrored).
            let arm = min(max(f.armDepth ?? 0.9, 0.3), min(f.width, f.depth))
            let s: Double = f.mirrored ? -1 : 1
            let pts = [
                Point2D(x: -hw, z: -hd), Point2D(x: hw, z: -hd),
                Point2D(x: hw, z: hd), Point2D(x: hw - arm, z: hd),
                Point2D(x: hw - arm, z: -hd + arm), Point2D(x: -hw, z: -hd + arm),
            ]
            let out = pts.map { Point2D(x: $0.x * s, z: $0.z) }
            return f.mirrored ? out.reversed() : out
        }
    }

    /// Local → world.
    public static func toWorld(_ p: Point2D, of f: PlacedFurniture) -> Point2D {
        let c = cos(f.rotation), s = sin(f.rotation)
        return Point2D(x: f.center.x + p.x * c - p.z * s,
                       z: f.center.z + p.x * s + p.z * c)
    }

    /// World → local.
    public static func toLocal(_ p: Point2D, of f: PlacedFurniture) -> Point2D {
        let d = p - f.center
        let c = cos(f.rotation), s = sin(f.rotation)
        return Point2D(x: d.x * c + d.z * s, z: -d.x * s + d.z * c)
    }

    /// Footprint polygon in world coordinates.
    public static func footprint(_ f: PlacedFurniture) -> [Point2D] {
        localOutline(f).map { toWorld($0, of: f) }
    }

    /// The rectangular boxes (local) that make up the piece — one for most
    /// shapes, two for an L sofa. Used by the 3D builder.
    public static func localBoxes(_ f: PlacedFurniture) -> [(center: Point2D, width: Double, depth: Double)] {
        guard f.shape == .lShape else { return [(Point2D(x: 0, z: 0), f.width, f.depth)] }
        let hw = f.width / 2, hd = f.depth / 2
        let arm = min(max(f.armDepth ?? 0.9, 0.3), min(f.width, f.depth))
        let s: Double = f.mirrored ? -1 : 1
        let back = (center: Point2D(x: 0, z: -hd + arm / 2), width: f.width, depth: arm)
        let chaise = (center: Point2D(x: s * (hw - arm / 2), z: arm / 2),
                      width: arm, depth: f.depth - arm)
        return [back, chaise]
    }

    /// Hit test on the floor plane, with `slop` meters of forgiveness.
    public static func contains(_ f: PlacedFurniture, _ p: Point2D, slop: Double = 0) -> Bool {
        let poly = footprint(f)
        if PlanGeometry.contains(poly, p) { return true }
        guard slop > 0 else { return false }
        for i in poly.indices where FloorGeometry.distance(
            from: p, toSegment: poly[i], poly[(i + 1) % poly.count]) <= slop {
            return true
        }
        return false
    }

    /// Normalize an angle into (−π, π].
    public static func normalized(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }

    /// Slide an axis-aligned piece flush against nearby axis-aligned walls when
    /// its footprint edge comes within `tolerance` of a wall face. Pieces at an
    /// arbitrary angle are returned unchanged.
    public static func snappedToWalls(_ f: PlacedFurniture, walls: [Wall],
                                      tolerance: Double) -> PlacedFurniture {
        guard tolerance > 0 else { return f }
        let quarter = (f.rotation / (.pi / 2)).rounded()
        guard abs(f.rotation - quarter * .pi / 2) < 0.02 else { return f }
        guard let box = PlanGeometry.bounds(of: footprint(f)) else { return f }

        var bestX: Double?, bestZ: Double?
        func consider(_ delta: Double, _ best: inout Double?) {
            if abs(delta) <= tolerance, best.map({ abs(delta) < abs($0) }) ?? true { best = delta }
        }
        for wall in walls {
            let d = wall.end - wall.start
            let len = d.length
            guard len > 0.2 else { continue }
            let half = wall.thickness / 2
            if abs(d.x) / len < 0.02 {
                // Vertical wall at x = wx; must overlap the piece in z.
                let wx = (wall.start.x + wall.end.x) / 2
                let z0 = min(wall.start.z, wall.end.z), z1 = max(wall.start.z, wall.end.z)
                guard z1 > Double(box.minY) + 0.05, z0 < Double(box.maxY) - 0.05 else { continue }
                consider(wx + half - Double(box.minX), &bestX)   // piece right of the wall
                consider(wx - half - Double(box.maxX), &bestX)   // piece left of the wall
            } else if abs(d.z) / len < 0.02 {
                let wz = (wall.start.z + wall.end.z) / 2
                let x0 = min(wall.start.x, wall.end.x), x1 = max(wall.start.x, wall.end.x)
                guard x1 > Double(box.minX) + 0.05, x0 < Double(box.maxX) - 0.05 else { continue }
                consider(wz + half - Double(box.minY), &bestZ)
                consider(wz - half - Double(box.maxY), &bestZ)
            }
        }
        var out = f
        out.center = Point2D(x: f.center.x + (bestX ?? 0), z: f.center.z + (bestZ ?? 0))
        return out
    }
}
