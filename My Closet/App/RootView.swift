import SwiftUI

/// The flow, in order: Welcome → questions → her outfit photos (she picks them, keeps the pieces
/// that are hers) or, instead, how scanning works → camera scan → building → reveal → try-on
/// (the demo video, then her full-length photo) → paywall → the app.
/// Onboarding runs once; after that the app opens on Today.
/// Each step replaces the last; there is no going back into onboarding.
struct RootView: View {
    private enum Stage { case welcome, questions, outfitPhotos, scanIntro, scan, building, reveal, tryOn, paywall, main }

    // `stage` first: its initial value may reset the saved profile before the store loads it.
    @State private var stage: Stage = Self.initialStage
    @State private var store = ClosetStore()

    private static let completedKey = "onboarding.completed"

    /// Debug builds launched with `-skipOnboarding` open straight on the app, `-outfitPhotos` on
    /// the outfit photo picker, `-tryOn` on the try-on intro; `-resetOnboarding` forgets the finished onboarding and her answers so it
    /// runs again (scanned pieces stay).
    private static var initialStage: Stage {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: completedKey)
            OnboardingProfile.reset()
        }
        if arguments.contains("-skipOnboarding") { return .main }
        if arguments.contains("-outfitPhotos") { return .outfitPhotos }
        if arguments.contains("-tryOn") { return .tryOn }
        #endif
        return UserDefaults.standard.bool(forKey: completedKey) ? .main : .welcome
    }

    var body: some View {
        ZStack {
            switch stage {
            case .welcome:
                WelcomeView { go(.questions) }
            case .questions:
                OnboardingQuestionsView { go(.outfitPhotos) }
            case .outfitPhotos:
                OutfitPhotosView(onDone: { go(.building) }, onCamera: { go(.scanIntro) })
            case .scanIntro:
                ScanIntroView { go(.scan) }
            case .scan:
                ScanView(finishTitle: "Style my looks", requiresOutfit: true) { go(.building) }
            case .building:
                BuildingView { go(.reveal) }
            case .reveal:
                RevealView { go(.tryOn) }
            case .tryOn:
                TryOnFlowView { go(.paywall) }
            case .paywall:
                PaywallView { go(.main) }
            case .main:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .environment(store)
        .preferredColorScheme(.light)
        .tint(Theme.ink)
    }

    private func go(_ next: Stage) {
        if next == .main { UserDefaults.standard.set(true, forKey: Self.completedKey) }
        withAnimation(.easeInOut(duration: 0.4)) { stage = next }
    }
}

struct MainTabView: View {
    var body: some View {
        // `.tabItem` rather than `Tab` — the target deploys to iOS 17.6.
        TabView {
            LooksView()
                .tabItem { Label("Today", systemImage: "tshirt") }
            ClosetView()
                .tabItem { Label("Closet", systemImage: "hanger") }
        }
    }
}

#Preview {
    RootView()
}
