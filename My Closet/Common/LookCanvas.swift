import SwiftUI

/// Draws one flat-lay look on its tinted "floor". Pieces settle onto the card one by one
/// the first time it appears, like someone laying the outfit out.
struct LookCanvas: View {
    let look: Look
    let animateIn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled: Bool

    init(look: Look, animateIn: Bool = true) {
        self.look = look
        self.animateIn = animateIn
        _settled = State(initialValue: !animateIn)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ForEach(Array(look.pieces.enumerated()), id: \.offset) { index, piece in
                    pieceView(piece, index: index, in: size)
                }
                Text(look.caption)
                    .font(.hand(size.width * 0.062))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
                    .rotationEffect(.degrees(look.captionRot))
                    .position(x: look.captionX * size.width, y: look.captionY * size.height)
                    .opacity(settled ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(Double(look.pieces.count) * 0.09 + 0.1), value: settled)
            }
        }
        .background(Color(hexString: look.floor))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .onAppear { settled = true }
    }

    private func pieceView(_ piece: Look.Piece, index: Int, in size: CGSize) -> some View {
        let cx = look.mirror ? 1 - piece.cx : piece.cx
        let rot = look.mirror ? -piece.rot : piece.rot
        // Reduce Motion: pieces cross-fade in place instead of dropping onto the card.
        let travel = !reduceMotion
        return Image(piece.item)
            .resizable()
            .scaledToFit()
            .frame(width: piece.w * size.width)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
            .rotationEffect(.degrees(settled || !travel ? rot : rot * 1.8))
            .scaleEffect(settled || !travel ? 1 : 1.18)
            .opacity(settled ? 1 : 0)
            .position(x: cx * size.width, y: piece.cy * size.height + (settled || !travel ? 0 : -14))
            .animation(.spring(duration: 0.55, bounce: 0.28).delay(Double(index) * 0.09), value: settled)
    }
}
