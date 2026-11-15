import CoreImage
import CoreML
import UIKit
import Vision

/// Splits a photo of someone into the pieces they're wearing. `ClothesParser` (SegFormer-B2
/// fine-tuned on the ATR human-parsing set) labels every pixel as top, pants, shoes and so on;
/// each garment's pixels become a mask, Vision's person segmentation sharpens its edges, and
/// `ClothingAnalyzer` names, colours and stickers the cutout. All on device.
nonisolated enum OutfitParser {
    /// The garments the closet has shelves for, with the ATR labels that make them up.
    private enum Part: CaseIterable {
        case top, bottom, dress, shoes, bag

        var labels: Set<Int32> {
            switch self {
            case .top: [4]       // upper-clothes
            case .bottom: [5, 6] // skirt, pants
            case .dress: [7]
            case .shoes: [9, 10] // left and right shoe, kept as one pair
            case .bag: [16]
            }
        }

        var category: String {
            switch self {
            case .top: "tops"
            case .bottom: "bottoms"
            case .dress: "dresses"
            case .shoes: "shoes"
            case .bag: "bags"
            }
        }

        var noun: String {
            switch self {
            case .top: "Top"
            case .bottom: "Trousers"
            case .dress: "Dress"
            case .shoes: "Shoes"
            case .bag: "Bag"
            }
        }

        /// Smallest share of the photo the garment must cover to be worth a closet slot.
        var minCoverage: Double {
            switch self {
            case .top, .bottom: 0.02
            case .dress: 0.04
            case .shoes: 0.003
            case .bag: 0.01
            }
        }

        /// Shoes and bags often sit away from the body's outline, so only clothes are trimmed
        /// to the person mask.
        var trimsToPerson: Bool { self == .top || self == .bottom || self == .dress }
    }

    private static let side = 512
    private static let context = CIContext()

    nonisolated(unsafe) private static let model: VNCoreMLModel? = {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        // Loaded by URL rather than through the generated `ClothesParser` class, which inherits
        // the app's main-actor default and this runs on a background task.
        guard let url = Bundle.main.url(forResource: "ClothesParser", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url, configuration: configuration)
        else { return nil }
        return try? VNCoreMLModel(for: model)
    }()

    /// The pieces worn in `image` (upright, sRGB), largest first.
    static func parse(_ image: CGImage) -> [DetectedPiece] {
        guard let labels = labelMap(for: image) else { return [] }
        let personMask = personMask(for: image)
        let source = CIImage(cgImage: image)

        return Part.allCases.compactMap { part -> (DetectedPiece, Int)? in
            var mask = [UInt8](repeating: 0, count: side * side)
            for i in 0..<labels.count where part.labels.contains(labels[i]) { mask[i] = 255 }
            let count = keepMainRegions(of: &mask)
            guard Double(count) / Double(side * side) >= part.minCoverage,
                  let box = trimmedBounds(of: mask),
                  // A garment scattered in fragments (behind a barbell, half out of frame) makes a poor sticker.
                  Double(count) / Double(box.width * box.height) >= 0.3,
                  let cutout = cutout(of: source, mask: mask, box: box, person: part.trimsToPerson ? personMask : nil),
                  let piece = ClothingAnalyzer.describeGarment(cutout, category: part.category, noun: part.noun, polish: true)
            else { return nil }
            return (piece, count)
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    // MARK: - Model

    /// One label per pixel of a `side`×`side` view of the image, top row first.
    private static func labelMap(for image: CGImage) -> [Int32]? {
        guard let model else { return nil }
        let request = VNCoreMLRequest(model: model)
        // The model was trained on images stretched to a square, so stretch rather than crop.
        request.imageCropAndScaleOption = .scaleFill
        request.runOnCPUInSimulator()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let output = (request.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue,
              output.shape.count == 3
        else { return nil }
        let rowStride = output.strides[1].intValue
        let columnStride = output.strides[2].intValue
        return output.withUnsafeBufferPointer(ofType: Int32.self) { buffer in
            var labels = [Int32](repeating: 0, count: side * side)
            for y in 0..<side {
                for x in 0..<side { labels[y * side + x] = buffer[y * rowStride + x * columnStride] }
            }
            return labels
        }
    }

    /// Vision's person matte, scaled to the image. Nil where unavailable.
    private static func personMask(for image: CGImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        request.runOnCPUInSimulator()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        let mask = CIImage(cvPixelBuffer: buffer)
        return mask.transformed(by: CGAffineTransform(scaleX: CGFloat(image.width) / mask.extent.width,
                                                      y: CGFloat(image.height) / mask.extent.height))
    }

    // MARK: - Masks

    /// Drops specks and stray patches (a hand holding a phone, a sliver behind a barbell),
    /// keeping each region at least a fifth the size of the largest — so both shoes survive.
    /// Returns how many pixels are left.
    private static func keepMainRegions(of mask: inout [UInt8]) -> Int {
        var region = [Int32](repeating: 0, count: mask.count)
        var sizes: [Int] = [0]
        var stack: [Int] = []
        for start in 0..<mask.count where mask[start] != 0 && region[start] == 0 {
            let id = Int32(sizes.count)
            var size = 0
            region[start] = id
            stack.append(start)
            while let i = stack.popLast() {
                size += 1
                let x = i % side, y = i / side
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < side && ny >= 0 && ny < side {
                    let n = ny * side + nx
                    if mask[n] != 0 && region[n] == 0 {
                        region[n] = id
                        stack.append(n)
                    }
                }
            }
            sizes.append(size)
        }
        guard let largest = sizes.max(), largest > 0 else { return 0 }
        var kept = 0
        for i in 0..<mask.count where mask[i] != 0 {
            if sizes[Int(region[i])] * 5 >= largest { kept += 1 } else { mask[i] = 0 }
        }
        return kept
    }

    /// Bounds of the mask in label-map pixels (top-left origin), ignoring the outermost 1% of
    /// pixels on each side so a few stray labels don't stretch the crop.
    private static func trimmedBounds(of mask: [UInt8]) -> CGRect? {
        var columns = [Int](repeating: 0, count: side)
        var rows = [Int](repeating: 0, count: side)
        for y in 0..<side {
            for x in 0..<side where mask[y * side + x] != 0 {
                columns[x] += 1
                rows[y] += 1
            }
        }
        func range(_ counts: [Int]) -> ClosedRange<Int>? {
            let total = counts.reduce(0, +)
            guard total > 0 else { return nil }
            let cut = max(1, total / 100)
            var low = 0, sum = 0
            while sum + counts[low] < cut { sum += counts[low]; low += 1 }
            var high = side - 1
            sum = 0
            while sum + counts[high] < cut { sum += counts[high]; high -= 1 }
            return low <= high ? low...high : nil
        }
        guard let x = range(columns), let y = range(rows) else { return nil }
        return CGRect(x: x.lowerBound, y: y.lowerBound, width: x.count, height: y.count)
    }

    /// The garment lifted off the photo as a transparent, tightly cropped image.
    private static func cutout(of source: CIImage, mask: [UInt8], box: CGRect, person: CIImage?) -> CGImage? {
        guard let maskImage = grayImage(mask) else { return nil }
        let extent = source.extent
        let scaleX = extent.width / CGFloat(side), scaleY = extent.height / CGFloat(side)

        // Upscale smoothly and soften the stair-steps, then firm the edge back up.
        var matte = CIImage(cgImage: maskImage)
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scaleY, kCIInputAspectRatioKey: scaleX / scaleY,
            ])
            .cropped(to: extent)
            .applyingGaussianBlur(sigma: max(scaleX, scaleY) * 0.6)
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 2.2])
        if let person {
            matte = matte.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: person])
        }
        let lifted = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: matte,
        ])

        // `box` is top-left origin in label pixels; Core Image is bottom-left in image pixels.
        let pad = 0.02 * CGFloat(side)
        let padded = box.insetBy(dx: -pad, dy: -pad).intersection(CGRect(x: 0, y: 0, width: side, height: side))
        let crop = CGRect(x: padded.minX * scaleX, y: extent.height - padded.maxY * scaleY,
                          width: padded.width * scaleX, height: padded.height * scaleY).integral
        return context.createCGImage(lifted, from: crop)
    }

    private static func grayImage(_ pixels: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
