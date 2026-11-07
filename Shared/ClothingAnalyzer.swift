import UIKit
import Vision
import CoreImage

/// A piece found in a screenshot, ready to review before it's saved.
struct DetectedPiece: Identifiable, Sendable {
    let id = UUID()
    let cutout: UIImage
    let sticker: UIImage
    var name: String
    /// A `ClosetCategory` raw value.
    var category: String
    var color: String
    /// True when the image classifier recognised clothing, not just a foreground subject.
    let looksLikeClothing: Bool

    var cutoutAspect: Double { cutout.size.width / max(cutout.size.height, 1) }
}

/// On-device analysis: Vision lifts each foreground subject off the screenshot, the image
/// classifier names and categorises it, and the cutout's average colour gives it a colour name.
/// Nothing leaves the phone.
nonisolated enum ClothingAnalyzer {
    static let categories = ["tops", "outerwear", "bottoms", "dresses", "shoes", "bags"]

    /// Longest side the screenshot is scaled to before analysis; keeps the share extension
    /// well inside its memory limit.
    private static let maxSide: CGFloat = 1600
    private static let maxPieces = 4
    private static let context = CIContext()

    struct Result: Sendable {
        /// Subjects the classifier recognised as clothing — the only ones offered by default.
        let clothing: [DetectedPiece]
        /// Everything else that was lifted (or the salient crop when lifting failed), offered only
        /// if the person explicitly asks to add the image anyway.
        let other: [DetectedPiece]
    }

    @concurrent
    static func analyze(_ source: UIImage) async -> Result {
        guard let image = normalized(source) else { return Result(clothing: [], other: []) }
        var subjects = liftSubjects(from: image)
        if subjects.isEmpty, let crop = salientCrop(of: image) { subjects = [crop] }

        let pieces = subjects.prefix(maxPieces + 2).compactMap(describe)
        return Result(clothing: Array(pieces.filter(\.looksLikeClothing).prefix(maxPieces)),
                      other: Array(pieces.filter { !$0.looksLikeClothing }.prefix(maxPieces)))
    }

    // MARK: - Lifting

    /// Each foreground instance as a transparent cutout, largest first.
    private static func liftSubjects(from image: CGImage) -> [CGImage] {
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        guard let observation = request.results?.first else { return [] }
        let minArea = Double(image.width * image.height) * 0.015
        let cutouts = observation.allInstances.compactMap { instance -> CGImage? in
            guard let buffer = try? observation.generateMaskedImage(
                ofInstances: IndexSet(integer: instance), from: handler, croppedToInstancesExtent: true)
            else { return nil }
            return context.createCGImage(CIImage(cvPixelBuffer: buffer), from: CIImage(cvPixelBuffer: buffer).extent)
        }
        return cutouts
            .filter { Double($0.width * $0.height) >= minArea }
            .sorted { $0.width * $0.height > $1.width * $1.height }
    }

    /// Fallback when nothing can be lifted (or subject lifting is unavailable): crop to the
    /// most eye-catching region so there's still something to add.
    private static func salientCrop(of image: CGImage) -> CGImage? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let box = request.results?.first?.salientObjects?.first?.boundingBox ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let rect = VNImageRectForNormalizedRect(box, image.width, image.height)
        // Vision's origin is bottom-left; CGImage cropping is top-left.
        let flipped = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY, width: rect.width, height: rect.height)
        return image.cropping(to: flipped.integral)
    }

    // MARK: - Describing

    private static func describe(_ subject: CGImage) -> DetectedPiece? {
        let cutout = downscaled(subject, maxSide: 1000)
        let match = classify(cutout)
        let color = colorName(of: cutout)
        guard let sticker = makeSticker(from: cutout) else { return nil }
        let noun = match?.noun ?? "Piece"
        return DetectedPiece(
            cutout: UIImage(cgImage: cutout),
            sticker: UIImage(cgImage: sticker),
            name: "\(color) \(noun.lowercased())",
            category: match?.category ?? "tops",
            color: color,
            looksLikeClothing: match != nil
        )
    }

    private struct Match { let category: String; let noun: String }

    /// Keyword → (category, display noun). Checked against the classifier's labels.
    private static let keywords: [(String, String, String)] = [
        ("dress", "dresses", "Dress"), ("gown", "dresses", "Dress"),
        ("blazer", "outerwear", "Blazer"), ("jacket", "outerwear", "Jacket"), ("coat", "outerwear", "Coat"),
        ("parka", "outerwear", "Parka"), ("vest", "outerwear", "Vest"),
        ("jeans", "bottoms", "Jeans"), ("denim", "bottoms", "Jeans"), ("trouser", "bottoms", "Trousers"),
        ("pants", "bottoms", "Trousers"), ("skirt", "bottoms", "Skirt"), ("shorts", "bottoms", "Shorts"),
        ("legging", "bottoms", "Leggings"),
        ("sneaker", "shoes", "Sneakers"), ("boot", "shoes", "Boots"), ("sandal", "shoes", "Sandals"),
        ("heel", "shoes", "Heels"), ("loafer", "shoes", "Loafers"), ("shoe", "shoes", "Shoes"),
        ("footwear", "shoes", "Shoes"),
        ("handbag", "bags", "Bag"), ("purse", "bags", "Bag"), ("backpack", "bags", "Backpack"),
        ("tote", "bags", "Tote"), ("bag", "bags", "Bag"),
        ("hoodie", "tops", "Hoodie"), ("sweatshirt", "tops", "Sweatshirt"), ("sweater", "tops", "Sweater"),
        ("cardigan", "tops", "Cardigan"), ("blouse", "tops", "Blouse"), ("tshirt", "tops", "T-shirt"), ("shirt", "tops", "Shirt"), ("jersey", "tops", "Top"),
        ("tank", "tops", "Top"), ("top", "tops", "Top"),
        ("clothing", "tops", "Piece"), ("apparel", "tops", "Piece"), ("textile", "tops", "Piece"),
    ]

    private static func classify(_ cutout: CGImage) -> Match? {
        guard let flat = flattenedOnWhite(cutout) else { return nil }
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: flat).perform([request])
        let labels = (request.results ?? []).filter { $0.confidence > 0.08 }
        // Labels arrive most-confident first; the first one naming a garment wins, but a generic
        // "clothing" label only counts if nothing more specific shows up.
        var generic: Match?
        for label in labels {
            // Whole-word matches only, so "laptop" isn't a top and "bagel" isn't a bag.
            let words = label.identifier.lowercased().split { !$0.isLetter }.map(String.init)
            guard let hit = keywords.first(where: { kw in
                words.contains { $0 == kw.0 || $0 == kw.0 + "s" || $0 == kw.0 + "es" }
            }) else { continue }
            let match = Match(category: hit.1, noun: hit.2)
            if hit.2 == "Piece" { generic = generic ?? match } else { return match }
        }
        return generic
    }

    private static func colorName(of image: CGImage) -> String {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return "Neutral" }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
            let a = Double(pixels[i + 3])
            r += Double(pixels[i]) / a; g += Double(pixels[i + 1]) / a; b += Double(pixels[i + 2]) / a; n += 1
        }
        guard n > 0 else { return "Neutral" }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0
        UIColor(red: r / n, green: g / n, blue: b / n, alpha: 1).getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
        return colorName(hue: hue * 360, saturation: sat, brightness: bri)
    }

    private static func colorName(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> String {
        if brightness < 0.2 { return "Black" }
        if saturation < 0.1 {
            if brightness > 0.9 { return "White" }
            return brightness > 0.6 ? "Light grey" : "Grey"
        }
        let warm = hue < 50 || hue >= 340
        if warm && saturation < 0.4 {
            if brightness > 0.8 { return "Cream" }
            if brightness > 0.6 { return "Beige" }
            return brightness > 0.4 ? "Tan" : "Brown"
        }
        switch hue {
        case ..<15, 340...:
            if brightness < 0.5 { return "Burgundy" }
            return saturation < 0.5 ? "Pink" : "Red"
        case ..<40: return brightness < 0.6 ? "Brown" : "Orange"
        case ..<70: return brightness < 0.6 ? "Olive" : "Yellow"
        case ..<165: return saturation < 0.35 || brightness < 0.45 ? "Olive" : "Green"
        case ..<200: return "Teal"
        case ..<255:
            if brightness < 0.45 { return "Navy" }
            return saturation < 0.45 ? "Sky" : "Blue"
        case ..<290: return "Purple"
        default: return "Pink"
        }
    }

    // MARK: - Image helpers

    /// Upright, sRGB, at most `maxSide` on the longest edge.
    private static func normalized(_ image: UIImage) -> CGImage? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    private static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = CGFloat(maxSide) / CGFloat(longest)
        let input = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(input, from: input.extent.integral) ?? image
    }

    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let white = CIImage(color: .white).cropped(to: input.extent)
        return context.createCGImage(input.composited(over: white), from: input.extent)
    }

    /// The cutout with a white die-cut border, padded by `stickerBorder` of the longer side on
    /// every edge — the same geometry as the bundled `<id>Sticker` assets.
    static let stickerBorder: CGFloat = 0.042

    private static func makeSticker(from cutout: CGImage) -> CGImage? {
        let pad = (stickerBorder * CGFloat(max(cutout.width, cutout.height))).rounded()
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(cutout.width) + pad * 2, height: CGFloat(cutout.height) + pad * 2)
        let piece = CIImage(cgImage: cutout).transformed(by: CGAffineTransform(translationX: pad, y: pad))
        let silhouette = piece.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        let border = silhouette
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: pad])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.0])
        return context.createCGImage(piece.composited(over: border).cropped(to: canvas), from: canvas)
    }
}
