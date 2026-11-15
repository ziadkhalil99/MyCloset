import CoreML
import UIKit
import Vision

/// Recognises the closet's owner, so the photo scan only takes outfits from photos of her and
/// skips friends and family. Vision finds the faces; `FaceEmbedder` (FaceNet, VGGFace2 weights)
/// turns each one into a 512-number fingerprint, and two fingerprints closer than
/// `matchDistance` are taken to be the same person. Everything runs on device.
nonisolated enum FaceMatcher {
    typealias Embedding = [Float]

    /// Euclidean distance between normalised embeddings. On test photos the same person measured
    /// 0.6–1.19 apart (with a phone partly covering the face) and other people 1.28 and up.
    static let matchDistance: Float = 1.2

    nonisolated(unsafe) private static let model: VNCoreMLModel? = {
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        // The Simulator's GPU path returns empty output for this model.
        configuration.computeUnits = .cpuOnly
        #endif
        guard let url = Bundle.main.url(forResource: "FaceEmbedder", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url, configuration: configuration)
        else { return nil }
        return try? VNCoreMLModel(for: model)
    }()

    /// One embedding per face Vision finds, largest face first. Tiny background faces are ignored.
    static func embeddings(in image: CGImage) -> [Embedding] {
        let request = VNDetectFaceRectanglesRequest()
        request.runOnCPUInSimulator()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let faces = (request.results ?? [])
            .filter { $0.boundingBox.height >= 0.03 }
            .sorted { $0.boundingBox.height > $1.boundingBox.height }
        return faces.prefix(4).compactMap { face in
            crop(face.boundingBox, from: image).flatMap(embedding(of:))
        }
    }

    /// A face found in a photo: where it is (Vision's normalised box, bottom-left origin) and
    /// its fingerprint.
    struct Face: Sendable {
        let box: CGRect
        let embedding: Embedding
    }

    /// Faces further than this from every reference are confidently someone else. Between
    /// `matchDistance` and this it's too close to call (a phone covering half the face).
    static let otherPersonDistance: Float = 1.35

    /// Every face Vision finds with its fingerprint, largest first. Tiny background faces are ignored.
    static func faces(in image: CGImage) -> [Face] {
        let request = VNDetectFaceRectanglesRequest()
        request.runOnCPUInSimulator()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let found = (request.results ?? [])
            .filter { $0.boundingBox.height >= 0.03 }
            .sorted { $0.boundingBox.height > $1.boundingBox.height }
        return found.prefix(6).compactMap { face in
            crop(face.boundingBox, from: image).flatMap(embedding(of:)).map { Face(box: face.boundingBox, embedding: $0) }
        }
    }

    /// How far a face is from the closest of her reference faces.
    static func distance(of face: Face, to references: [Embedding]) -> Float {
        references.map { distance(face.embedding, $0) }.min() ?? .infinity
    }

    /// True when any face in the image is close to any of the owner's reference faces.
    static func showsOwner(_ image: CGImage, references: [Embedding]) -> Bool {
        guard !references.isEmpty else { return true }
        return embeddings(in: image).contains { face in
            references.contains { distance(face, $0) < matchDistance }
        }
    }

    static func distance(_ a: Embedding, _ b: Embedding) -> Float {
        guard a.count == b.count else { return .infinity }
        var sum: Float = 0
        for i in a.indices { sum += (a[i] - b[i]) * (a[i] - b[i]) }
        return sum.squareRoot()
    }

    // MARK: - Private

    /// The face with a 20% margin, squared up, the way the model was trained.
    private static func crop(_ box: CGRect, from image: CGImage) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let side = max(box.width * width, box.height * height) * 1.4
        let centre = CGPoint(x: box.midX * width, y: (1 - box.midY) * height)
        let rect = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        return rect.isEmpty ? nil : image.cropping(to: rect)
    }

    private static func embedding(of face: CGImage) -> Embedding? {
        guard let model else { return nil }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        request.runOnCPUInSimulator()
        try? VNImageRequestHandler(cgImage: face).perform([request])
        guard let output = (request.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue
        else { return nil }
        var values = (0..<output.count).map { Float(truncating: output[$0]) }
        let norm = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0, norm.isFinite else { return nil }
        for i in values.indices { values[i] /= norm }
        return values
    }
}

/// The owner's reference face fingerprints, from the photos she picked in onboarding.
/// Kept on this iPhone only (UserDefaults); the photos themselves aren't stored.
enum OwnerFaces {
    private static let key = "owner.faceEmbeddings"

    static func load() -> [FaceMatcher.Embedding] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let faces = try? JSONDecoder().decode([[Float]].self, from: data)
        else { return [] }
        return faces
    }

    static func save(_ faces: [FaceMatcher.Embedding]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(faces), forKey: key)
    }
}
