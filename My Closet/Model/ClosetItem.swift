import SwiftUI

enum ClosetCategory: String, CaseIterable, Identifiable {
    case tops, outerwear, bottoms, dresses, shoes, bags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tops: "Tops"
        case .outerwear: "Outerwear"
        case .bottoms: "Bottoms"
        case .dresses: "Dresses"
        case .shoes: "Shoes"
        case .bags: "Bags"
        }
    }
}

/// One piece of clothing. Images live in Assets.xcassets/Closet as
/// `<id>` (tight cutout), `<id>Sticker` (white die-cut border) and `<id>Photo` (the original photo).
struct ClosetItem: Identifiable, Hashable {
    let id: String
    let name: String
    let category: ClosetCategory
    let material: String
    let color: String
    /// Original photo width / height.
    let photoAspect: CGFloat
    /// Where the cutout sits inside the original photo, normalized, top-left origin.
    let cutoutRect: CGRect
    /// Added from a screenshot: images live in the App Group (`PieceLibrary`), not the asset catalog.
    var isSaved = false
    var isWishlist = false

    var cutout: String { id }
    var sticker: String { id + "Sticker" }
    var photo: String { id + "Photo" }
    var detail: String { "\(material) · \(color)" }
    /// Cutout width / height.
    var cutoutAspect: CGFloat { (cutoutRect.width * photoAspect) / cutoutRect.height }

    var cutoutImage: Image {
        isSaved ? SavedImageCache.image(at: PieceLibrary.cutoutURL(for: id)) : Image(cutout)
    }
    var stickerImage: Image {
        isSaved ? SavedImageCache.image(at: PieceLibrary.stickerURL(for: id)) : Image(sticker)
    }

    /// Largest cutout width that fits inside `box` at this piece's aspect ratio.
    func fittedWidth(in box: CGSize) -> CGFloat { min(box.width, box.height * cutoutAspect) }
}

extension ClosetItem {
    static let all: [ClosetItem] = [
        .init(id: "cardiganCherry", name: "Cherry cardigan", category: .tops, material: "Knit", color: "Cream",
              photoAspect: 0.750, cutoutRect: CGRect(x: 0.037, y: 0.232, width: 0.950, height: 0.754)),
        .init(id: "hoodieBrown", name: "Cocoa hoodie", category: .tops, material: "Fleece", color: "Brown",
              photoAspect: 0.667, cutoutRect: CGRect(x: 0.000, y: 0.080, width: 1.000, height: 0.920)),
        .init(id: "hoodieGreen", name: "Forest hoodie", category: .tops, material: "Fleece", color: "Green",
              photoAspect: 0.749, cutoutRect: CGRect(x: 0.000, y: 0.015, width: 1.000, height: 0.985)),
        .init(id: "jacketBlack", name: "Leather jacket", category: .outerwear, material: "Faux leather", color: "Black",
              photoAspect: 0.886, cutoutRect: CGRect(x: 0.103, y: 0.144, width: 0.791, height: 0.715)),
        .init(id: "jacketBurgundy", name: "Cropped jacket", category: .outerwear, material: "Faux leather", color: "Burgundy",
              photoAspect: 1.211, cutoutRect: CGRect(x: 0.000, y: 0.000, width: 1.000, height: 0.993)),
        .init(id: "jeansLight", name: "Wide-leg jeans", category: .bottoms, material: "Denim", color: "Mid wash",
              photoAspect: 0.750, cutoutRect: CGRect(x: 0.187, y: 0.119, width: 0.645, height: 0.787)),
        .init(id: "jeansDark", name: "Split-hem jeans", category: .bottoms, material: "Denim", color: "Indigo",
              photoAspect: 1.000, cutoutRect: CGRect(x: 0.169, y: 0.117, width: 0.706, height: 0.779)),
        .init(id: "skirtBrown", name: "Pleated skirt", category: .bottoms, material: "Twill", color: "Chocolate",
              photoAspect: 0.750, cutoutRect: CGRect(x: 0.119, y: 0.252, width: 0.756, height: 0.492)),
        .init(id: "shortsTan", name: "Tailored shorts", category: .bottoms, material: "Wool blend", color: "Tan",
              photoAspect: 0.769, cutoutRect: CGRect(x: 0.048, y: 0.200, width: 0.905, height: 0.677)),
        .init(id: "dressDots", name: "Polka-dot midi", category: .dresses, material: "Cotton", color: "Brown",
              photoAspect: 0.684, cutoutRect: CGRect(x: 0.174, y: 0.029, width: 0.592, height: 0.922)),
        .init(id: "sneakersSamba", name: "Classic sneakers", category: .shoes, material: "Leather", color: "White",
              photoAspect: 0.840, cutoutRect: CGRect(x: 0.129, y: 0.137, width: 0.707, height: 0.703)),
        .init(id: "sneakers530", name: "Runner sneakers", category: .shoes, material: "Mesh", color: "White",
              photoAspect: 0.563, cutoutRect: CGRect(x: 0.049, y: 0.418, width: 0.898, height: 0.424)),
        .init(id: "bagHobo", name: "Slouchy hobo", category: .bags, material: "Leather", color: "Espresso",
              photoAspect: 0.667, cutoutRect: CGRect(x: 0.162, y: 0.141, width: 0.676, height: 0.725)),
        .init(id: "bagShoulder", name: "Shoulder bag", category: .bags, material: "Leather", color: "Brown",
              photoAspect: 0.769, cutoutRect: CGRect(x: 0.197, y: 0.205, width: 0.610, height: 0.658)),
        .init(id: "bagDenim", name: "Denim baguette", category: .bags, material: "Denim", color: "Sky",
              photoAspect: 0.667, cutoutRect: CGRect(x: 0.154, y: 0.174, width: 0.692, height: 0.654)),
    ]

    /// The pieces the staged scan walks through, chosen for their busy backgrounds.
    static var scanDemo: [ClosetItem] { ["cardiganCherry", "jeansDark", "sneakersSamba"].compactMap { item(id: $0) } }

    static func item(id: String) -> ClosetItem? { all.first { $0.id == id } }
}

extension ClosetItem {
    init(saved piece: SavedPiece) {
        self.init(id: piece.id, name: piece.name,
                  category: ClosetCategory(rawValue: piece.category) ?? .tops,
                  material: "From a screenshot", color: piece.color,
                  photoAspect: piece.cutoutAspect, cutoutRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                  isSaved: true, isWishlist: piece.isWishlist)
    }
}

/// Decoded saved-piece images, so grid tiles don't re-read PNGs on every render.
enum SavedImageCache {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(at url: URL?) -> Image {
        guard let url else { return Image(uiImage: UIImage()) }
        if let hit = cache.object(forKey: url as NSURL) { return Image(uiImage: hit) }
        guard let loaded = UIImage(contentsOfFile: url.path) else { return Image(uiImage: UIImage()) }
        cache.setObject(loaded, forKey: url as NSURL)
        return Image(uiImage: loaded)
    }
}
