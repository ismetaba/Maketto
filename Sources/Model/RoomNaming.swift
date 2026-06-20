import Foundation

/// Default Turkish room names from RoomPlan's room type (primary) with a light
/// object-inference fallback, numbering duplicates by descending area. Pure.
public enum RoomNaming {
    public static func defaultName(for kind: RoomKind) -> String {
        switch kind {
        case .livingRoom:  return "Salon"
        case .bedroom:     return "Yatak Odası"
        case .bathroom:    return "Banyo"
        case .kitchen:     return "Mutfak"
        case .diningRoom:  return "Yemek Odası"
        case .hallway:     return "Hol"
        case .balcony:     return "Balkon"
        case .unidentified: return "Oda"
        }
    }

    /// SDK kind if known, else infer from detected objects.
    public static func effectiveKind(_ room: RoomModel) -> RoomKind {
        if let k = room.kind, k != .unidentified { return k }
        return inferKind(from: room.detectedObjects)
    }

    static func inferKind(from objects: [DetectedObject]) -> RoomKind {
        let cats = Set(objects.map { $0.category.lowercased() })
        if cats.contains("toilet") || cats.contains("bathtub") { return .bathroom }
        if cats.contains("stove") || cats.contains("oven") || cats.contains("dishwasher")
            || cats.contains("refrigerator") || cats.contains("sink") { return .kitchen }
        if cats.contains("bed") { return .bedroom }
        if cats.contains("sofa") || cats.contains("television") { return .livingRoom }
        return .unidentified
    }

    /// Assign default names to a set of rooms. Returns NEW RoomModels with `.name`
    /// and `.kind` set; duplicate kinds are numbered (largest area = 1).
    public static func assignNames(_ rooms: [RoomModel]) -> [RoomModel] {
        let resolved: [(room: RoomModel, kind: RoomKind, area: Double)] = rooms.map {
            ($0, effectiveKind($0), PlanGeometry.area(of: $0))
        }
        var groups: [String: [Int]] = [:]
        for (i, item) in resolved.enumerated() {
            groups[defaultName(for: item.kind), default: []].append(i)
        }
        var names = [String](repeating: "", count: rooms.count)
        for (base, idxs) in groups {
            if idxs.count == 1 {
                names[idxs[0]] = base
            } else {
                let ordered = idxs.sorted {
                    let a = resolved[$0].area, b = resolved[$1].area
                    if a != b { return a > b }
                    return resolved[$0].room.id.uuidString > resolved[$1].room.id.uuidString
                }
                for (n, idx) in ordered.enumerated() {
                    names[idx] = "\(base) \(n + 1)"
                }
            }
        }
        return resolved.enumerated().map { i, item in
            var r = item.room
            r.name = names[i]
            r.kind = item.kind
            return r
        }
    }
}
