import Foundation
import Observation

/// The bundled demo closet plus anything added from screenshots through the share extension.
@Observable
final class ClosetStore {
    private(set) var saved: [ClosetItem] = []
    let lookBook = LookBook.bundled
    private(set) var recentlyAdded: Set<String> = []
    var wornLookID: String?
    var profile = OnboardingProfile()

    /// Saved pieces first (newest first), then the bundled closet.
    var items: [ClosetItem] { saved + ClosetItem.all }

    private static let lastSeenKey = "closet.lastSeenSavedPiece"

    init() {
        reloadSaved()
    }

    /// Re-reads the shared library. Pieces added since the closet was last opened get the "new!" tag.
    func reloadSaved() {
        let pieces = PieceLibrary.load()
        let lastSeen = UserDefaults.standard.object(forKey: Self.lastSeenKey) as? Date ?? .distantPast
        for piece in pieces where piece.addedAt > lastSeen {
            recentlyAdded.insert(piece.id)
        }
        if let newest = pieces.first?.addedAt, newest > lastSeen {
            UserDefaults.standard.set(newest, forKey: Self.lastSeenKey)
        }
        saved = pieces.map(ClosetItem.init(saved:))
    }

    func remove(_ item: ClosetItem) {
        guard item.isSaved else { return }
        try? PieceLibrary.remove(id: item.id)
        recentlyAdded.remove(item.id)
        reloadSaved()
    }

    func markAdded(_ item: ClosetItem) {
        recentlyAdded.insert(item.id)
    }

    func items(in category: ClosetCategory?) -> [ClosetItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }

    func looks(containing item: ClosetItem) -> [Look] {
        lookBook.looks.filter { look in look.pieces.contains { $0.item == item.id } }
    }
}
