import SwiftUI

/// One room's map tint: a soft floor fill plus a stronger accent for outlines,
/// dots and labels.
struct RoomTint: Equatable {
    let fill: Color
    let accent: Color
}

/// Distinct-but-harmonious room colors for the home map — the robot-vacuum-app
/// idea (every room has its own tint so the map reads at a glance) tuned to the
/// warm Maketto palette. Tints are assigned by the room's stable position in
/// the home (sort order), so a room keeps its color across screens.
enum RoomPalette {
    static func tint(_ index: Int) -> RoomTint {
        let n = all.count
        return all[((index % n) + n) % n]
    }

    static let all: [RoomTint] = [
        RoomTint( // wheat / brass
            fill: Color(light: Color(hex: 0xF2E9D2), dark: Color(hex: 0xC8A862, alpha: 0.17)),
            accent: Color(light: Color(hex: 0x9C7F3E), dark: Color(hex: 0xD9C088))
        ),
        RoomTint( // sage / evergreen
            fill: Color(light: Color(hex: 0xE1EAD9), dark: Color(hex: 0x87C29B, alpha: 0.15)),
            accent: Color(light: Color(hex: 0x5E7E61), dark: Color(hex: 0xA8CDAF))
        ),
        RoomTint( // blush / clay
            fill: Color(light: Color(hex: 0xF4E1D2), dark: Color(hex: 0xE0906B, alpha: 0.15)),
            accent: Color(light: Color(hex: 0xB5734E), dark: Color(hex: 0xE0B18F))
        ),
        RoomTint( // mist / teal
            fill: Color(light: Color(hex: 0xDFEAEA), dark: Color(hex: 0x7FB5BD, alpha: 0.15)),
            accent: Color(light: Color(hex: 0x54777D), dark: Color(hex: 0x9FC6CC))
        ),
        RoomTint( // heather / plum
            fill: Color(light: Color(hex: 0xEAE2EC), dark: Color(hex: 0xB99BC5, alpha: 0.15)),
            accent: Color(light: Color(hex: 0x7A6486), dark: Color(hex: 0xC5AED1))
        ),
        RoomTint( // olive / moss
            fill: Color(light: Color(hex: 0xEBEBD3), dark: Color(hex: 0xC2C273, alpha: 0.14)),
            accent: Color(light: Color(hex: 0x77753D), dark: Color(hex: 0xCFCD8D))
        ),
    ]
}

// MARK: - RoomKind presentation

extension RoomKind {
    /// Human-facing Turkish name (shared with default room naming).
    var displayName: String { RoomNaming.defaultName(for: self) }

    /// SF Symbol used in kind pickers and room cards.
    var icon: String {
        switch self {
        case .livingRoom: return "sofa"
        case .bedroom: return "bed.double"
        case .bathroom: return "shower"
        case .kitchen: return "fork.knife"
        case .diningRoom: return "table.furniture"
        case .hallway: return "door.left.hand.open"
        case .balcony: return "sun.max"
        case .unidentified: return "square.split.bottomrightquarter"
        }
    }
}
