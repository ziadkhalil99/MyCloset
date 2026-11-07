import SwiftUI

/// Screen 08: "Here's how scanning works". The video is an in-app loop built from her
/// cardigan photo: a light sweeps down, the background goes, the piece lifts off as a sticker.
struct ScanIntroView: View {
    let onStart: () -> Void

    @State private var activeStep = 0

    private let steps = ["Lay it flat", "Snap a photo", "We lift it off"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onStart)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 8)

            Text("Here's how scanning works")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("15 seconds. Then you try it.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .padding(.top, 6)

            ScanDemoPlayer(activeStep: $activeStep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 20)

            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    VStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(index == activeStep ? .white : Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(index == activeStep ? Theme.ink : Theme.card, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: index == activeStep ? 0 : 1))
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(index == activeStep ? Theme.ink : Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: activeStep)
            .padding(.top, 18)

            Button("Start scanning", action: onStart)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 24)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Theme.screenPadding)
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// A 4-second loop driven by the clock, so it never drifts and pauses cleanly.
private struct ScanDemoPlayer: View {
    @Binding var activeStep: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var pausedAt: Date?

    private static let loop: Double = 4
    private let item = ClosetItem.item(id: "cardiganCherry")!

    var body: some View {
        GeometryReader { geo in
            let aspect = item.photoAspect
            let width = min(geo.size.width, geo.size.height * aspect)
            let height = width / aspect
            TimelineView(.animation(paused: pausedAt != nil || reduceMotion)) { context in
                let t = time(at: context.date)
                frame(t: t, width: width, height: height)
                    .onChange(of: step(for: t)) { _, value in activeStep = value }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func time(at date: Date) -> Double {
        if reduceMotion { return 3.0 }
        let now = pausedAt ?? date
        return now.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.loop)
    }

    private func step(for t: Double) -> Int { t < 0.5 ? 0 : (t < 1.9 ? 1 : 2) }

    private func frame(t: Double, width: CGFloat, height: CGFloat) -> some View {
        let sweep = smooth(t / 1.8)
        let lift = smooth((t - 1.9) / 0.5)
        let rect = item.cutoutRect
        let cutoutSize = CGSize(width: rect.width * width, height: rect.height * height)
        let center = CGPoint(x: rect.midX * width, y: rect.midY * height)

        return ZStack(alignment: .topLeading) {
            Color(white: 0.09)
            Image(item.photo).resizable().frame(width: width, height: height).opacity(1 - lift)
            Color.black.opacity(0.58)
                .frame(width: width, height: height)
                .mask(alignment: .top) { Rectangle().frame(height: sweep * height) }
                .opacity(1 - lift)
            Image(item.cutout).resizable()
                .frame(width: cutoutSize.width, height: cutoutSize.height)
                .position(center)
                .frame(width: width, height: height)
                .mask(alignment: .top) { Rectangle().frame(height: sweep * height) }
                .opacity(1 - lift)
            if t < 1.85 {
                LinearGradient(colors: [.clear, .white.opacity(0.6), .white, .white.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 26)
                    .blendMode(.plusLighter)
                    .offset(y: sweep * height - 13)
            }
            StickerImage(item: item, width: cutoutSize.width)
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                .scaleEffect(1 - 0.16 * lift + 0.08 * sin(lift * .pi))
                .rotationEffect(.degrees(-3 * lift))
                .position(center)
                .opacity(lift)
            ViewfinderBrackets()
                .padding(18)
                .frame(width: width, height: height)
                .opacity(1 - lift)
            controls(t: t)
                .frame(width: width, height: height, alignment: .bottom)
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 28))
    }

    private func controls(t: Double) -> some View {
        HStack(spacing: 12) {
            Button {
                if let pausedAt {
                    start += Date.now.timeIntervalSince(pausedAt)
                    self.pausedAt = nil
                } else {
                    pausedAt = .now
                }
            } label: {
                Image(systemName: pausedAt == nil ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20)
            }
            .accessibilityLabel(pausedAt == nil ? "Pause" : "Play")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white).frame(width: geo.size.width * t / Self.loop)
                }
            }
            .frame(height: 4)
            Text(String(format: "0:%02d", Int(t / Self.loop * 15)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(14)
    }

    private func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

private struct ViewfinderBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, l: CGFloat = 30
            Path { path in
                for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] {
                    path.move(to: CGPoint(x: x, y: y + dy * l))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + dx * l, y: y))
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }
}
