import UIKit

/// Sends studio-photo jobs on a background `URLSession`, so they finish even if she moves on,
/// leaves the app or locks the phone. iOS relaunches the app in the background to deliver the
/// replies, and each one is turned into images and saved to the closet right here, with or
/// without any UI on screen.
nonisolated final class StudioUploader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = StudioUploader()
    static let identifier = "com.My-Closet.studio"

    enum Outcome: Sendable {
        case saved
        /// `status` is the provider's HTTP status, or nil for a network error.
        case failed(status: Int?, message: String)
    }

    /// Called on a background queue once a piece's studio photo is saved, or has failed.
    var onFinish: (@Sendable (_ pieceID: String, _ outcome: Outcome) -> Void)?
    /// Handed over by the app delegate when iOS wakes the app for this session.
    var backgroundCompletion: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var received: [Int: Data] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Pieces whose studio photo is on its way, including uploads from before the app was closed.
    func inFlightPieceIDs() async -> Set<String> {
        Set(await session.allTasks.compactMap(\.taskDescription))
    }

    /// Starts the upload for a piece, unless one is already on its way.
    func submit(_ job: StudioPhotoGenerator.Job, pieceID: String) async throws {
        guard !(await inFlightPieceIDs()).contains(pieceID) else { return }
        // Background sessions only upload from a file.
        let file = Self.bodyFile(for: pieceID)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try job.body.write(to: file, options: .atomic)
        let task = session.uploadTask(with: job.request, fromFile: file)
        task.taskDescription = pieceID
        task.resume()
    }

    /// Stops everything still waiting, e.g. when the account is out of credit.
    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    private static func bodyFile(for pieceID: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StudioUploads", isDirectory: true)
            .appendingPathComponent("\(pieceID).body")
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock { received[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let data = lock.withLock { received.removeValue(forKey: task.taskIdentifier) } ?? Data()
        guard let pieceID = task.taskDescription else { return }
        try? FileManager.default.removeItem(at: Self.bodyFile(for: pieceID))
        if let error {
            onFinish?(pieceID, .failed(status: nil, message: error.localizedDescription))
            return
        }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            let output = try StudioPhotoGenerator.output(from: data, status: status)
            if var piece = PieceLibrary.load().first(where: { $0.id == pieceID }) {
                piece.studio = true
                piece.cutoutAspect = output.aspect
                // Returns false if she deleted the piece meanwhile; nothing to do then.
                try PieceLibrary.replaceImages(of: piece, cutout: output.cutout, sticker: output.sticker)
            }
            onFinish?(pieceID, .saved)
        } catch StudioPhotoGenerator.StudioError.server(let status, let message) {
            onFinish?(pieceID, .failed(status: status, message: message))
        } catch {
            onFinish?(pieceID, .failed(status: nil, message: error.localizedDescription))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { backgroundCompletion = nil }
            return backgroundCompletion
        }
        DispatchQueue.main.async { completion?() }
    }
}

/// Hands iOS's "your background uploads finished" wake-up to `StudioUploader`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == StudioUploader.identifier else { return completionHandler() }
        nonisolated(unsafe) let completion = completionHandler
        StudioUploader.shared.backgroundCompletion = { completion() }
    }
}
