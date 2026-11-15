import PhotosUI
import SwiftUI

/// "Now, a photo of you": she picks one full-length photo of herself. We show an example of the
/// shot we want, sweep a light over hers while we check it's head to toe, then save it on this
/// iPhone as the base for try-on. She can skip and add it later.
struct TryOnPhotoView: View {
    let frame: Namespace.ID
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var check: TryOnPhoto.Check?
    @State private var isChecking = false
    @State private var saveFailed = false
    @State private var appeared = false

    private static let tips = ["Head to toe", "Facing forward", "Good light"]
    private static let example = UIImage(named: "TryOnExample.jpg")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Not now", action: onDone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 44)
            }

            Text("Now, a photo of you")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .entrance(appeared, delay: 0.05, reduceMotion: reduceMotion)
            Text("Stand straight with your whole body in frame. We'll turn it into your model and dress it in your closet.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .entrance(appeared, delay: 0.1, reduceMotion: reduceMotion)

            photoFrame
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 18)

            statusRow
                .frame(minHeight: 34)
                .entrance(appeared, delay: 0.2, reduceMotion: reduceMotion)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
                Text("Your photo stays private and is only used to create your try-on looks.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            .entrance(appeared, delay: 0.24, reduceMotion: reduceMotion)

            buttons
                .padding(.top, 16)
                .padding(.bottom, 8)
                .entrance(appeared, delay: 0.28, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, Theme.screenPadding)
        .onAppear { appeared = true }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .sensoryFeedback(trigger: check) { _, new in
            guard let new else { return nil }
            return new.isGood ? .success : .warning
        }
        .alert("Couldn't save your photo", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again, or choose another photo.")
        }
    }

    // MARK: - Frame

    private var photoFrame: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .fill(Theme.card)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity.combined(with: .scale(scale: 1.06)))
                        .id(ObjectIdentifier(photo))
                } else if let example = Self.example {
                    Image(uiImage: example)
                        .resizable()
                        .scaledToFill()
                        .overlay(Theme.card.opacity(0.35))
                        .transition(.opacity)
                }
            }
            .overlay {
                if isChecking { ScanSweep(reduceMotion: reduceMotion) }
            }
            .overlay(alignment: .topLeading) {
                if photo == nil {
                    Text("Example")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.9), in: Capsule())
                        .padding(12)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(photo == nil ? Theme.inkSoft.opacity(0.5) : Theme.line,
                                  style: StrokeStyle(lineWidth: 1.5, dash: photo == nil ? [7, 6] : []))
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .matchedGeometryEffect(id: "tryOnFrame", in: frame)
            .shadow(color: .black.opacity(0.10), radius: 22, y: 10)
            .animation(.spring(duration: 0.5, bounce: 0.2), value: photo)
            .animation(.easeInOut(duration: 0.25), value: isChecking)
            .accessibilityElement()
            .accessibilityLabel(photo == nil ? "Example of a full-length photo" : "Your photo")
    }

    // MARK: - Status and buttons

    @ViewBuilder
    private var statusRow: some View {
        Group {
            if isChecking {
                Label("Checking your photo…", systemImage: "sparkles")
                    .foregroundStyle(Theme.inkSoft)
            } else if let check {
                Label(check.message, systemImage: check.isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(check.isGood ? Theme.ink : Theme.accent)
            } else {
                HStack(spacing: 14) {
                    ForEach(Self.tips, id: \.self) { tip in
                        Label(tip, systemImage: "checkmark")
                            .labelStyle(TightLabelStyle())
                    }
                }
                .foregroundStyle(Theme.inkSoft)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .transition(.opacity.combined(with: .offset(y: 6)))
        .animation(.easeInOut(duration: 0.25), value: isChecking)
        .animation(.easeInOut(duration: 0.25), value: check)
    }

    @ViewBuilder
    private var buttons: some View {
        if photo == nil {
            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                Text("Choose a photo")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            VStack(spacing: 4) {
                Button("Use this photo", action: usePhoto)
                    .buttonStyle(PrimaryButtonStyle(fill: isChecking ? Theme.inkSoft.opacity(0.4) : Theme.ink))
                    .disabled(isChecking)
                PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                    Text("Choose another")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(minHeight: 44)
                }
                .disabled(isChecking)
            }
        }
    }

    // MARK: - Actions

    private func load(_ item: PhotosPickerItem) async {
        defer { selection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            if photo == nil { check = .noPerson }
            return
        }
        check = nil
        photo = image
        isChecking = true
        // Let the sweep run at least once, so the check reads as something happening.
        async let result = TryOnPhoto.check(image)
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 1.4))
        let found = await result
        guard photo === image else { return }
        isChecking = false
        check = found
    }

    private func usePhoto() {
        guard let photo else { return }
        do {
            try TryOnPhoto.save(photo)
            onDone()
        } catch {
            saveFailed = true
        }
    }
}

/// A band of light that sweeps down the photo while it's being checked.
private struct ScanSweep: View {
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18)
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .white, .white.opacity(0.55), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 34)
                        .blendMode(.plusLighter)
                        .offset(y: -17 + t * (geo.size.height + 34))
                }
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .bold))
            configuration.title
        }
    }
}
