import SwiftUI

/// Screens 02–07 of the Figma flow. The progress bar and the sticker pile stay put while the
/// question below them slides; every answer drops a sticker onto the pile.
struct OnboardingQuestionsView: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable { case problem, reassurance, vibe, occasions, goal, name }

    @Environment(ClosetStore.self) private var store
    @State private var step: Step = .problem
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            OnboardingProgressBar(progress: CGFloat(step.rawValue + 1) / 7)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 14)

            if step != .reassurance {
                StickerPile(itemIDs: store.profile.pileItemIDs,
                            tapeLabel: step == .name && !store.profile.trimmedName.isEmpty ? "\(store.profile.trimmedName)'s closet \u{2661}" : nil)
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 6)
                    .transition(.opacity)
            }

            ZStack(alignment: .top) {
                content(for: step, profile: $store.profile)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, step == .reassurance ? 0 : 14)

            Button(continueTitle, action: advance)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.35)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 8)
        }
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.impact(flexibility: .soft), trigger: store.profile.pileItemIDs.count)
        .sensoryFeedback(.selection, trigger: store.profile.occasions)
    }

    // MARK: - Steps

    @ViewBuilder
    private func content(for step: Step, profile: Binding<OnboardingProfile>) -> some View {
        switch step {
        case .problem:
            question("How often do you have \u{201C}nothing to wear\u{201D}?") {
                VStack(spacing: 10) {
                    ForEach(OnboardingProfile.frequencies, id: \.self) { option in
                        OptionRow(title: option, isSelected: profile.wrappedValue.frequency == option) {
                            profile.wrappedValue.frequency = option
                        }
                    }
                }
            }
        case .reassurance:
            ReassuranceStep()
        case .vibe:
            question("Pick your vibe", subtitle: "Tap up to 3. Watch them come off the photo.") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 10) {
                    ForEach(Vibe.allCases) { vibe in
                        VibeTile(vibe: vibe, isOn: profile.wrappedValue.vibes.contains(vibe)) {
                            toggle(vibe, in: profile)
                        }
                    }
                }
            }
        case .occasions:
            question("Where are you getting dressed for?", subtitle: "Pick all that fit your week.") {
                FlowLayout {
                    ForEach(OnboardingProfile.occasionOptions, id: \.self) { option in
                        ChoiceChip(title: option, isSelected: profile.wrappedValue.occasions.contains(option)) {
                            if let index = profile.wrappedValue.occasions.firstIndex(of: option) {
                                profile.wrappedValue.occasions.remove(at: index)
                            } else {
                                profile.wrappedValue.occasions.append(option)
                            }
                        }
                    }
                }
            }
        case .goal:
            question("What would make your mornings better?") {
                VStack(spacing: 10) {
                    ForEach(OnboardingProfile.goals, id: \.self) { option in
                        OptionRow(title: option, isSelected: profile.wrappedValue.goal == option) {
                            profile.wrappedValue.goal = option
                        }
                    }
                }
            }
        case .name:
            question("Last thing: what should we call you?") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Your name", text: profile.name)
                        .font(.system(size: 20, weight: .medium))
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($nameFocused)
                        .onSubmit { if canContinue { advance() } }
                        .padding(.horizontal, 18)
                        .frame(height: 60)
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.ink, lineWidth: 2))
                        .tint(Theme.accent)
                    Text("Your closet will be called \u{201C}\(profile.wrappedValue.closetTitle.prefix(1).uppercased() + profile.wrappedValue.closetTitle.dropFirst())\u{201D}.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSoft)
                }
                .task {
                    try? await Task.sleep(for: .seconds(0.45))
                    nameFocused = true
                }
            }
        }
    }

    private func question<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 6)
            }
            content()
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Logic

    private var canContinue: Bool {
        let profile = store.profile
        switch step {
        case .problem: return profile.frequency != nil
        case .reassurance: return true
        case .vibe: return !profile.vibes.isEmpty
        case .occasions: return !profile.occasions.isEmpty
        case .goal: return profile.goal != nil
        case .name: return !profile.trimmedName.isEmpty
        }
    }

    private var continueTitle: String { step == .reassurance ? "Makes sense" : "Continue" }

    private func toggle(_ vibe: Vibe, in profile: Binding<OnboardingProfile>) {
        if let index = profile.wrappedValue.vibes.firstIndex(of: vibe) {
            profile.wrappedValue.vibes.remove(at: index)
        } else if profile.wrappedValue.vibes.count < OnboardingProfile.maxVibes {
            profile.wrappedValue.vibes.append(vibe)
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            nameFocused = false
            onFinish()
            return
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) { step = next }
    }
}

/// Screen 03: a big pile of her clothes drops in, one by one.
private struct ReassuranceStep: View {
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pile: [(id: String, x: CGFloat, y: CGFloat, w: CGFloat, rot: Double)] = [
        ("skirtBrown", 0.27, 236, 140, -10), ("hoodieBrown", 0.42, 120, 176, -6),
        ("jeansLight", 0.74, 190, 100, 9), ("cardiganCherry", 0.76, 58, 104, 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(pile.enumerated()), id: \.offset) { index, spot in
                        if let item = ClosetItem.item(id: spot.id) {
                            StickerImage(item: item, width: min(spot.w, item.fittedWidth(in: CGSize(width: spot.w, height: 190))))
                                .shadow(color: .black.opacity(0.14), radius: 10, y: 6)
                                .rotationEffect(.degrees(landed || reduceMotion ? spot.rot : spot.rot + (index.isMultiple(of: 2) ? 22 : -22)))
                                .scaleEffect(landed || reduceMotion ? 1 : 1.35)
                                .offset(y: landed || reduceMotion ? 0 : -110)
                                .opacity(landed ? 1 : 0)
                                .position(x: spot.x * geo.size.width, y: spot.y)
                                .animation(.spring(duration: 0.65, bounce: 0.4).delay(0.15 + Double(index) * 0.14), value: landed)
                        }
                    }
                }
            }
            .frame(height: 330)
            .padding(.top, 20)

            Text("It's not your closet.\nIt's the combos.")
                .font(.display(34))
                .foregroundStyle(Theme.ink)
            Text("Most of us reach for the same few pieces. We'll show you everything else they go with.")
                .font(.system(size: 17))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: landed)
        .onAppear { landed = true }
    }
}
