import Observation
import UIKit

/// Hands every photo-scan piece without a studio photo to `StudioUploader`, which keeps working
/// in the background, and tracks what's on its way so tiles can show it. Pieces are saved straight
/// away with their cutout, so the closet and looks never wait: they just get prettier as replies
/// arrive. Anything unfinished is picked up again the next time the closet loads.
@Observable
final class StudioQueue {
    /// Pieces whose studio photo is on its way, for a pulsing hint on their tiles.
    private(set) var working: Set<String> = []
    /// Pieces whose studio photo arrived while the app was open.
    private(set) var finished: Set<String> = []
    /// The last failure, for debugging; studio photos are an extra, never a blocker.
    private(set) var lastError: String?

    /// Called after a piece's images are replaced, so the closet can reload.
    var onReplace: () -> Void = {}

    private var failed: Set<String> = []
    /// Set when the account can't make images at all (no credit, bad key), so nothing more is sent.
    private var stopped = false

    /// The app's one queue, for the uploader's callbacks (which arrive on a background queue).
    private static weak var current: StudioQueue?

    init() {
        Self.current = self
        StudioUploader.shared.onFinish = { id, outcome in
            Task { @MainActor in StudioQueue.current?.finish(id, outcome) }
        }
        Task {
            let inFlight = await StudioUploader.shared.inFlightPieceIDs()
            working.formUnion(inFlight)
        }
    }

    /// Sends every photo-scan piece that doesn't have its studio photo yet.
    func enqueueMissing(in pieces: [SavedPiece]) {
        guard StudioPhotoGenerator.isConfigured, !stopped else { return }
        for piece in pieces.reversed() where piece.source == "photos" && piece.studio != true {
            guard !working.contains(piece.id), !failed.contains(piece.id) else { continue }
            working.insert(piece.id)
            Task { await submit(piece) }
        }
    }

    private func submit(_ piece: SavedPiece) async {
        do {
            guard let url = PieceLibrary.cutoutURL(for: piece.id), let cutout = UIImage(contentsOfFile: url.path) else {
                working.remove(piece.id)
                return
            }
            let job = try await Self.makeJob(cutout, category: piece.category)
            try await StudioUploader.shared.submit(job, pieceID: piece.id)
        } catch {
            working.remove(piece.id)
            failed.insert(piece.id)
            lastError = error.localizedDescription
        }
    }

    /// Rendering and encoding the upload is image work; keep it off the main thread.
    @concurrent
    private static func makeJob(_ cutout: UIImage, category: String) async throws -> StudioPhotoGenerator.Job {
        try StudioPhotoGenerator.job(for: cutout, category: category)
    }

    private func finish(_ id: String, _ outcome: StudioUploader.Outcome) {
        working.remove(id)
        switch outcome {
        case .saved:
            SavedImageCache.forget(PieceLibrary.cutoutURL(for: id))
            SavedImageCache.forget(PieceLibrary.stickerURL(for: id))
            finished.insert(id)
            onReplace()
        case .failed(let status, let message):
            lastError = message
            guard let status else {
                failed.insert(id)
                return
            }
            let outOfQuota = status == 429 && message.lowercased().contains("quota")
            if status == 429 && !outOfQuota {
                // Just sending too fast: try this piece again shortly.
                Task {
                    try? await Task.sleep(for: .seconds(45))
                    retry(id)
                }
            } else if [401, 402, 403].contains(status) || outOfQuota {
                // No credit or a bad key fails every piece the same way: stop sending.
                failed.insert(id)
                stopped = true
                StudioUploader.shared.cancelAll()
                failed.formUnion(working)
                working.removeAll()
            } else {
                failed.insert(id)
            }
        }
    }

    private func retry(_ id: String) {
        guard !stopped, !working.contains(id),
              let piece = PieceLibrary.load().first(where: { $0.id == id }), piece.studio != true
        else { return }
        working.insert(id)
        Task { await submit(piece) }
    }
}
