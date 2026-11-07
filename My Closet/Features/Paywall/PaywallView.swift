import SwiftUI

/// Screen 12. Demo only: no StoreKit, any button lets her in. Prices are placeholders and
/// there is no free trial. The billed amount is the most prominent price on each plan.
struct PaywallView: View {
    let onFinish: () -> Void

    private enum Plan { case yearly, weekly }

    @Environment(ClosetStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plan: Plan = .yearly
    @State private var appeared = false
    @State private var showClose = false
    @State private var purchased = false
    @State private var showWelcome = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LookWall(looks: store.lookBook.looks)
                    .frame(height: 290)
                    .padding(.horizontal, -Theme.screenPadding)

                TapeLabel(text: "\(store.profile.trimmedName.isEmpty ? "My" : store.profile.trimmedName + "'s") closet \u{2661}", size: 26)
                    .scaleEffect(appeared || reduceMotion ? 1 : 1.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(duration: 0.45, bounce: 0.45).delay(0.5), value: appeared)
                    .padding(.top, -22)

                headline
                    .padding(.top, 14)
                    .modifier(FadeUp(on: appeared, delay: 0.3))

                VStack(alignment: .leading, spacing: 10) {
                    benefit("cardiganCherry", "Fresh looks every morning", delay: 0.7)
                    benefit("sneakersSamba", "Unlimited scans", delay: 0.82)
                    benefit("bagDenim", "Plan the whole week ahead", delay: 0.94)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 20)

                VStack(spacing: 10) {
                    planCard(.yearly, title: "Yearly", subtitle: "Works out to $0.77 a week", price: "$39.99", period: "per year")
                        .overlay(alignment: .topTrailing) {
                            Text("BEST VALUE")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.accent, in: .rect(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white, lineWidth: 3).padding(-1.5))
                                .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                                .rotationEffect(.degrees(5))
                                .offset(x: -14, y: -12)
                                .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                                .opacity(appeared ? 1 : 0)
                                .animation(.spring(duration: 0.45, bounce: 0.5).delay(1.4), value: appeared)
                        }
                        .modifier(FadeUp(on: appeared, delay: 1.0))
                    planCard(.weekly, title: "Weekly", subtitle: "Cancel anytime", price: "$5.99", period: "per week")
                        .modifier(FadeUp(on: appeared, delay: 1.12))
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { footer }
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(.trailing, 16)
            .padding(.top, 8)
            .opacity(showClose ? 1 : 0)
            .allowsHitTesting(showClose)
        }
        .overlay { if purchased { StickerBurst() } }
        .overlay {
            if showWelcome {
                VStack(spacing: 6) {
                    Text(store.profile.trimmedName.isEmpty ? "Welcome in" : "Welcome in, \(store.profile.trimmedName)")
                        .font(.display(32))
                    Text("Your first look is ready")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
                .transition(.opacity)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: purchased)
        .sensoryFeedback(.selection, trigger: plan)
        .task {
            appeared = true
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.4)) { showClose = true }
        }
    }

    private var headline: some View {
        (Text("Get dressed in ").font(.display(30))
         + Text("minutes").font(.displayItalic(30)).foregroundColor(Theme.accent)
         + Text(",\nevery morning").font(.display(30)))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
    }

    private func benefit(_ itemID: String, _ text: String, delay: Double) -> some View {
        HStack(spacing: 12) {
            Image(itemID)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 36, height: 36)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
        .modifier(FadeUp(on: appeared, delay: delay))
    }

    private func planCard(_ value: Plan, title: String, subtitle: String, price: String, period: String) -> some View {
        let isOn = plan == value
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { plan = value }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(price).font(.system(size: 18, weight: .bold))
                    Text(period).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .frame(height: 64)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: isOn ? 2.5 : 1.5))
            .scaleEffect(isOn ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: purchase) {
                Text("Unlock my closet")
            }
            .buttonStyle(ShineButtonStyle(animated: !reduceMotion && !purchased))
            HStack(spacing: 6) {
                Text("Cancel anytime")
                Text("\u{00B7}")
                Button("Restore") {}
                Text("\u{00B7}")
                Button("Terms") {}
                Text("\u{00B7}")
                Button("Privacy") {}
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.inkSoft)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(Theme.paper)
    }

    private func purchase() {
        guard !purchased else { return }
        purchased = true
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeInOut(duration: 0.45)) { showWelcome = true }
            try? await Task.sleep(for: .seconds(1.5))
            onFinish()
        }
    }
}

