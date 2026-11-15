import PhotosUI
import SwiftUI

/// Real scan. The viewfinder is the live back camera (or a photo from the library); the shot
/// is analysed on-device by `ClothingAnalyzer`, the piece lifts off as a sticker, she can fix
/// its name and category, and "Add to closet" saves it to the shared `PieceLibrary`.
///
/// In onboarding (`requiresOutfit`) the finish button only turns on once there's enough for
/// one outfit; from the closet she can finish whenever she likes.
struct ScanView: View {
    var finishTitle = "Done"
    var requiresOutfit = false
    let onFinish: () -> Void

    private enum Phase { case aiming, analyzing, lifted, tagged, notFound, adding }

    @Environment(ClosetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraController()
    @State private var phase: Phase = .aiming
    @State private var photo: UIImage?
    @State private var piece: DetectedPiece?
    @State private var name = ""
    /// The name the app filled in, so a category change only renames a name she hasn't edited.
    @State private var autoName = ""
    @State private var category: ClosetCategory = .tops
    @State private var added: [ClosetItem] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var sweep: CGFloat = 0
    @State private var saveError: String?
    @State private var liftCount = 0
    @State private var shutterCount = 0

    /// Portrait 3:4, the shape of a photo from the back camera.
    private let viewportAspect: CGFloat = 0.75

    private var canFinish: Bool { requiresOutfit ? store.canStyle : true }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                viewport(in: geo.size)
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
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: category) { _, newCategory in
            // Rename only while she hasn't typed her own name: "Grey piece" → "Grey bottoms".
            guard let piece, name == autoName else { return }
            name = "\(piece.color) \(newCategory.noun)"
            autoName = name
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let image = UIImage(data: data) { analyze(image) }
            }
        }
        .alert("Couldn't save that piece",
               isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if requiresOutfit {
                Color.clear.frame(width: 40, height: 40)
            } else {
                Button(action: onFinish) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            Spacer()
            Text(added.isEmpty ? "Scan a piece" : "\(added.count) added")
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
            ForEach(Array(added.suffix(3).enumerated()), id: \.element.id) { offset, piece in
                piece.cutoutImage
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
        let width = min(available.width - 40, available.height * 0.94 * viewportAspect)
        let height = width / viewportAspect
        let lifted = phase == .lifted || phase == .tagged || phase == .adding

        return ZStack {
            Color(white: 0.09)

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .opacity(lifted ? 0 : 1)
            } else {
                cameraLayer
            }

            // The background dims while it's being read, and stays dim behind the lifted piece.
            Color.black.opacity(phase == .aiming ? 0 : (phase == .notFound ? 0.5 : 0.62))

            if phase == .analyzing {
                LinearGradient(colors: [.clear, .white.opacity(0.55), .white, .white.opacity(0.55), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 26)
                    .blur(radius: 3)
                    .blendMode(.plusLighter)
                    .position(x: width / 2, y: sweep * height)
            }

            if let piece {
                Image(uiImage: piece.sticker)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: width * 0.78, maxHeight: height * 0.78)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
                    .scaleEffect(phase == .adding ? 0.15 : (lifted ? 1 : 0.7))
                    .rotationEffect(.degrees(lifted ? -3 : 0))
                    .offset(phase == .adding ? CGSize(width: width / 2, height: -height / 2 - 40) : .zero)
                    .opacity(lifted ? (phase == .adding ? 0 : 1) : 0)
            }

            if phase == .notFound {
                Image(systemName: "eye.slash")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if phase == .aiming && camera.status == .running {
                ViewfinderCorners()
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 30))
    }

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.status {
        case .running:
            CameraPreview(session: camera.capture.session)
        case .starting:
            ProgressView().tint(.white)
        case .denied:
            cameraMessage(icon: "camera.fill", title: "Camera is off",
                          body: "Allow camera access in Settings to scan, or pick a photo instead.",
                          showSettings: true)
        case .unavailable:
            cameraMessage(icon: "photo.on.rectangle", title: "No camera here",
                          body: "Pick a photo of a piece laid flat instead.", showSettings: false)
        }
    }

    private func cameraMessage(icon: String, title: String, body: String, showSettings: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
            Text(title)
                .font(.display(24))
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.14), in: Capsule())
                    .padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 16) {
            switch phase {
            case .aiming:
                aimingPanel
            case .analyzing:
                Text("Lifting it off the background…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                captureRow.disabled(true).opacity(0.4)
            case .lifted, .tagged, .adding:
                tagPanel
            case .notFound:
                notFoundPanel
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 20)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private var aimingPanel: some View {
        VStack(spacing: 16) {
            Text(hint)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            captureRow
            if canFinish && (requiresOutfit || !added.isEmpty) {
                Button(finishTitle, action: onFinish)
                    .buttonStyle(PrimaryButtonStyle(fill: .white, text: .black))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: canFinish)
    }

    private var hint: String {
        if requiresOutfit, let next = LookStylist.nextNeeded(store.items) {
            return added.isEmpty ? "Lay one piece flat in good light. Start with \(next)." : "Nice. Now scan \(next)."
        }
        if requiresOutfit && !added.isEmpty { return "Add shoes, a bag or more pieces, or style your looks." }
        return "Lay one piece flat in good light"
    }

    private var captureRow: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .accessibilityLabel("Choose a photo")
            Spacer()
            Button(action: capture) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(.white).frame(width: 64, height: 64)
                }
            }
            .buttonStyle(ShutterButtonStyle())
            .disabled(camera.status != .running)
            .opacity(camera.status == .running ? 1 : 0.35)
            .accessibilityLabel("Take photo")
            Spacer()
            Color.clear.frame(width: 52, height: 52)
        }
        .padding(.horizontal, 12)
    }

    private var tagPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $name)
                .font(.display(28))
                .foregroundStyle(.white)
                .submitLabel(.done)
            HStack(spacing: 8) {
                Menu {
                    Picker("Category", selection: $category) {
                        ForEach(ClosetCategory.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(category.title)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .tagChip()
                }
                if let piece { Text(piece.color).tagChip() }
            }
            .opacity(phase == .lifted ? 0 : 1)
            .offset(y: phase == .lifted ? 8 : 0)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button("Retake", action: reset)
                    .buttonStyle(PrimaryButtonStyle(fill: .white.opacity(0.14), text: .white))
                    .frame(width: 120)
                Button(action: addToCloset) {
                    Label("Add to closet", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(fill: .white, text: .black))
            }
            .disabled(phase != .tagged)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notFoundPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't find a piece")
                .font(.display(28))
                .foregroundStyle(.white)
            Text("Lay it flat on a plain surface with the whole piece in frame.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Button("Try again", action: reset)
                .buttonStyle(PrimaryButtonStyle(fill: .white, text: .black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sequence

    private func capture() {
        shutterCount += 1
        Task {
            guard let image = await camera.takePhoto() else { return }
            analyze(image)
        }
    }

    private func analyze(_ image: UIImage) {
        photo = image
        piece = nil
        sweep = 0
        withAnimation(.easeOut(duration: 0.25)) { phase = .analyzing }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = 1 }
        Task {
            async let analysis = ClothingAnalyzer.analyze(image, polish: true)
            // Let the sweep play at least once, even when analysis is quick.
            try? await Task.sleep(for: .seconds(1.3))
            let result = await analysis
            guard photo === image else { return }
            // A plain rectangle crop isn't a scanned piece, so a failed lift counts as nothing found.
            // The Simulator can't lift subjects at all, so there the crop is let through for testing.
            #if targetEnvironment(simulator)
            let usable = true
            #else
            let usable = result.lifted
            #endif
            guard usable, let best = result.clothing.first ?? result.other.first else {
                withAnimation(.easeInOut(duration: 0.3)) { phase = .notFound }
                return
            }
            piece = best
            name = best.name
            autoName = best.name
            category = ClosetCategory(rawValue: best.category) ?? .tops
            liftCount += 1
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { phase = .lifted }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation { phase = .tagged }
        }
    }

    private func addToCloset() {
        guard let piece else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = SavedPiece(id: UUID().uuidString, name: trimmed.isEmpty ? piece.name : trimmed,
                               category: category.rawValue, color: piece.color, isWishlist: false,
                               addedAt: .now, cutoutAspect: piece.cutoutAspect, source: "camera")
        do {
            try PieceLibrary.add(saved, cutout: piece.cutout, sticker: piece.sticker)
        } catch {
            saveError = error.localizedDescription
            return
        }
        store.reloadSaved()
        withAnimation(.easeIn(duration: 0.45)) { phase = .adding }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.spring(duration: 0.4)) { added.append(ClosetItem(saved: saved)) }
            try? await Task.sleep(for: .seconds(0.2))
            reset()
        }
    }

    private func reset() {
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            photo = nil
            piece = nil
            sweep = 0
            phase = .aiming
        }
    }
}

extension ClosetCategory {
    /// Lower-case noun for an auto name, e.g. "Grey bottoms".
    var noun: String {
        switch self {
        case .tops: "top"
        case .outerwear: "jacket"
        case .bottoms: "bottoms"
        case .dresses: "dress"
        case .shoes: "shoes"
        case .bags: "bag"
        }
    }
}

private extension View {
    func tagChip() -> some View {
        font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.14), in: Capsule())
            .foregroundStyle(.white)
    }
}

struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Four corner brackets that breathe while waiting for the shot.
struct ViewfinderCorners: View {
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
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
