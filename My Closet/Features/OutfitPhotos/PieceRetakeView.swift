import PhotosUI
import SwiftUI

/// Swaps one piece found in her outfit photos for a proper photo of it, scanned the same way as
/// the camera scan: lay it flat, snap it (or pick a photo), and the piece lifts off its
/// background. The new cutout keeps the shelf she put the piece on.
struct PieceRetakeView: View {
    let category: ClosetCategory
    let current: UIImage
    let onUse: (DetectedPiece) -> Void

    private enum Phase: Equatable { case aiming, analyzing, found, notFound }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera = CameraController()
    @State private var phase: Phase = .aiming
    @State private var photo: UIImage?
    @State private var piece: DetectedPiece?
    @State private var pickerItem: PhotosPickerItem?
    @State private var sweep: CGFloat = 0
    @State private var shutterCount = 0
    @State private var liftCount = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            viewport
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
            bottomPanel
                .frame(height: 190)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterCount)
        .sensoryFeedback(.success, trigger: liftCount)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                if let data, let image = UIImage(data: data) { analyze(image) }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minHeight: 44)
            Spacer()
            Image(uiImage: current)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .padding(4)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("The piece you're replacing")
        }
        .overlay {
            Text("Better photo of your \(category.noun)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Viewport

    private var viewport: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height * 0.75)
            let height = width / 0.75
            ZStack {
                Color(white: 0.09)
                if let photo, phase != .aiming {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                        .opacity(phase == .found ? 0.25 : 0.8)
                        .blur(radius: phase == .found ? 8 : 0)
                } else {
                    cameraLayer
                }
                if phase == .analyzing {
                    LinearGradient(colors: [.clear, .white.opacity(0.5), .white, .white.opacity(0.5), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 30)
                        .blendMode(.plusLighter)
                        .offset(y: (sweep - 0.5) * height)
                }
                if phase == .found, let piece {
                    Image(uiImage: piece.sticker)
                        .resizable()
                        .scaledToFit()
                        .padding(36)
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if phase == .aiming && camera.status == .running {
                    ViewfinderCorners()
                }
            }
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 30))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.status {
        case .running:
            CameraPreview(session: camera.capture.session)
        case .starting:
            ProgressView().tint(.white)
        case .denied:
            message(icon: "camera.fill", title: "Camera is off",
                    body: "Allow camera access in Settings, or pick a photo instead.", showSettings: true)
        case .unavailable:
            message(icon: "photo.on.rectangle", title: "No camera here",
                    body: "Pick a photo of the piece laid flat instead.", showSettings: false)
        }
    }

    private func message(icon: String, title: String, body: String, showSettings: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28, weight: .semibold))
            Text(title).font(.display(22))
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
            }
        }
        .foregroundStyle(.white)
        .padding(28)
    }

    // MARK: - Bottom panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            switch phase {
            case .aiming:
                Text("Lay it flat in good light, the whole piece in frame")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                captureRow
            case .analyzing:
                Text("Lifting it off the background…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            case .found:
                Button("Use this photo") {
                    if let piece { onUse(piece) }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(fill: .white, text: Theme.ink))
                Button("Try again", action: retry)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minHeight: 44)
            case .notFound:
                Text("Couldn't find a piece in that photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Button("Try again", action: retry)
                    .buttonStyle(PrimaryButtonStyle(fill: .white, text: Theme.ink))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.25), value: phase)
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

    // MARK: - Actions

    private func capture() {
        shutterCount += 1
        Task {
            guard let image = await camera.takePhoto() else { return }
            analyze(image)
        }
    }

    private func retry() {
        photo = nil
        piece = nil
        withAnimation { phase = .aiming }
    }

    private func analyze(_ image: UIImage) {
        photo = image
        piece = nil
        sweep = 0
        withAnimation(.easeOut(duration: 0.25)) { phase = .analyzing }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = 1 }
        Task {
            async let analysis = ClothingAnalyzer.analyze(image, polish: true)
            try? await Task.sleep(for: .seconds(1.2))
            let result = await analysis
            guard photo === image else { return }
            // The Simulator can't lift subjects, so there the plain crop is let through for testing.
            #if targetEnvironment(simulator)
            let usable = true
            #else
            let usable = result.lifted
            #endif
            guard usable, var best = result.clothing.first ?? result.other.first else {
                withAnimation(.easeInOut(duration: 0.3)) { phase = .notFound }
                return
            }
            best.category = category.rawValue
            best.name = "\(best.color) \(category.noun)"
            piece = best
            liftCount += 1
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) { phase = .found }
        }
    }
}
