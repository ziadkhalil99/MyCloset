import SwiftUI

/// "Today's looks": a swipeable lookbook of flat-lay outfits made from her own closet.
struct LooksView: View {
    @Environment(ClosetStore.self) private var store
    @State private var currentID: String?
    @State private var wearCount = 0

    private var looks: [Look] { store.lookBook.looks }
    private var current: Look? { looks.first { $0.id == (currentID ?? looks.first?.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Theme.screenPadding)
                carousel
                    .padding(.top, 20)
                pageDots
                    .padding(.top, 14)
                if let current {
                    footer(for: current)
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.top, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: wearCount)
    }

    /// "Good morning, Sara" once onboarding has her name, otherwise "Today's looks".
    private var greeting: String {
        let name = store.profile.trimmedName
        guard !name.isEmpty else { return "Today's looks" }
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "morning" : (hour < 17 ? "afternoon" : "evening")
        return "Good \(part), \(name)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased() + "  ·  14°")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkSoft)
            Text(greeting)
                .font(.display(36))
                .foregroundStyle(Theme.ink)
            Text("\(looks.count) outfits from \(store.items.filter { !$0.isWishlist }.count) pieces you own")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.top, 12)
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 14) {
                ForEach(looks) { look in
                    LookCanvas(look: look)
                        .aspectRatio(store.lookBook.canvasAspect, contentMode: .fit)
                        // The container size already excludes the 32pt content margins.
                        .containerRelativeFrame(.horizontal)
                        .overlay(alignment: .bottomLeading) {
                            if store.wornLookID == look.id { wornStamp }
                        }
                        .shadow(color: Theme.ink.opacity(0.08), radius: 16, y: 8)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                        }
                        .id(look.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 32, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentID)
        .scrollIndicators(.hidden)
    }

    private var wornStamp: some View {
        Text("wearing today ♡")
            .font(.hand(19))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 2))
            .rotationEffect(.degrees(-6))
            .padding(18)
            .transition(.scale(scale: 1.6).combined(with: .opacity))
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(looks) { look in
                Capsule()
                    .fill(look.id == current?.id ? Theme.ink : Theme.line)
                    .frame(width: look.id == current?.id ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.3), value: current?.id)
    }

    private func footer(for look: Look) -> some View {
        let worn = store.wornLookID == look.id
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(look.items) { piece in
                    Image(piece.cutout)
                        .resizable()
                        .scaledToFit()
                        .padding(9)
                        .frame(width: 56, height: 56)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                        .accessibilityLabel(piece.name)
                }
                Spacer(minLength: 0)
                Text("\(look.items.count) pieces")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .id(look.id)
            .transition(.opacity)

            Button {
                withAnimation(.spring(duration: 0.45, bounce: 0.4)) {
                    store.wornLookID = worn ? nil : look.id
                }
                if !worn { wearCount += 1 }
            } label: {
                Label(worn ? "Wearing this today" : "Wear this",
                      systemImage: worn ? "checkmark" : "hanger")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PrimaryButtonStyle(fill: worn ? Theme.accent : Theme.ink))
        }
        .animation(.easeInOut(duration: 0.25), value: look.id)
    }
}

#Preview {
    LooksView()
        .environment(ClosetStore())
}
