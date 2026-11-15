import Photos
import SwiftUI

/// Drives "Reading your photos": asks for library access, runs `PhotoLibraryScanner`, and keeps
/// what the screen shows — the counters, the outfit being read, and the pieces on each shelf.
@Observable
final class PhotoScanModel {
    enum Phase { case idle, running, finished, denied }

    struct Found: Identifiable {
        let id: String
        let category: ClosetCategory
        let sticker: UIImage
        let photoID: String
    }

    private(set) var phase: Phase = .idle
    private(set) var total = 0
    private(set) var scanned = 0
    private(set) var outfits = 0
    private(set) var currentPhoto: (id: String, image: UIImage)?
    private(set) var found: [Found] = []
    /// True when the person shared only some photos.
    private(set) var isLimited = false

    private var rejected: Set<String> = []
    private var task: Task<Void, Never>?

    var progress: Double { total == 0 ? 0 : Double(scanned) / Double(total) }

    func found(in category: ClosetCategory) -> [Found] { found.filter { $0.category == category } }

    func start(onPiece: @escaping () -> Void) {
        guard phase == .idle || phase == .denied, task == nil else { return }
        task = Task {
            var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if status == .notDetermined {
                status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            guard status == .authorized || status == .limited else {
                phase = .denied
                task = nil
                return
            }
            isLimited = status == .limited
            phase = .running
            for await event in PhotoLibraryScanner.scan(owner: OwnerFaces.load()) {
                apply(event, onPiece: onPiece)
            }
            phase = .finished
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if phase == .running { phase = .finished }
    }

    /// The photo on screen isn't her (or isn't an outfit): take its pieces back out of the closet.
    func rejectCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        rejected.insert(photo.id)
        for piece in found where piece.photoID == photo.id {
            try? PieceLibrary.remove(id: piece.id)
        }
        withAnimation(.spring(duration: 0.4)) {
            found.removeAll { $0.photoID == photo.id }
            currentPhoto = nil
        }
    }

    private func apply(_ event: PhotoLibraryScanner.Event, onPiece: () -> Void) {
        switch event {
        case .started(let total):
            self.total = total
        case .progress(let scanned):
            self.scanned = scanned
        case .outfit(let id, let image):
            outfits += 1
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { currentPhoto = (id, image) }
        case .piece(let saved, let sticker, let photoID):
            guard !rejected.contains(photoID) else {
                try? PieceLibrary.remove(id: saved.id)
                return
            }
            let category = ClosetCategory(rawValue: saved.category) ?? .tops
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) {
                found.append(Found(id: saved.id, category: category, sticker: sticker, photoID: photoID))
            }
            onPiece()
        case .finished:
            scanned = total
        }
    }
}
