import UIKit

/// Everyday basics she can tap to fill her closet in seconds during onboarding, instead of
/// scanning. Each has a clean product cutout bundled as `Resources/Catalog/catalog-<id>.png`.
/// Picked pieces are saved to `PieceLibrary` like any scanned piece (source "catalog"), so the
/// closet, looks and try-on treat them the same; she can swap in her real pieces later.
nonisolated struct StarterPiece: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: ClosetCategory
    let material: String
    let color: String

    /// The id the piece gets in her closet.
    var closetID: String { "catalog-" + id }
    var imageName: String { "catalog-\(id).png" }
}

nonisolated enum StarterCatalog {
    static let pieces: [StarterPiece] = [
        .init(id: "teeWhite", name: "White tee", category: .tops, material: "Cotton", color: "White"),
        .init(id: "teeBlack", name: "Black tee", category: .tops, material: "Cotton", color: "Black"),
        .init(id: "teeStriped", name: "Striped long-sleeve", category: .tops, material: "Cotton", color: "Cream"),
        .init(id: "tankWhite", name: "Ribbed tank", category: .tops, material: "Rib knit", color: "White"),
        .init(id: "bodysuitBlack", name: "Black bodysuit", category: .tops, material: "Jersey", color: "Black"),
        .init(id: "shirtWhite", name: "White shirt", category: .tops, material: "Poplin", color: "White"),
        .init(id: "shirtDenim", name: "Denim shirt", category: .tops, material: "Denim", color: "Light blue"),
        .init(id: "sweaterCream", name: "Cream sweater", category: .tops, material: "Knit", color: "Cream"),
        .init(id: "sweatshirtGrey", name: "Grey sweatshirt", category: .tops, material: "Fleece", color: "Grey"),
        .init(id: "hoodieBlack", name: "Black hoodie", category: .tops, material: "Fleece", color: "Black"),
        .init(id: "cardiganBeige", name: "Beige cardigan", category: .tops, material: "Knit", color: "Beige"),
        .init(id: "blouseSatin", name: "Satin blouse", category: .tops, material: "Satin", color: "Champagne"),
        .init(id: "jacketDenim", name: "Denim jacket", category: .outerwear, material: "Denim", color: "Mid wash"),
        .init(id: "jacketLeather", name: "Leather jacket", category: .outerwear, material: "Faux leather", color: "Black"),
        .init(id: "blazerBlack", name: "Black blazer", category: .outerwear, material: "Wool blend", color: "Black"),
        .init(id: "trenchBeige", name: "Trench coat", category: .outerwear, material: "Cotton", color: "Beige"),
        .init(id: "coatCamel", name: "Camel coat", category: .outerwear, material: "Wool", color: "Camel"),
        .init(id: "pufferBlack", name: "Puffer jacket", category: .outerwear, material: "Nylon", color: "Black"),
        .init(id: "jeansWideLight", name: "Wide-leg jeans", category: .bottoms, material: "Denim", color: "Light wash"),
        .init(id: "jeansStraightBlue", name: "Straight jeans", category: .bottoms, material: "Denim", color: "Mid wash"),
        .init(id: "jeansSkinnyBlack", name: "Black skinny jeans", category: .bottoms, material: "Denim", color: "Black"),
        .init(id: "leggingsBlack", name: "Black leggings", category: .bottoms, material: "Jersey", color: "Black"),
        .init(id: "trousersBlack", name: "Black trousers", category: .bottoms, material: "Crepe", color: "Black"),
        .init(id: "trousersBeige", name: "Beige trousers", category: .bottoms, material: "Twill", color: "Beige"),
        .init(id: "sweatpantsGrey", name: "Grey joggers", category: .bottoms, material: "Fleece", color: "Grey"),
        .init(id: "shortsDenim", name: "Denim shorts", category: .bottoms, material: "Denim", color: "Light wash"),
        .init(id: "skirtMiniBlack", name: "Black mini skirt", category: .bottoms, material: "Twill", color: "Black"),
        .init(id: "skirtSatin", name: "Satin midi skirt", category: .bottoms, material: "Satin", color: "Champagne"),
        .init(id: "dressBlack", name: "Little black dress", category: .dresses, material: "Jersey", color: "Black"),
        .init(id: "dressWhite", name: "White summer dress", category: .dresses, material: "Linen", color: "White"),
        .init(id: "dressFloral", name: "Floral midi dress", category: .dresses, material: "Viscose", color: "Floral"),
        .init(id: "dressBrown", name: "Brown midi dress", category: .dresses, material: "Jersey", color: "Chocolate"),
        .init(id: "sneakersWhite", name: "White sneakers", category: .shoes, material: "Leather", color: "White"),
        .init(id: "sneakersRunner", name: "Running shoes", category: .shoes, material: "Mesh", color: "Grey"),
        .init(id: "bootsBlack", name: "Ankle boots", category: .shoes, material: "Leather", color: "Black"),
        .init(id: "heelsNude", name: "Strappy heels", category: .shoes, material: "Leather", color: "Nude"),
        .init(id: "flatsBlack", name: "Ballet flats", category: .shoes, material: "Leather", color: "Black"),
        .init(id: "loafersBlack", name: "Loafers", category: .shoes, material: "Leather", color: "Black"),
        .init(id: "slidesBeige", name: "Slides", category: .shoes, material: "Rubber", color: "Beige"),
        .init(id: "toteBlack", name: "Black tote", category: .bags, material: "Leather", color: "Black"),
        .init(id: "bagShoulderTan", name: "Shoulder bag", category: .bags, material: "Leather", color: "Tan"),
        .init(id: "crossbodyBlack", name: "Crossbody bag", category: .bags, material: "Leather", color: "Black"),
        .init(id: "toteCanvas", name: "Canvas tote", category: .bags, material: "Canvas", color: "Natural"),
    ]

    /// Categories in the order they're shown, with the pieces in each.
    static var sections: [(category: ClosetCategory, pieces: [StarterPiece])] {
        ClosetCategory.allCases.compactMap { category in
            let inCategory = pieces.filter { $0.category == category }
            return inCategory.isEmpty ? nil : (category, inCategory)
        }
    }

    static func image(for piece: StarterPiece) -> UIImage? { UIImage(named: piece.imageName) }

    /// True once the picks can make at least one outfit: a top or jacket with a bottom, or a dress.
    static func canStyle(_ picks: [StarterPiece]) -> Bool {
        let categories = Set(picks.map(\.category))
        let upper = categories.contains(.tops) || categories.contains(.outerwear)
        return (upper && categories.contains(.bottoms)) || categories.contains(.dresses)
    }

    /// What's still missing for a first outfit, or nil once she has one.
    static func missing(_ picks: [StarterPiece]) -> String? {
        guard !canStyle(picks) else { return nil }
        let categories = Set(picks.map(\.category))
        let upper = categories.contains(.tops) || categories.contains(.outerwear)
        switch (upper, categories.contains(.bottoms)) {
        case (true, false): return "Add a bottom or a dress to style your first look"
        case (false, true): return "Add a top or a dress to style your first look"
        default: return "Pick a top and a bottom, or a dress"
        }
    }

    /// Saves the picks to her closet, in the order she tapped them (first pick ends up newest).
    /// Making the die-cut stickers is image work, so it runs off the main thread.
    @concurrent
    static func save(_ picks: [StarterPiece]) async throws {
        let now = Date.now
        for (index, piece) in picks.enumerated() {
            guard let image = image(for: piece), let cutout = image.cgImage,
                  let sticker = ClothingAnalyzer.sticker(for: cutout)
            else { continue }
            let saved = SavedPiece(
                id: piece.closetID, name: piece.name, category: piece.category.rawValue, color: piece.color,
                isWishlist: false, addedAt: now.addingTimeInterval(-Double(index)),
                cutoutAspect: Double(cutout.width) / Double(cutout.height), source: "catalog", studio: true)
            try PieceLibrary.add(saved, cutout: image, sticker: UIImage(cgImage: sticker))
        }
    }
}
