import SwiftUI

/// Screen 10: "Styling Sara's closet…". Pieces fly onto an outfit card one by one, the look
/// counter ticks up and the checklist repeats her answers back, then it moves on by itself.
struct BuildingView: View {
    let onDone: () -> Void

    @Environment(ClosetStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = 0
    @State private var count = 0
    @State private var ticked = 0

    private var look: Look? { store.lookBook.looks.first }

    var body: some View {
        let profile = store.profile
        let checklist = ["Reading colours & fabrics",
                         "Matching your vibe: \(profile.vibeSummary)",
                         "Planning for \(profile.occasionSummary)"]
        VStack(spacing: 0) {
            Text("Styling \(profile.closetTitle)\u{2026}")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 36)

            if let look {
                AssemblingCard(look: look, landed: landed, aspect: store.lookBook.canvasAspect)
                    .frame(width: 250)
                    .padding(.top, 28)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(count)")
                    .font(.display(56))
                    .contentTransition(.numericText(value: Double(count)))
                Text("of \(store.lookBook.looks.count) looks")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            .foregroundStyle(Theme.ink)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(checklist.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(index < ticked ? Theme.ink : Theme.line, in: Circle())
                            .scaleEffect(index < ticked ? 1 : 0.85)
                        Text(line)
                            .font(.system(size: 15, weight: index < ticked ? .medium : .regular))
                            .foregroundStyle(index < ticked ? Theme.ink : Theme.inkSoft)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.screenPadding)
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.impact(flexibility: .soft), trigger: landed)
        .sensoryFeedback(.success, trigger: ticked == 3)
        .task { await run() }
    }

    private func run() async {
        let total = store.lookBook.looks.count
        let pieces = look?.pieces.count ?? 0
        for step in 0..<12 {
            try? await Task.sleep(for: .seconds(step == 0 ? 0.35 : 0.3))
            if Task.isCancelled { return }
            if step % 2 == 0, landed < pieces {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.3)) { landed += 1 }
            }
            if count < total { withAnimation(.snappy) { count += 1 } }
            if step == 3 || step == 7 || step == 10 {
                withAnimation(.spring(duration: 0.35, bounce: 0.5)) { ticked += 1 }
            }
        }
        try? await Task.sleep(for: .seconds(0.7))
        if !Task.isCancelled { onDone() }
    }
}

/// The first look's card with its pieces flying in from off-card, one per `landed` step.
private struct AssemblingCard: View {
    let look: Look
    let landed: Int
    let aspect: Double

    /// Where each piece starts, relative to its resting spot: x, y, extra clockwise rotation.
    private let starts: [(CGFloat, CGFloat, Double)] = [(-220, -40, -30), (230, 120, 28), (-210, 160, -26), (220, -90, 24)]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(Array(look.pieces.enumerated()), id: \.offset) { index, piece in
                    let start = starts[index % starts.count]
                    let isIn = index < landed
                    let cx = look.mirror ? 1 - piece.cx : piece.cx
                    let rot = look.mirror ? -piece.rot : piece.rot
                    Image(piece.item)
                        .resizable()
                        .scaledToFit()
                        .frame(width: piece.w * size.width)
                        .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
                        .rotationEffect(.degrees(rot + (isIn ? 0 : start.2)))
                        .position(x: cx * size.width + (isIn ? 0 : start.0), y: piece.cy * size.height + (isIn ? 0 : start.1))
                        .opacity(isIn ? 1 : 0)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .background(Color(hexString: look.floor), in: .rect(cornerRadius: Theme.cardRadius))
        .shadow(color: Theme.ink.opacity(0.08), radius: 16, y: 8)
    }
}
