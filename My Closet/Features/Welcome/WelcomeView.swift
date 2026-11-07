import SwiftUI

struct WelcomeView: View {
    let onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Sticker collage: centre and width as fractions of the collage area.
    private let collage: [(id: String, cx: CGFloat, cy: CGFloat, w: CGFloat, rot: Double)] = [
        ("dressDots", 0.50, 0.50, 0.25, -3),
        ("jacketBurgundy", 0.29, 0.27, 0.42, -9),
        ("cardiganCherry", 0.74, 0.24, 0.38, 7),
        ("bagDenim", 0.17, 0.70, 0.25, -13),
        ("sneakersSamba", 0.80, 0.68, 0.27, 11),
        ("bagHobo", 0.53, 0.88, 0.20, 4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(collage.enumerated()), id: \.offset) { index, spot in
                        if let item = ClosetItem.item(id: spot.id) {
                            StickerImage(item: item, width: spot.w * geo.size.width)
                                .shadow(color: .black.opacity(0.14), radius: 10, y: 6)
                                .rotationEffect(.degrees(appeared || reduceMotion ? spot.rot : spot.rot - 20))
                                .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
                                .opacity(appeared ? 1 : 0)
                                .position(x: spot.cx * geo.size.width,
                                          y: spot.cy * geo.size.height + (appeared || reduceMotion ? 0 : 60))
                                .animation(.spring(duration: 0.7, bounce: 0.35).delay(0.15 + Double(index) * 0.08),
                                           value: appeared)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("Your closet,\nstyled.")
                    .font(.display(46))
                    .foregroundStyle(Theme.ink)
                Text("Snap what you already own. We'll turn it into outfits you'll actually wear.")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.5).delay(0.55), value: appeared)

            Button(action: onStart) {
                Text("Get started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 28)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.75), value: appeared)

            Text("Takes about a minute")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.85), value: appeared)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 8)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { appeared = true }
    }
}

#Preview {
    WelcomeView {}
}
