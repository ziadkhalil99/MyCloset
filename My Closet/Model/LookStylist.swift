import Foundation

/// Builds flat-lay looks from the pieces someone owns. An outfit is a top and a bottom, or a
/// dress, plus shoes, a bag and a jacket when they have them. Each category has a fixed spot
/// on the card, and pieces are sized to fit their spot at their own aspect ratio.
enum LookStylist {
    static let canvasAspect = 0.78
    static let maxLooks = 6

    private static let floors = ["EADFD0", "DCE2D3", "F0DEDA", "DCE4EC", "F2E8CF"]
    private static let occasionCaptions: [String: String] = [
        "Work": "desk to dinner", "Campus": "campus day", "Errands": "errand run",
        "Working from home": "wfh but cute", "Nights out": "night out ✨", "Travel": "travel day ✈︎",
        "Gym": "post-gym coffee", "Date night": "date night 🍷",
    ]
    private static let fallbackCaptions = ["coffee date ☕", "off-duty", "gallery afternoon", "farmers market",
                                           "golden hour", "brunch w/ the girls", "running late"]

    // MARK: - What's needed

    /// True once the pieces can make at least one outfit.
    static func canStyle(_ items: [ClosetItem]) -> Bool {
        let owned = owned(items)
        let hasUpper = owned.contains { $0.category == .tops || $0.category == .outerwear }
        let hasBottom = owned.contains { $0.category == .bottoms }
        return (hasUpper && hasBottom) || owned.contains { $0.category == .dresses }
    }

    /// What to scan next to make the first outfit, e.g. "a bottom (or a dress)". Nil once it can style.
    static func nextNeeded(_ items: [ClosetItem]) -> String? {
        guard !canStyle(items) else { return nil }
        let owned = owned(items)
        let hasUpper = owned.contains { $0.category == .tops || $0.category == .outerwear }
        let hasBottom = owned.contains { $0.category == .bottoms }
        switch (hasUpper, hasBottom) {
        case (true, false): return "a bottom (or a dress)"
        case (false, true): return "a top (or a dress)"
        default: return "a top and a bottom, or a dress"
        }
    }

    // MARK: - Building looks

    static func lookBook(from items: [ClosetItem], occasions: [String]) -> LookBook {
        let owned = owned(items)
        func pieces(_ category: ClosetCategory) -> [ClosetItem] { owned.filter { $0.category == category } }
        let tops = pieces(.tops), outer = pieces(.outerwear), bottoms = pieces(.bottoms)
        let dresses = pieces(.dresses), shoes = pieces(.shoes), bags = pieces(.bags)

        // With no tops, a jacket can be the top half; otherwise jackets layer on top.
        let uppers = tops.isEmpty ? outer : tops
        let layers = tops.isEmpty ? [] : outer

        // Pairs walked diagonally, so the first looks use different pieces rather than the same top.
        var pairs: [[ClosetItem]] = []
        if !uppers.isEmpty && !bottoms.isEmpty {
            for diagonal in 0..<(uppers.count + bottoms.count - 1) {
                for i in 0..<uppers.count {
                    let j = diagonal - i
                    if bottoms.indices.contains(j) { pairs.append([uppers[i], bottoms[j]]) }
                }
            }
        }
        let dressBases = dresses.map { [$0] }
        var bases: [[ClosetItem]] = []
        for index in 0..<max(pairs.count, dressBases.count) {
            if pairs.indices.contains(index) { bases.append(pairs[index]) }
            if dressBases.indices.contains(index) { bases.append(dressBases[index]) }
        }

        let captions = captionList(for: occasions)
        let looks = bases.prefix(maxLooks).enumerated().map { index, base in
            let jacket = layers.isEmpty || !index.isMultiple(of: 2) ? nil : layers[(index / 2) % layers.count]
            return makeLook(base: base,
                            jacket: jacket,
                            shoes: shoes.isEmpty ? nil : shoes[index % shoes.count],
                            bag: bags.isEmpty ? nil : bags[index % bags.count],
                            index: index,
                            caption: captions[index % captions.count])
        }
        return LookBook(canvasAspect: canvasAspect, looks: looks)
    }

