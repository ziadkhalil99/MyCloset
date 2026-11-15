import SwiftUI

/// How-to sheet for the selfie step: what a good one looks like and what doesn't work.
/// Shown the first time she lands on "First, a selfie", and again from the info button
/// next to the placeholder. Capture lives on that first screen, not here.
/// The "don't" examples are the good example made too dark, blurry, too far away and
/// covered, so the difference is easy to see.
struct SelfieTipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let example = UIImage(named: "SelfieExample.jpg")

    private enum Mistake: CaseIterable {
        case dark, blurry, far, covered

        var title: String {
            switch self {
            case .dark: "Too dark"
            case .blurry: "Blurry"
            case .far: "Too far"
            case .covered: "Covered"
            }
        }
    }

    private static let tips: [(icon: String, text: String)] = [
        ("faceid", "Face the camera, eyes open"),
        ("sun.max", "Bright, even light"),
        ("person", "Just you, no sunglasses or hat"),
        ("camera.filters", "No filters or effects"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Take the right selfie")
                    .font(.display(26))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 28)
                Text("We use it to find you in your outfit photos, so only your clothes go in your closet.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                goodExample
                    .padding(.top, 22)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(Mistake.allCases, id: \.self) { mistake in
                        badExample(mistake).frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.tips, id: \.text) { tip in
                        HStack(spacing: 12) {
                            Image(systemName: tip.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 32, height: 32)
                                .background(Theme.card, in: Circle())
                            Text(tip.text)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 22)
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Got it") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.paper)
        }
        .background(Theme.paper)
    }

    // MARK: - Examples

    private var goodExample: some View {
        VStack(spacing: 10) {
            face(size: 132)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.success, lineWidth: 3))
                .overlay(alignment: .bottomTrailing) {
                    badge(systemName: "checkmark", fill: Theme.success, size: 32)
                }
            Text("Like this")
                .font(.hand(20))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Good example: a clear, well-lit photo of just your face")
    }

    private func badExample(_ mistake: Mistake) -> some View {
        VStack(spacing: 6) {
            Group {
                switch mistake {
                case .dark:
                    face(size: 64).brightness(-0.45)
                case .blurry:
                    face(size: 64).blur(radius: 4)
                case .far:
                    face(size: 22)
                        .clipShape(Circle())
                        .frame(width: 64, height: 64)
                        .background(Color(white: 0.82))
                case .covered:
                    face(size: 64)
                        .overlay(alignment: .center) {
                            Capsule()
                                .fill(.black)
                                .frame(width: 44, height: 12)
                                .offset(y: -6)
                        }
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                badge(systemName: "xmark", fill: Theme.accent, size: 22)
            }
            Text(mistake.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avoid: \(mistake.title)")
    }

    @ViewBuilder
    private func face(size: CGFloat) -> some View {
        if let example = Self.example {
            Image(uiImage: example)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func badge(systemName: String, fill: Color, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2))
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        SelfieTipsSheet()
            .presentationDetents([.large])
    }
}
