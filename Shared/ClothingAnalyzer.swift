import UIKit
import Vision
import CoreImage

/// A piece found in a screenshot, ready to review before it's saved.
nonisolated struct DetectedPiece: Identifiable, Sendable {
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
/// Photos the person took themselves can also get a studio polish.
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
        /// False when no subject could be lifted and the pieces are just the salient crop.
        var lifted = true
    }

    /// - Parameter polish: Evens out crease shading and lighting on the cutouts. Meant for the
    ///   person's own photos; screenshots of product shots are already clean.
    @concurrent
    static func analyze(_ source: UIImage, polish: Bool = false) async -> Result {
        guard let image = normalized(source) else { return Result(clothing: [], other: []) }
        var subjects = liftSubjects(from: image)
        let lifted = !subjects.isEmpty
        if subjects.isEmpty, let crop = salientCrop(of: image) { subjects = [crop] }

        let pieces = subjects.prefix(maxPieces + 2).compactMap { describe($0, polish: polish) }
        return Result(clothing: Array(pieces.filter(\.looksLikeClothing).prefix(maxPieces)),
                      other: Array(pieces.filter { !$0.looksLikeClothing }.prefix(maxPieces)),
                      lifted: lifted)
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

    private static func describe(_ subject: CGImage, polish: Bool) -> DetectedPiece? {
        let raw = downscaled(subject, maxSide: 1000)
        // Classification and colour read the untouched pixels; only what's shown is polished.
        let match = classify(raw)
        let color = colorName(of: raw)
        let cutout = polish ? (studioPolish(raw) ?? raw) : raw
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

    /// Names, colours and stickers a garment that `OutfitParser` already cut off a person. The
    /// parser knows the broad category; the classifier only refines it (a jacket on top is
    /// outerwear) and gives it a better noun.
    static func describeGarment(_ cutout: CGImage, category: String, noun: String, polish: Bool) -> DetectedPiece? {
        let raw = downscaled(cutout, maxSide: 900)
        var category = category, noun = noun
        if let match = classify(raw),
           match.category == category || (category == "tops" && match.category == "outerwear"),
           match.noun != "Piece" {
            category = match.category
            noun = match.noun
        }
        let color = colorName(of: raw)
        let shown = polish ? (studioPolish(raw) ?? raw) : raw
        guard let sticker = makeSticker(from: shown) else { return nil }
        return DetectedPiece(cutout: UIImage(cgImage: shown), sticker: UIImage(cgImage: sticker),
                             name: "\(color) \(noun.lowercased())", category: category, color: color,
                             looksLikeClothing: true)
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
        request.runOnCPUInSimulator()
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

    // MARK: - Studio polish

    /// Softens wrinkles and uneven room lighting so a photo of a piece on the bed reads more like
    /// a product shot. Crease shading is multiplicative, so each pixel is brightened by the ratio
    /// of coarse to fine local luminance: folds even out while colour and fine texture stay. The
    /// gain is clamped, so prints, seams and pleats (strong contrast) survive. Silhouettes are
    /// unchanged — it can't truly iron the garment.
    private static func studioPolish(_ cutout: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cutout)
        let extent = input.extent
        let side = max(extent.width, extent.height)

        // The blur runs on premultiplied pixels, so the transparent surroundings carry no weight.
        func luminance(sigma: CGFloat) -> CIImage {
            let weights = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            return input.applyingGaussianBlur(sigma: sigma).cropped(to: extent).unpremultiplyingAlpha()
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": weights, "inputGVector": weights, "inputBVector": weights,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    // A small floor keeps the division below finite on black fabric.
                    "inputBiasVector": CIVector(x: 0.002, y: 0.002, z: 0.002, w: 1),
                ])
        }
        let fine = luminance(sigma: side * 0.004)
        let coarse = luminance(sigma: side * 0.035)
        let gain = coarse
            .applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: fine])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.8])
            // Mostly lifts shadows; darkening highlights would dull light fabrics.
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0.9, y: 0.9, z: 0.9, w: 1),
                "inputMaxComponents": CIVector(x: 1.35, y: 1.35, z: 1.35, w: 1),
            ])
        let evened = gain
            .applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: input.unpremultiplyingAlpha().settingAlphaOne(in: extent),
            ])
            .applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": 0.25, "inputHighlightAmount": 1.0])
            .applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.35, "inputRadius": 1.5])
            .cropped(to: extent)
        // Put the original silhouette back.
        let output = evened.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: input,
        ])
        return context.createCGImage(output, from: extent)
    }

    // MARK: - Image helpers

    /// Upright, sRGB, at most `maxSide` on the longest edge.
    static func normalized(_ image: UIImage) -> CGImage? {
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

    /// A white die-cut sticker for a cutout made elsewhere (the studio photos).
    static func sticker(for cutout: CGImage) -> CGImage? { makeSticker(from: cutout) }

    /// The largest foreground subject, lifted off its background. Nil where Vision can't lift
    /// (the Simulator).
    static func liftLargestSubject(_ image: CGImage) -> CGImage? { liftSubjects(from: image).first }

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

extension VNRequest {
    /// The Simulator has no Neural Engine, so Vision's ML requests fail there ("Could not create
    /// inference context") unless they're pinned to the CPU. No effect on a device.
    nonisolated func runOnCPUInSimulator() {
        #if targetEnvironment(simulator)
        guard let stages = try? supportedComputeStageDevices else { return }
        for (stage, devices) in stages {
            if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }
}