    // MARK: - Layout

    /// A spot on the card: centre, the box the piece must fit in (fractions of canvas width and
    /// height), and its tilt.
    private struct Slot {
        let cx: Double, cy: Double, boxW: Double, boxH: Double, rot: Double
    }

    private static func makeLook(base: [ClosetItem], jacket: ClosetItem?, shoes: ClosetItem?, bag: ClosetItem?,
                                 index: Int, caption: String) -> Look {
        var placed: [(ClosetItem, Slot)] = []
        if base.count == 2 {
            let (top, bottom) = (base[0], base[1])
            placed.append((bottom, Slot(cx: 0.40, cy: 0.70, boxW: 0.46, boxH: 0.42, rot: -3)))
            if let jacket {
                placed.append((jacket, Slot(cx: 0.68, cy: 0.34, boxW: 0.50, boxH: 0.36, rot: 7)))
                placed.append((top, Slot(cx: 0.32, cy: 0.33, boxW: 0.50, boxH: 0.32, rot: -3)))
                if let bag { placed.append((bag, Slot(cx: 0.84, cy: 0.60, boxW: 0.26, boxH: 0.22, rot: -5))) }
            } else {
                placed.append((top, Slot(cx: 0.42, cy: 0.33, boxW: 0.58, boxH: 0.34, rot: 3)))
                if let bag { placed.append((bag, Slot(cx: 0.81, cy: 0.52, boxW: 0.30, boxH: 0.24, rot: 8))) }
            }
            if let shoes { placed.append((shoes, Slot(cx: 0.79, cy: 0.86, boxW: 0.32, boxH: 0.18, rot: -6))) }
        } else if let dress = base.first {
            if let jacket {
                placed.append((dress, Slot(cx: 0.36, cy: 0.55, boxW: 0.42, boxH: 0.74, rot: -2)))
                placed.append((jacket, Slot(cx: 0.72, cy: 0.32, boxW: 0.46, boxH: 0.36, rot: 7)))
                if let bag { placed.append((bag, Slot(cx: 0.77, cy: 0.63, boxW: 0.28, boxH: 0.22, rot: -5))) }
            } else {
                placed.append((dress, Slot(cx: 0.40, cy: 0.55, boxW: 0.46, boxH: 0.76, rot: -2)))
                if let bag { placed.append((bag, Slot(cx: 0.80, cy: 0.44, boxW: 0.30, boxH: 0.26, rot: 8))) }
            }
            if let shoes { placed.append((shoes, Slot(cx: 0.76, cy: 0.86, boxW: 0.32, boxH: 0.18, rot: 4))) }
        }

        let mirror = index % 3 == 2
        let pieces = placed.map { item, slot in
            // Widest the piece can be while staying inside its box at its own aspect ratio.
            let width = min(slot.boxW, slot.boxH * Double(item.cutoutAspect) / canvasAspect)
            return Look.Piece(item: item.id, cx: slot.cx, cy: slot.cy, w: width, rot: slot.rot)
        }
        return Look(id: placed.map(\.0.id).joined(separator: "+"),
                    caption: caption,
                    floor: floors[index % floors.count],
                    mirror: mirror,
                    captionX: mirror ? 0.3 : 0.7,
                    captionY: mirror ? 0.08 : 0.09,
                    captionRot: mirror ? -4 : 6,
                    pieces: pieces)
    }

    private static func owned(_ items: [ClosetItem]) -> [ClosetItem] { items.filter { !$0.isWishlist } }

    /// Captions from her occasions first, then the general ones, without repeats.
    private static func captionList(for occasions: [String]) -> [String] {
        var seen = Set<String>()
        return (occasions.compactMap { occasionCaptions[$0] } + fallbackCaptions).filter { seen.insert($0).inserted }
    }
}
