import SwiftUI

/// The Figma flow, in order: Welcome → questions → how scanning works → scan → building →
/// reveal → paywall → the app. It always opens on Welcome so it can be recorded start to finish.
/// Each step replaces the last; there is no going back into onboarding.
struct RootView: View {
    private enum Stage { case welcome, questions, scanIntro, scan, building, reveal, paywall, main }

    @State private var store = ClosetStore()
    @State private var stage: Stage = Self.initialStage

    /// Debug builds launched with `-skipOnboarding` open straight on the closet,
    /// handy for checking pieces added from the share sheet.
    private static var initialStage: Stage {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-skipOnboarding") { return .main }
        #endif
        return .welcome
    }

    var body: some View {
        ZStack {
            switch stage {
            case .welcome:
                WelcomeView { go(.questions) }
            case .questions:
                OnboardingQuestionsView { go(.scanIntro) }
            case .scanIntro:
                ScanIntroView { go(.scan) }
            case .scan:
                ScanView(finishTitle: "Style my looks") { go(.building) }
            case .building:
                BuildingView { go(.reveal) }
            case .reveal:
                RevealView { go(.paywall) }
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
