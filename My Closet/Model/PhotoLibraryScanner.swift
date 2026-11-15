import Photos
import UIKit
import Vision

/// Walks the photo library newest first, keeps the photos that show one person head to toe,
/// cuts what they're wearing off with `OutfitParser`, and drops repeats of pieces it has
/// already found. Photos are read on device only; iCloud-only originals are skipped rather
/// than downloaded.
nonisolated enum PhotoLibraryScanner {
    enum Event: Sendable {
        /// How many photos will be looked at.
        case started(total: Int)
        case progress(scanned: Int)
        /// A photo with an outfit in it, about to be cut up.
        case outfit(photoID: String, image: UIImage)
        /// A new piece, already saved to the closet.
        case piece(SavedPiece, sticker: UIImage, photoID: String)
        case finished
    }

    /// Only the last year, and at most this many photos, so a run takes a minute or two.
    static let maxPhotos = 2000
    static let maxPieces = 80
    /// Hard cap on photos of her that get read and cut up in one scan: keeps the run short and
    /// bounds how many pieces are sent for studio photos.
    static let maxOutfitPhotos = 50
    private static let lookBack: TimeInterval = 365 * 24 * 3600
    /// Photos this close in time to an outfit already read are usually the same outfit.
    private static let sameOutfitWindow: TimeInterval = 120
    /// Feature-print distance under which two same-colour pieces on one shelf count as one.
    /// Different garments measured 0.75–1.15 apart; the Simulator returns 0 for every pair.
    static let duplicateDistance: Float = 0.6

    /// - Parameter owner: Her reference face fingerprints; only photos where she appears are read.
    static func scan(owner: [FaceMatcher.Embedding]) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await run(owner: owner) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Run

    private struct Known {
        let category: String
        let color: String
        let print: VNFeaturePrintObservation
    }

    private static func run(owner: [FaceMatcher.Embedding], emit: (Event) -> Void) async {
        let assets = fetchRecentPhotos()
        emit(.started(total: assets.count))

        var known: [Known] = []
        var lastOutfitDate: Date?
        var savedCount = 0
        var outfitCount = 0

        for (index, asset) in assets.enumerated() {
            if Task.isCancelled || savedCount >= maxPieces || outfitCount >= maxOutfitPhotos { break }
            defer { if index % 4 == 3 || index == assets.count - 1 { emit(.progress(scanned: index + 1)) } }

            if let date = asset.creationDate, let last = lastOutfitDate,
               abs(last.timeIntervalSince(date)) < sameOutfitWindow { continue }

            guard let small = await image(for: asset, longestSide: 480),
                  let smallCG = ClothingAnalyzer.normalized(small),
                  showsOnePersonHeadToToe(smallCG)
            else { continue }

            guard let large = await image(for: asset, longestSide: 1600, allowDownload: true),
                  let largeCG = ClothingAnalyzer.normalized(large),
                  // Her photos only: someone else's outfit doesn't belong in her closet.
                  FaceMatcher.showsOwner(largeCG, references: owner)
            else { continue }

            let pieces = OutfitParser.parse(largeCG)
            guard !pieces.isEmpty else { continue }
            lastOutfitDate = asset.creationDate
            outfitCount += 1
            let photoID = asset.localIdentifier
            emit(.outfit(photoID: photoID, image: small))

            for piece in pieces where savedCount < maxPieces {
                guard let print = featurePrint(of: piece.sticker) else { continue }
                // Same shelf, same colour and a close feature print: the same piece seen again.
                let isRepeat = known.contains { other in
                    guard other.category == piece.category, other.color == piece.color else { return false }
                    var distance: Float = .infinity
                    try? print.computeDistance(&distance, to: other.print)
                    return distance < duplicateDistance
                }
                known.append(Known(category: piece.category, color: piece.color, print: print))
                guard !isRepeat else { continue }

                let saved = SavedPiece(id: UUID().uuidString, name: piece.name, category: piece.category,
                                       color: piece.color, isWishlist: false, addedAt: .now,
                                       cutoutAspect: piece.cutoutAspect, source: "photos")
                guard (try? PieceLibrary.add(saved, cutout: piece.cutout, sticker: piece.sticker)) != nil else { continue }
                savedCount += 1
                emit(.piece(saved, sticker: thumbnail(of: piece.sticker), photoID: photoID))
            }
        }
        emit(.finished)
    }

    // MARK: - Library

    private static func fetchRecentPhotos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate > %@", Date.now.addingTimeInterval(-lookBack) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        // PhotoKit can't filter on media subtypes in a predicate, so screenshots are dropped here.
        result.enumerateObjects { asset, _, stop in
            guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            assets.append(asset)
            if assets.count >= maxPhotos { stop.pointee = true }
        }
        return assets
    }

    /// Small images come from whatever is on the phone, so screening thousands of photos stays
    /// fast. Full-size outfit photos may be downloaded from her own iCloud library: with
    /// "Optimize iPhone Storage" most originals aren't on the device.
    private static func image(for asset: PHAsset, longestSide: CGFloat, allowDownload: Bool = false) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowDownload
        options.isSynchronous = false
        let size = CGSize(width: longestSide, height: longestSide)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Vision

    /// One person, tall in the frame — a mirror selfie or a full-length photo. Group shots are
    /// skipped so friends' outfits don't end up in the closet.
    private static func showsOnePersonHeadToToe(_ image: CGImage) -> Bool {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        request.runOnCPUInSimulator()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let people = (request.results ?? []).filter { $0.confidence > 0.4 && $0.boundingBox.height > 0.2 }
        guard people.count == 1, let person = people.first else { return false }
        return person.boundingBox.height >= 0.5
    }

    /// Computed on the sticker flattened onto white: transparent pixels would otherwise read as
    /// black and make every silhouette look alike.
    static func featurePrint(of image: UIImage) -> VNFeaturePrintObservation? {
        let flat = UIGraphicsImageRenderer(size: image.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        guard let cg = flat.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.runOnCPUInSimulator()
        guard (try? VNImageRequestHandler(cgImage: cg).perform([request])) != nil else { return nil }
        return request.results?.first
    }

    static func thumbnail(of image: UIImage) -> UIImage {
        let scale = min(1, 220 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
