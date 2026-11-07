import Foundation

/// A hand-arranged flat-lay outfit. Placement is authored in Resources/Looks.json:
/// `cx`/`cy` are the piece centre as fractions of the canvas, `w` its width as a fraction
/// of canvas width, `rot` degrees clockwise. Pieces draw in array order (first = bottom).
struct Look: Identifiable, Decodable, Hashable {
    struct Piece: Decodable, Hashable {
        let item: String
        let cx: Double
        let cy: Double
        let w: Double
        let rot: Double
    }

    let id: String
    let caption: String
    let floor: String
    let mirror: Bool
    let captionX: Double
    let captionY: Double
    let captionRot: Double
    let pieces: [Piece]

    var items: [ClosetItem] { pieces.compactMap { ClosetItem.item(id: $0.item) } }
}

struct LookBook: Decodable {
    let canvasAspect: Double
    let looks: [Look]

    static let bundled: LookBook = {
        guard let url = Bundle.main.url(forResource: "Looks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let book = try? JSONDecoder().decode(LookBook.self, from: data)
        else {
            assertionFailure("Looks.json missing or malformed")
            return LookBook(canvasAspect: 0.78, looks: [])
        }
        return book
    }()
}
