import UIKit

/// A piece the person added from a screenshot. The share extension writes these and the app
/// reads them, both through the shared App Group container.
struct SavedPiece: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    /// A `ClosetCategory` raw value.
    var category: String
    var color: String
    var isWishlist: Bool
    let addedAt: Date
    /// Cutout width / height.
    let cutoutAspect: Double
}

/// On-disk store in the App Group container: `Pieces/index.json` plus
/// `<id>-cutout.png` (transparent cutout) and `<id>-sticker.png` (cutout with a white die-cut border).
enum PieceLibrary {
    static let appGroupID = "group.com.My-Closet"

    enum LibraryError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Your closet couldn't be opened. Open My Closet once, then try again." }
    }

    static var folder: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let url = base.appendingPathComponent("Pieces", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cutoutURL(for id: String) -> URL? { folder?.appendingPathComponent("\(id)-cutout.png") }
    static func stickerURL(for id: String) -> URL? { folder?.appendingPathComponent("\(id)-sticker.png") }
    private static var indexURL: URL? { folder?.appendingPathComponent("index.json") }

    /// Newest first.
    static func load() -> [SavedPiece] {
        guard let url = indexURL, let data = try? Data(contentsOf: url),
              let pieces = try? JSONDecoder().decode([SavedPiece].self, from: data)
        else { return [] }
        return pieces.sorted { $0.addedAt > $1.addedAt }
    }

    static func add(_ piece: SavedPiece, cutout: UIImage, sticker: UIImage) throws {
        guard let cutoutURL = cutoutURL(for: piece.id), let stickerURL = stickerURL(for: piece.id) else {
            throw LibraryError.unavailable
        }
        try cutout.pngData()?.write(to: cutoutURL, options: .atomic)
        try sticker.pngData()?.write(to: stickerURL, options: .atomic)
        var pieces = load().filter { $0.id != piece.id }
        pieces.insert(piece, at: 0)
        try write(pieces)
    }

    static func remove(id: String) throws {
        for url in [cutoutURL(for: id), stickerURL(for: id)].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        try write(load().filter { $0.id != id })
    }

    private static func write(_ pieces: [SavedPiece]) throws {
        guard let url = indexURL else { throw LibraryError.unavailable }
        try JSONEncoder().encode(pieces).write(to: url, options: .atomic)
    }
}
