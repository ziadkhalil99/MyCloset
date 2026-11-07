import SwiftUI

/// Screen 11: face-down looks are dealt, then the first one flips face-up. The rest wait
/// behind "Unlock my looks".
struct RevealView: View {
    let onUnlock: () -> Void

    @Environment(ClosetStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dealt = false
    @State private var flipped = false
    @State private var showFooter = false

    var body: some View {
        let looks = store.lookBook.looks
        let name = store.profile.trimmedName
        VStack(spacing: 0) {
            Text(name.isEmpty ? "Your closet\nmakes \(looks.count) looks" : "\(name), your closet\nmakes \(looks.count) looks")
                .font(.display(34))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    FaceDownCard()
                        .frame(width: 236, height: 302)
                        .rotationEffect(.degrees(dealt ? (index == 0 ? 8 : -6) : (index == 0 ? 30 : -30)))
                        .offset(x: index == 0 ? 34 : -30, y: dealt ? 0 : 640)
                        .animation(.spring(duration: 0.7, bounce: 0.2).delay(0.15 + Double(index) * 0.15), value: dealt)
                }
                if let first = looks.first {
                    LookCanvas(look: first, animateIn: false)
                        .frame(width: 248, height: 318)
                        .shadow(color: .black.opacity(0.16), radius: 20, y: 12)
                        .rotation3DEffect(.degrees(flipped || reduceMotion ? 0 : 90), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .opacity(flipped ? 1 : 0)
                        .rotationEffect(.degrees(-2))
                }
            }
            .frame(maxHeight: .infinity)

            Label("\(max(looks.count - 1, 0)) more looks are ready", systemImage: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .opacity(showFooter ? 1 : 0)
                .offset(y: showFooter ? 0 : 10)

            Button("Unlock my looks", action: onUnlock)
                .buttonStyle(PrimaryButtonStyle())
                .opacity(showFooter ? 1 : 0)
                .padding(.top, 24)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Theme.screenPadding)
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: flipped)
        .task {
            dealt = true
            try? await Task.sleep(for: .seconds(0.95))
            withAnimation(.spring(duration: 0.55, bounce: 0.3)) { flipped = true }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeOut(duration: 0.4)) { showFooter = true }
        }
    }
}

private struct FaceDownCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius)
            .fill(Theme.ink)
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.paper)
            }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .accessibilityHidden(true)
    }
}
