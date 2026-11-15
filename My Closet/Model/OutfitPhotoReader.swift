import CoreImage
import PhotosUI
import SwiftUI
import Vision

/// Reads the outfit photos she picked and cuts out what *she* is wearing in each, for her to keep
/// or drop before anything is saved.
///
/// Her reference face decides whose clothes are read. With one person in the photo we read it
/// unless that face is confidently someone else (a mirror selfie with the phone over her face
/// still counts). With several people we find her face, keep only her body using Vision's
/// per-person masks, and read that, so a friend's outfit never reaches her closet.
/// Repeats of a piece across photos are offered once. Everything runs on this iPhone.
nonisolated enum OutfitPhotoReader {
    /// A piece found in one of her photos.
    struct Candidate: Identifiable, Sendable {
        let id = UUID()
        var piece: DetectedPiece
        /// Small sticker for the review grid.
        var thumbnail: UIImage
        let photoIndex: Int
        /// True once she replaced the cutout with her own photo of the piece.
        var isRetaken = false
    }

    enum Skip: Error, Sendable {
        case unreadable, noPerson, notYou, noClothes

        var message: String {
            switch self {
            case .unreadable: "Couldn't open it"
            case .noPerson: "No one in it"
            case .notYou: "Couldn't find you"
            case .noClothes: "No clothes found"
            }
        }
    }

    enum Event: Sendable {
        case reading(index: Int)
        case found(Candidate)
        case skipped(index: Int, Skip)
        case finished
    }

    static func read(_ items: [PhotosPickerItem], owner: [FaceMatcher.Embedding]) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await run(items, owner: owner) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct Known {
        let category: String
        let color: String
        let print: VNFeaturePrintObservation
    }

    private static let context = CIContext()

    private static func run(_ items: [PhotosPickerItem], owner: [FaceMatcher.Embedding], emit: (Event) -> Void) async {
        var known: [Known] = []
        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }
            emit(.reading(index: index))

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = ClothingAnalyzer.normalized(image)
            else {
                emit(.skipped(index: index, .unreadable))
                continue
            }

            let outfit: CGImage
            switch isolateOwner(in: cgImage, owner: owner) {
            case .success(let isolated): outfit = isolated
            case .failure(let skip):
                emit(.skipped(index: index, skip))
                continue
            }

            let pieces = OutfitParser.parse(outfit)
            guard !pieces.isEmpty else {
                emit(.skipped(index: index, .noClothes))
                continue
            }
            for piece in pieces {
                // Same shelf, same colour and a close feature print: the same piece seen again.
                if let print = PhotoLibraryScanner.featurePrint(of: piece.sticker) {
                    let isRepeat = known.contains { other in
                        guard other.category == piece.category, other.color == piece.color else { return false }
                        var distance: Float = .infinity
                        try? print.computeDistance(&distance, to: other.print)
                        return distance < PhotoLibraryScanner.duplicateDistance
                    }
                    known.append(Known(category: piece.category, color: piece.color, print: print))
                    if isRepeat { continue }
                }
                emit(.found(Candidate(piece: piece, thumbnail: PhotoLibraryScanner.thumbnail(of: piece.sticker),
                                      photoIndex: index)))
            }
        }
        emit(.finished)
    }

    // MARK: - Finding her

    /// The part of the photo to read: the whole photo when she's the only one in it, just her when
    /// there are several people, or a reason to skip it.
    private static func isolateOwner(in image: CGImage, owner: [FaceMatcher.Embedding]) -> Result<CGImage, Skip> {
        let people = peopleBoxes(in: image)
        guard !people.isEmpty else { return .failure(.noPerson) }
        let faces = owner.isEmpty ? [] : FaceMatcher.faces(in: image)

        if people.count == 1 {
            // Only a face we're sure isn't hers rules the photo out; no face (a phone in front
            // of it) or a borderline one is fine, since she chose this photo herself.
            let confidentlyOther = !faces.isEmpty && faces.allSatisfy {
                FaceMatcher.distance(of: $0, to: owner) > FaceMatcher.otherPersonDistance
            }
            return confidentlyOther ? .failure(.notYou) : .success(image)
        }

        // Several people: her face has to be there, and only her body is read.
        guard let her = faces.min(by: { FaceMatcher.distance(of: $0, to: owner) < FaceMatcher.distance(of: $1, to: owner) }),
              FaceMatcher.distance(of: her, to: owner) < FaceMatcher.matchDistance
        else { return .failure(.notYou) }

        // First her own box, so nobody standing beside her is in the frame…
        let faceCentre = CGPoint(x: her.box.midX, y: her.box.midY)
        let body = people.first { $0.insetBy(dx: -0.02, dy: -0.02).contains(faceCentre) }
            // No body box around her face: assume she's standing below it.
            ?? CGRect(x: her.box.midX - her.box.width * 2.5, y: 0,
                      width: her.box.width * 5, height: her.box.maxY + her.box.height * 0.5)
        guard let (cropped, region) = crop(image, to: body) else { return .failure(.notYou) }

        // …then, within that, only her pixels, which drops anyone overlapping her. Kept only when
        // her face is still the one in the result, since the per-person masks can pick wrong.
        let faceInCrop = CGRect(x: (her.box.minX - region.minX) / region.width,
                                y: (her.box.minY - region.minY) / region.height,
                                width: her.box.width / region.width, height: her.box.height / region.height)
        if let alone = personAlone(in: cropped, face: faceInCrop),
           FaceMatcher.faces(in: alone).contains(where: { FaceMatcher.distance(of: $0, to: owner) < FaceMatcher.matchDistance }) {
            return .success(alone)
        }
        return .success(cropped)
    }

    /// People clearly in the photo (normalised boxes, bottom-left origin). Small background
    /// figures don't count.
    private static func peopleBoxes(in image: CGImage) -> [CGRect] {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        request.runOnCPUInSimulator()
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        return (request.results ?? []).filter { $0.confidence > 0.4 && $0.boundingBox.height > 0.25 }.map(\.boundingBox)
    }

    /// Her body alone on white, cropped to her, using Vision's per-person masks: the person
    /// whose mask covers her face (or the area just below it).
    private static func personAlone(in image: CGImage, face: CGRect) -> CGImage? {
        let request = VNGeneratePersonInstanceMaskRequest()
        request.runOnCPUInSimulator()
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else { return nil }

        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        func label(atX x: CGFloat, y: CGFloat) -> UInt8 {
            // Vision's y runs bottom-up; the mask's rows run top-down.
            let column = min(max(Int(x * CGFloat(width)), 0), width - 1)
            let row = min(max(Int((1 - y) * CGFloat(height)), 0), height - 1)
            return base.load(fromByteOffset: row * rowBytes + column, as: UInt8.self)
        }
        // Her face, then her neck and chest just below it.
        let probes = stride(from: 0.0, through: 2.5, by: 0.5).map { face.midY - CGFloat($0) * face.height }
        guard let instance = probes.lazy.map({ label(atX: face.midX, y: $0) }).first(where: { $0 != 0 }) else { return nil }

        guard let buffer = try? observation.generateMaskedImage(ofInstances: IndexSet(integer: Int(instance)), from: handler,
                                                                  croppedToInstancesExtent: true)
        else { return nil }
        let her = CIImage(cvPixelBuffer: buffer)
        let white = CIImage(color: .white).cropped(to: her.extent)
        return context.createCGImage(her.composited(over: white), from: her.extent)
    }

    /// The image cut to `box` with a little margin, and the normalised region that was kept
    /// (bottom-left origin, like the box).
    private static func crop(_ image: CGImage, to box: CGRect) -> (CGImage, CGRect)? {
        let region = box.insetBy(dx: -0.06 * box.width, dy: -0.04 * box.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let rect = CGRect(x: region.minX * width, y: (1 - region.maxY) * height,
                          width: region.width * width, height: region.height * height).integral
        guard !rect.isEmpty, let cropped = image.cropping(to: rect) else { return nil }
        return (cropped, region)
    }

    // MARK: - Her reference face

    enum ReferenceError: Error {
        case unreadable, noFace, severalFaces

        var message: String {
            switch self {
            case .unreadable: "Couldn't open it"
            case .noFace: "No face found"
            case .severalFaces: "Pick a photo of just you"
            }
        }
    }

    /// Her face's fingerprint from a photo meant to show just her.
    @concurrent
    static func referenceFace(in image: UIImage) async -> Result<FaceMatcher.Embedding, ReferenceError> {
        guard let cgImage = ClothingAnalyzer.normalized(image) else { return .failure(.unreadable) }
        let faces = FaceMatcher.faces(in: cgImage)
        guard let first = faces.first else { return .failure(.noFace) }
        // A second face about as big means we can't tell which one is her.
        if faces.count > 1, faces[1].box.height > first.box.height * 0.6 { return .failure(.severalFaces) }
        return .success(first.embedding)
    }

    // MARK: - Saving

    /// Saves the pieces she kept. Cutouts from her outfit photos go in as "photos" pieces, so the
    /// studio queue turns them into clean product photos in the background; pieces she
    /// photographed again go in as "camera" pieces, like the scan.
    @concurrent
    static func save(_ kept: [(piece: DetectedPiece, category: String, retaken: Bool)]) async throws {
        let now = Date.now
        for (index, entry) in kept.enumerated() {
            let saved = SavedPiece(id: UUID().uuidString, name: entry.piece.name, category: entry.category,
                                   color: entry.piece.color, isWishlist: false,
                                   addedAt: now.addingTimeInterval(-Double(index)),
                                   cutoutAspect: entry.piece.cutoutAspect,
                                   source: entry.retaken ? "camera" : "photos")
            try PieceLibrary.add(saved, cutout: entry.piece.cutout, sticker: entry.piece.sticker)
        }
    }
}
