import Foundation

enum Vibe: String, CaseIterable, Identifiable {
    case cozy, edgy, romantic, sporty, preppy, classic

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// The closet piece that represents this vibe on its tile and on the sticker pile.
    var itemID: String {
        switch self {
        case .cozy: "hoodieBrown"
        case .edgy: "jacketBlack"
        case .romantic: "dressDots"
        case .sporty: "sneakersSamba"
        case .preppy: "skirtBrown"
        case .classic: "shortsTan"
        }
    }
}

/// What onboarding learns. It only changes wording (name, vibe, occasions), not which looks she gets.
struct OnboardingProfile {
    static let frequencies = ["Every single morning", "A few times a week", "Before anything special", "Honestly, rarely"]
    static let occasionOptions = ["Work", "Campus", "Errands", "Working from home", "Nights out", "Travel", "Gym", "Date night"]
    static let goals = ["Get ready in minutes", "Wear more of what I own", "Stop buying things I don't wear", "Find my style"]
    static let maxVibes = 3

    var frequency: String?
    var vibes: [Vibe] = []
    var occasions: [String] = []
    var goal: String?
    var name = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Sara's closet", or "your closet" before she's given a name.
    var closetTitle: String { trimmedName.isEmpty ? "your closet" : "\(trimmedName)'s closet" }

    /// Every answer leaves a sticker on the pile, in the order she gave them.
    var pileItemIDs: [String] {
        var ids: [String] = []
        if frequency != nil { ids.append("cardiganCherry") }
        ids += vibes.map(\.itemID)
        if !occasions.isEmpty { ids.append("bagDenim") }
        if goal != nil { ids.append("sneakers530") }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    var vibeSummary: String {
        vibes.isEmpty ? "your style" : vibes.map { $0.title.lowercased() }.joined(separator: ", ")
    }

    var occasionSummary: String {
        let picked = occasions.prefix(2).map { $0.lowercased() }
        return picked.isEmpty ? "your week" : picked.joined(separator: " & ")
    }
}
