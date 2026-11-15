import SwiftUI

/// Try-on onboarding, two screens: the demo video, then her full-length photo. The video card
/// morphs into the photo frame between them, so it reads as one continuous step.
struct TryOnFlowView: View {
    let onDone: () -> Void

    private enum Step { case intro, photo }

    @State private var step: Step = .intro
    @Namespace private var frame

    var body: some View {
        ZStack {
            switch step {
            case .intro:
                TryOnIntroView(frame: frame) {
                    withAnimation(.spring(duration: 0.6, bounce: 0.15)) { step = .photo }
                }
                .transition(.opacity)
            case .photo:
                TryOnPhotoView(frame: frame, onDone: onDone)
                    .transition(.opacity)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// "Try your closet on you": the looping demo (her photo becomes a model, she picks pieces, they
/// go on), with a taped caption and step row that follow the video.
struct TryOnIntroView: View {
    let frame: Namespace.ID
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var time: Double = 0
    @State private var appeared = false

    /// Where each part of the video starts, in seconds (see Resources/TryOnDemo.mp4).
    private static let phases: [(start: Double, caption: String)] = [
        (0, "your photo"), (3.2, "your model"), (6.0, "pick a piece"), (12.5, "on you ♡"),
    ]
    private static let duration: Double = 21
    private static let steps = ["Add your photo", "Pick a piece", "See it on you"]

    private static let videoURL = Bundle.main.url(forResource: "TryOnDemo", withExtension: "mp4")

    private var phase: Int { Self.phases.lastIndex { time >= $0.start } ?? 0 }
    private var activeStep: Int { phase <= 1 ? 0 : phase - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Try your closet on you")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 32)
                .entrance(appeared, delay: 0, reduceMotion: reduceMotion)
            Text("Add one photo of you and see every piece you own on you, before you get dressed.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .entrance(appeared, delay: 0.06, reduceMotion: reduceMotion)

            videoCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(duration: 0.7, bounce: 0.2).delay(0.12), value: appeared)

            stepRow
                .padding(.top, 18)
                .entrance(appeared, delay: 0.22, reduceMotion: reduceMotion)

            Button("Try it with my photo", action: onContinue)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 22)
                .padding(.bottom, 8)
                .entrance(appeared, delay: 0.28, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, Theme.screenPadding)
        .onAppear { appeared = true }
    }

    private var videoCard: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(Theme.card)
            .overlay {
                if let url = Self.videoURL {
                    LoopingVideo(url: url) { time = $0 }
                }
            }
            .overlay(alignment: .top) { progressBar.padding(14) }
            .overlay(alignment: .bottom) {
                // The trailing no-break space leaves room for Caveat's last letter, which overhangs
                // its box and gets clipped otherwise ("your model" lost half its "l").
                TapeLabel(text: Self.phases[phase].caption + "\u{00A0}", size: 24)
                    .id(phase)
                    .transition(.asymmetric(insertion: .tapeSlap, removal: .opacity))
                    .padding(.bottom, 22)
            }
            .animation(.spring(duration: 0.45, bounce: 0.45), value: phase)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
            .aspectRatio(9 / 16, contentMode: .fit)
            .matchedGeometryEffect(id: "tryOnFrame", in: frame)
            .shadow(color: .black.opacity(0.10), radius: 22, y: 10)
            .accessibilityElement()
            .accessibilityLabel("Demo: a full-length photo turns into a model, then outfits from the closet are tried on it.")
    }

    /// Story-style bar showing how far through the loop the video is.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                Capsule().fill(.white)
                    .frame(width: geo.size.width * min(1, time / Self.duration))
            }
        }
        .frame(height: 3)
        .animation(.linear(duration: 0.1), value: time)
    }

    private var stepRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, title in
                let isActive = index == activeStep
                VStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isActive ? .white : Theme.ink)
                        .frame(width: 28, height: 28)
                        .background(isActive ? Theme.ink : Theme.card, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: isActive ? 0 : 1))
                        .scaleEffect(isActive ? 1.08 : 1)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.ink : Theme.inkSoft)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: activeStep)
    }
}

extension View {
    /// Fades and lifts a view into place when `appeared` turns true, staggered by `delay`.
    func entrance(_ appeared: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 14)
            .animation(.spring(duration: 0.6, bounce: 0.15).delay(delay), value: appeared)
    }
}

#Preview {
    TryOnFlowView {}
}
