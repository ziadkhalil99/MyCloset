import UIKit
import Vision

/// The full-length photo she gives us for try-on: the base her closet gets dressed onto.
/// Kept as a single JPEG in Application Support on this iPhone.
enum TryOnPhoto {
    /// What a quick look at the photo found, so we can tell her before she commits to it.
    enum Check: Equatable {
        case fullBody
        case notFullBody
        case severalPeople
        case noPerson

        var message: String {
            switch self {
            case .fullBody: "Looks great"
            case .notFullBody: "We can't see you head to toe"
            case .severalPeople: "Pick a photo of just you"
            case .noPerson: "We couldn't find you in this one"
            }
        }

        var isGood: Bool { self == .fullBody }
    }

    private static let maxSide: CGFloat = 2048

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "TryOn/model.jpg")
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }

    static func save(_ image: UIImage) throws {
        let scaled = downscaled(image)
        guard let data = scaled.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Finds the people in the photo and whether one of them is in frame from head to ankles.
    /// Nil when body detection can't run here (it isn't available in the Simulator), so we don't
    /// warn her about a photo we never looked at.
    @concurrent
    static func check(_ image: UIImage) async -> Check? {
        guard let cgImage = ClothingAnalyzer.normalized(image) else { return .noPerson }
        let request = VNDetectHumanBodyPoseRequest()
        request.runOnCPUInSimulator()
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return nil
        }
        let people = (request.results ?? []).filter { $0.confidence > 0.3 }
        guard let person = people.first else { return .noPerson }
        if people.count > 1 { return .severalPeople }

        func sees(_ joint: VNHumanBodyPoseObservation.JointName) -> Bool {
            ((try? person.recognizedPoint(joint))?.confidence ?? 0) > 0.3
        }
        let head = sees(.nose) || sees(.leftEar) || sees(.rightEar) || sees(.neck)
        let feet = sees(.leftAnkle) || sees(.rightAnkle)
        return head && feet ? .fullBody : .notFullBody
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
