import Foundation
import Observation

/// Her own closet: pieces scanned in the app or added from screenshots through the share
/// extension, and the looks styled from them.
@Observable
final class ClosetStore {
    private(set) var saved: [ClosetItem] = []
    private(set) var lookBook = LookBook(canvasAspect: LookStylist.canvasAspect, looks: [])
    private(set) var recentlyAdded: Set<String> = []
    var wornLookID: String?
    /// Turns pieces found in her photos into studio product photos in the background.
    let studio = StudioQueue()
    var profile = OnboardingProfile.load() {
        didSet {
            profile.save()
            if profile.occasions != oldValue.occasions { restyle() }
        }
    }

    /// Newest first.
    var items: [ClosetItem] { saved }

    /// True once there's enough for at least one outfit.
    var canStyle: Bool { LookStylist.canStyle(items) }

    private static let lastSeenKey = "closet.lastSeenSavedPiece"

    init() {
        studio.onReplace = { [weak self] in self?.reloadSaved() }
        reloadSaved()
    }

    /// Re-reads the shared library and restyles the looks. Pieces added since the closet was
    /// last opened get the "new!" tag.
    func reloadSaved() {
        let pieces = PieceLibrary.load()
        let lastSeen = UserDefaults.standard.object(forKey: Self.lastSeenKey) as? Date ?? .distantPast
        for piece in pieces where piece.addedAt > lastSeen {
            recentlyAdded.insert(piece.id)
        }
        if let newest = pieces.first?.addedAt, newest > lastSeen {
            UserDefaults.standard.set(newest, forKey: Self.lastSeenKey)
        }
        saved = pieces.map { ClosetItem(saved: $0) }
        restyle()
        studio.enqueueMissing(in: pieces)
    }

    func remove(_ item: ClosetItem) {
        guard item.isSaved else { return }
        try? PieceLibrary.remove(id: item.id)
        recentlyAdded.remove(item.id)
        reloadSaved()
    }

    func items(in category: ClosetCategory?) -> [ClosetItem] {
        guard let category else { return items }
        return items.filter { $0.category == category }
    }

    /// The pieces in a look, in the order they're laid out.
    func pieces(of look: Look) -> [ClosetItem] {
        look.pieces.compactMap { piece in items.first { $0.id == piece.item } }
    }

    func looks(containing item: ClosetItem) -> [Look] {
        lookBook.looks.filter { look in look.pieces.contains { $0.item == item.id } }
    }

    private func restyle() {
        lookBook = LookStylist.lookBook(from: items, occasions: profile.occasions)
        if let worn = wornLookID, !lookBook.looks.contains(where: { $0.id == worn }) { wornLookID = nil }
    }
}
