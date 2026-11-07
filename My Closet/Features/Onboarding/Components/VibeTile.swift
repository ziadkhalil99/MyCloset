import SwiftUI

/// A vibe answer. Unselected it shows her real photo; selecting it sweeps a light down the
/// photo, fades the background and pops the piece off as a sticker.
struct VibeTile: View {
    let vibe: Vibe
    let isOn: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var peeled: Bool
    @State private var sweep: CGFloat = -0.2
    @State private var sweepVisible = false
    @State private var peelTask: Task<Void, Never>?

    private static let height: CGFloat = 136

    init(vibe: Vibe, isOn: Bool, action: @escaping () -> Void) {
        self.vibe = vibe
        self.isOn = isOn
        self.action = action
        _peeled = State(initialValue: isOn)
    }

    private var item: ClosetItem? { ClosetItem.item(id: vibe.itemID) }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Theme.card

                if let item {
                    Color.clear
                        .overlay { Image(item.photo).resizable().scaledToFill() }
                        .clipped()
                        .opacity(peeled ? 0 : 1)

                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        .opacity(peeled ? 0 : 1)

                    StickerImage(item: item, width: item.fittedWidth(in: CGSize(width: 96, height: 88)))
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                        .rotationEffect(.degrees(peeled ? -4 : 12))
                        .scaleEffect(peeled ? 1 : 0.7)
                        .opacity(peeled ? 1 : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 22)
                }

                if sweepVisible {
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 26)
                        .blendMode(.plusLighter)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .offset(y: sweep * Self.height - 13)
                }

                Text(vibe.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(peeled ? Theme.ink : .white)
                    .shadow(color: .black.opacity(peeled ? 0 : 0.4), radius: 3)
                    .padding(12)
            }
            .frame(height: Self.height)
            .clipShape(.rect(cornerRadius: 20))
            // scaledToFill photos overflow the tile vertically; clipping hides that but doesn't
            // stop the overflow from taking taps meant for the neighbouring tile.
            .contentShape(.rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(peeled ? Theme.ink : Theme.line, lineWidth: peeled ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.ink, in: Circle())
                    .padding(10)
                    .scaleEffect(peeled ? 1 : 0.3)
                    .opacity(peeled ? 1 : 0)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(vibe.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onChange(of: isOn) { _, on in on ? peel() : unpeel() }
        .onDisappear { peelTask?.cancel() }
    }

    private func peel() {
        peelTask?.cancel()
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.25)) { peeled = true }
            return
        }
        sweep = -0.2
        sweepVisible = true
        withAnimation(.easeInOut(duration: 0.55)) { sweep = 1.15 }
        peelTask = Task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0.45)) { peeled = true }
            try? await Task.sleep(for: .seconds(0.3))
            sweepVisible = false
        }
    }

    private func unpeel() {
        peelTask?.cancel()
        sweepVisible = false
        withAnimation(.easeOut(duration: 0.3)) { peeled = false }
    }
}