private struct FadeUp: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 14)
            .animation(.easeOut(duration: 0.45).delay(delay), value: on)
    }
}

/// Two rows of her looks drifting in opposite directions.
private struct LookWall: View {
    let looks: [Look]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 10) {
                row(looks, t: t, speed: 22, leftward: true)
                row(looks.reversed(), t: t, speed: 18, leftward: false)
            }
            .padding(.top, 34)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.62), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }

    private func row(_ items: [Look], t: Double, speed: Double, leftward: Bool) -> some View {
        let pitch: CGFloat = 112
        let span = pitch * CGFloat(items.count)
        let travel = CGFloat((t * speed).truncatingRemainder(dividingBy: Double(span)))
        return HStack(spacing: 16) {
            ForEach(Array((items + items).enumerated()), id: \.offset) { index, look in
                LookCanvas(look: look, animateIn: false)
                    .frame(width: 96, height: 118)
                    .clipShape(.rect(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 5)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -3 : 3))
            }
        }
        .fixedSize()
        .drawingGroup()
        .offset(x: leftward ? -travel : travel - span)
        // minWidth: 0 is load-bearing: without it the frame reports the strip's full ~1,800pt
        // width and the whole paywall column grows past the screen edges.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .frame(height: 124)
    }
}

/// Black pill that breathes gently and has a light sweeping across it.
private struct ShineButtonStyle: ButtonStyle {
    let animated: Bool

    func makeBody(configuration: Configuration) -> some View {
        TimelineView(.animation(paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cycle = t.truncatingRemainder(dividingBy: 2.8)
            let shine = min(cycle / 0.9, 1)
            let breathe = animated ? 1 + 0.0125 * (1 - cos(t * 2 * .pi / 1.8)) : 1
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.ink)
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.4), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60)
                            .rotationEffect(.degrees(20))
                            .offset(x: -80 + (geo.size.width + 160) * shine)
                            .opacity(animated && cycle < 0.9 ? 1 : 0)
                    }
                }
                .clipShape(Capsule())
                .scaleEffect((configuration.isPressed ? 0.97 : 1) * breathe)
        }
    }
}

/// Her clothes burst out of the button as stickers when she unlocks.
private struct StickerBurst: View {
    private let ids = ["cardiganCherry", "sneakersSamba", "bagDenim", "dressDots", "jacketBurgundy",
                       "jeansLight", "hoodieBrown", "skirtBrown", "bagHobo", "shortsTan", "jacketBlack", "sneakers530"]
    @State private var fired = false

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height - 40)
            ZStack {
                ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                    if let item = ClosetItem.item(id: id) {
                        let angle = Double(index) / Double(ids.count) * 2 * .pi
                        let distance = 150 + Double((index * 37) % 90)
                        StickerImage(item: item, width: item.fittedWidth(in: CGSize(width: 70, height: 80)))
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                            .keyframeAnimator(initialValue: BurstFrame(), trigger: fired) { content, frame in
                                content
                                    .scaleEffect(frame.scale)
                                    .rotationEffect(.degrees(frame.rotation))
                                    .offset(frame.offset)
                                    .opacity(frame.opacity)
                            } keyframes: { _ in
                                KeyframeTrack(\.offset) {
                                    SpringKeyframe(CGSize(width: cos(angle) * distance, height: sin(angle) * distance - 180), duration: 0.8, spring: .bouncy)
                                    CubicKeyframe(CGSize(width: cos(angle) * distance, height: sin(angle) * distance + 60), duration: 0.6)
                                }
                                KeyframeTrack(\.scale) {
                                    SpringKeyframe(1.1, duration: 0.6)
                                    LinearKeyframe(1, duration: 0.8)
                                }
                                KeyframeTrack(\.rotation) {
                                    LinearKeyframe(Double((index * 53) % 120) - 60, duration: 1.4)
                                }
                                KeyframeTrack(\.opacity) {
                                    LinearKeyframe(1, duration: 0.9)
                                    LinearKeyframe(0, duration: 0.5)
                                }
                            }
                            .position(origin)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { fired = true }
    }
}

private struct BurstFrame {
    var offset: CGSize = .zero
    var scale: Double = 0.3
    var rotation: Double = 0
    var opacity: Double = 1
}
