import SwiftUI

/// Staged scan. Nothing is detected: each step plays the original photo, sweeps a light
/// band down it (the background dims behind the band while the piece stays lit), lifts the
/// piece off as a sticker, tags it, and drops it into the closet.
struct ScanView: View {
    var finishTitle = "See today's looks"
    let onFinish: () -> Void

    private enum Phase { case aiming, scanning, lifted, tagged, adding, done }

    @Environment(ClosetStore.self) private var store
    @State private var index = 0
    @State private var phase: Phase = .aiming
    @State private var sweep: CGFloat = 0
    @State private var added: [ClosetItem] = []
    @State private var liftCount = 0
    @State private var shutterCount = 0

    private let queue = ClosetItem.scanDemo
    private var item: ClosetItem { queue[index] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                ZStack {
                    if phase == .done {
                        doneCollage(in: geo.size)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        viewport(in: geo.size)
                            .id(item.id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            bottomPanel
                .frame(height: 230)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: liftCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterCount)
        .sensoryFeedback(.selection, trigger: added.count)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Close")
            Spacer()
            Text(phase == .done ? "All set" : "Scan \(index + 1) of \(queue.count)")
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.numericText())
            Spacer()
            addedTray
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
    }

    private var addedTray: some View {
        ZStack {
            ForEach(Array(added.enumerated()), id: \.element.id) { offset, piece in
                Image(piece.cutout)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(Double(offset) * 12 - 12))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 40, height: 40)
        .background(.white.opacity(added.isEmpty ? 0.06 : 0.12), in: Circle())
        .overlay(alignment: .topTrailing) {
            if !added.isEmpty {
                Text("\(added.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 18, height: 18)
                    .background(.white, in: Circle())
                    .offset(x: 4, y: -4)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityLabel("\(added.count) pieces added")
    }

    // MARK: - Viewport

    private func viewport(in available: CGSize) -> some View {
        let aspect = item.photoAspect
        let width = min(available.width - 40, available.height * 0.94 * aspect)
        let height = width / aspect
        let rect = item.cutoutRect
        let cutoutSize = CGSize(width: rect.width * width, height: rect.height * height)
        let cutoutCenter = CGPoint(x: (rect.minX + rect.width / 2) * width, y: (rect.minY + rect.height / 2) * height)
        let lifted = phase == .lifted || phase == .tagged || phase == .adding

        return ZStack(alignment: .topLeading) {
            Color(white: 0.09)

            // Original photo, fades out once the piece is lifted.
            Image(item.photo)
                .resizable()
                .frame(width: width, height: height)
                .opacity(lifted ? 0 : 1)

            // Background dims behind the sweep line while the piece stays lit.
            Color.black.opacity(0.62)
                .frame(width: width, height: height)
                .mask(alignment: .top) { Rectangle().frame(height: sweep * height) }
                .opacity(lifted ? 0 : 1)
            Image(item.cutout)
                .resizable()
                .frame(width: cutoutSize.width, height: cutoutSize.height)
                .position(cutoutCenter)
                .frame(width: width, height: height)
                .mask(alignment: .top) { Rectangle().frame(height: sweep * height) }
                .opacity(lifted ? 0 : 1)

            // Sweep band.
            if phase == .scanning {
                LinearGradient(colors: [.clear, .white.opacity(0.55), .white, .white.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 26)
                    .blur(radius: 3)
                    .blendMode(.plusLighter)
                    .offset(y: sweep * height - 13)
            }

            // The lifted sticker.
            StickerImage(item: item, width: cutoutSize.width)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
                .scaleEffect(phase == .adding ? 0.15 : (lifted ? 0.84 : 1))
                .rotationEffect(.degrees(lifted ? -3 : 0))
                .position(phase == .adding ? CGPoint(x: width - 10, y: -40) : cutoutCenter)
                .opacity(lifted ? (phase == .adding ? 0 : 1) : 0)

            ViewfinderCorners(pulsing: phase == .aiming)
                .frame(width: width, height: height)
                .opacity(lifted ? 0 : 1)
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 30))
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 18) {
            switch phase {
            case .aiming:
                Text("Lay it flat in good light")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                shutter
            case .scanning:
                Text("Lifting it off the background…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                shutter.disabled(true).opacity(0.4)
            case .lifted, .tagged, .adding:
                tagPanel
            case .done:
                donePanel
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 20)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private var shutter: some View {
        Button(action: capture) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(.white).frame(width: 64, height: 64)
            }
        }
        .buttonStyle(ShutterButtonStyle())
        .accessibilityLabel("Scan")
    }

    private var tagPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.name)
                .font(.display(30))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                ForEach(Array([item.category.title, item.color, item.material].enumerated()), id: \.offset) { offset, tag in
                    Text(tag)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                        .opacity(phase == .lifted ? 0 : 1)
                        .offset(y: phase == .lifted ? 8 : 0)
                        .animation(.spring(duration: 0.4).delay(Double(offset) * 0.08), value: phase)
                }
            }
            Spacer(minLength: 0)
            Button(action: addToCloset) {
                Label("Add to closet", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(fill: .white, text: .black))
            .disabled(phase != .tagged)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var donePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(added.count) pieces added")
                .font(.display(30))
                .foregroundStyle(.white)
            Text("Your closet has \(store.items.count) pieces. Ready to get dressed?")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Button(action: onFinish) {
                Text(finishTitle)
            }
            .buttonStyle(PrimaryButtonStyle(fill: .white, text: .black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doneCollage(in size: CGSize) -> some View {
        let base = min(size.width, size.height) * 0.42
        return ZStack {
            ForEach(Array(added.enumerated()), id: \.element.id) { offset, piece in
                let spread = CGFloat(offset) - CGFloat(added.count - 1) / 2
                StickerImage(item: piece, width: base)
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                    .rotationEffect(.degrees(Double(spread) * 12))
                    .offset(x: spread * base * 0.55, y: abs(spread) * 18)
            }
        }
    }

    // MARK: - Sequence

    private func capture() {
        shutterCount += 1
        sweep = 0
        withAnimation(.easeOut(duration: 0.2)) { phase = .scanning }
        withAnimation(.easeInOut(duration: 1.4)) { sweep = 1 }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            liftCount += 1
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { phase = .lifted }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation { phase = .tagged }
        }
    }

    private func addToCloset() {
        store.markAdded(item)
        withAnimation(.easeIn(duration: 0.45)) { phase = .adding }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.spring(duration: 0.4)) { added.append(item) }
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) {
                if index + 1 < queue.count {
                    index += 1
                    sweep = 0
                    phase = .aiming
                } else {
                    phase = .done
                }
            }
        }
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Four corner brackets that breathe while waiting for the shot.
private struct ViewfinderCorners: View {
    let pulsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = breathe ? 22 : 16
            let length: CGFloat = 30
            Path { path in
                let w = geo.size.width, h = geo.size.height
                for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0),
                                       (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)] {
                    path.move(to: CGPoint(x: x, y: y + dy * length))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + dx * length, y: y))
                }
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .shadow(color: .black.opacity(0.35), radius: 4)
        .onAppear {
            guard pulsing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
