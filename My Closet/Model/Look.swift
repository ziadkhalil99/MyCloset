import Foundation

/// A flat-lay outfit. `cx`/`cy` are the piece centre as fractions of the canvas, `w` its width
/// as a fraction of canvas width, `rot` degrees clockwise. Pieces draw in array order
/// (first = bottom). Looks are built from the person's own pieces by `LookStylist`.
struct Look: Identifiable, Hashable {
    struct Piece: Hashable {
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
}

struct LookBook {
    let canvasAspect: Double
    let looks: [Look]
}
