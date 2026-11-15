import SwiftUI

/// "Reading your photos": the library scan running live. The outfit photo being read sits on
/// top (✕ takes its pieces back out), and each piece found lands on its shelf below.
struct PhotoScanView: View {
    /// Go on to styling; only offered once the closet has enough for a look.
    let onDone: () -> Void
    /// Switch to scanning pieces with the camera.
    let onCamera: () -> Void

    @Environment(ClosetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var scan = PhotoScanModel()

    var body: some View {
        VStack(spacing: 0) {
            if scan.phase == .denied {
                deniedMessage
            } else {
                header
                photoCard
                    .frame(height: 230)
                    .padding(.top, 20)
                shelves
                    .frame(maxHeight: .infinity)
                    .padding(.top, 20)
                footer
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 8)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            scan.start { store.reloadSaved() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings with access granted: start reading.
            if phase == .active && scan.phase == .denied { scan.start { store.reloadSaved() } }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            scan.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            ProgressView(value: scan.progress)
                .tint(Theme.ink)
                .padding(.top, 12)
                .padding(.bottom, 18)
            Text(scan.phase == .finished ? "Your closet is filling up" : "Reading your photos")
                .font(.display(28))
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
            Text(countLine)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSoft)
                .contentTransition(.numericText())
                .animation(.default, value: scan.scanned)
        }
    }

    private var countLine: String {
        let photos = "\(scan.scanned.formatted()) of \(scan.total.formatted()) photos"
        let outfits = scan.outfits == 1 ? "1 outfit" : "\(scan.outfits) outfits"
        return "\(photos) · \(outfits)"
    }

    // MARK: - Photo

    @ViewBuilder
    private var photoCard: some View {
        if let photo = scan.currentPhoto {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: 180, height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    // Only offered when this photo put pieces on the shelves; otherwise there's nothing to undo.
                    if scan.found.contains(where: { $0.photoID == photo.id }) {
                    Button {
                        scan.rejectCurrentPhoto()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(.white, in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Not me — remove this photo's pieces")
                    }
                }
                .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
                .rotationEffect(.degrees(photo.id.hashValue % 2 == 0 ? -3 : 3))
                .id(photo.id)
                .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .strokeBorder(Theme.line)
                .frame(width: 180, height: 230)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28))
                        Text(scan.phase == .finished ? "All done" : "Looking for\nphotos of you")
                            .font(.system(size: 13, weight: .medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.inkSoft)
                }
        }
    }

    // MARK: - Shelves

    private var shownCategories: [ClosetCategory] {
        ClosetCategory.allCases.filter { [.tops, .bottoms, .shoes].contains($0) || !scan.found(in: $0).isEmpty }
    }

    private var shelves: some View {
        VStack(spacing: 0) {
            ForEach(shownCategories) { category in
                ShelfRow(title: category.title, pieces: scan.found(in: category), studio: store.studio)
                if category != shownCategories.last { Divider().overlay(Theme.line) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
        .overlay(alignment: .topLeading) {
            Text("\(Int((scan.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line))
                .offset(x: 12, y: -12)
                .opacity(scan.phase == .running ? 1 : 0)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if scan.phase == .finished {
            VStack(spacing: 4) {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                Button(store.canStyle ? "Style my looks" : "Add more with the camera") {
                    if store.canStyle { onDone() } else { onCamera() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            }
        } else {
            VStack(spacing: 4) {
                Text("Keep the app open while we scan")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 14)
                if store.canStyle {
                    Button("Stop here and style my looks") {
                        scan.stop()
                        onDone()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                }
            }
            .frame(minHeight: 70, alignment: .top)
        }
    }

    private var summary: String {
        let count = scan.found.count
        if count == 0 {
            return scan.isLimited
                ? "We didn't find outfits in the photos you shared. Share more in Settings, or scan pieces with the camera."
                : "We couldn't find full-length photos of you. Scan a few pieces with the camera instead."
        }
        let pieces = count == 1 ? "1 piece" : "\(count) pieces"
        // Studio photos never hold her up: they keep arriving in the background, even after she leaves.
        let studio = store.studio.working.isEmpty ? "" : " Studio photos will keep appearing in the background."
        return store.canStyle
            ? "We found \(pieces).\(studio) You can edit or remove any of them in your closet."
            : "We found \(pieces). Add a few more to start styling looks."
    }

    // MARK: - Denied

    private var deniedMessage: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.inkSoft)
            Text("No access to your photos")
                .font(.display(26))
                .foregroundStyle(Theme.ink)
            Text("Allow access in Settings to fill your closet from your photos, or scan pieces with the camera.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Scan with the camera instead", action: onCamera)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(minHeight: 44)
        }
    }
}

/// One shelf: the category, how many pieces are on it, and the latest few as stickers.
private struct ShelfRow: View {
    let title: String
    let pieces: [PhotoScanModel.Found]
    let studio: StudioQueue

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.lowercased())
                    .font(.hand(18))
                    .foregroundStyle(Theme.ink)
                Text("\(pieces.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSoft)
                    .contentTransition(.numericText(value: Double(pieces.count)))
            }
            .frame(width: 72, alignment: .leading)

            HStack(spacing: -14) {
                ForEach(pieces.suffix(5)) { piece in
                    // The studio photo replaces the rough cutout as soon as it arrives.
                    (studio.finished.contains(piece.id)
                        ? SavedImageCache.image(at: PieceLibrary.stickerURL(for: piece.id))
                        : Image(uiImage: piece.sticker))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        // Pulses while its studio photo is being made.
                        .phaseAnimator([1.0, 0.5]) { image, opacity in
                            image.opacity(studio.working.contains(piece.id) ? opacity : 1)
                        } animation: { _ in .easeInOut(duration: 0.7) }
                        .animation(.easeInOut(duration: 0.4), value: studio.finished.contains(piece.id))
                        .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .offset(y: -60)).combined(with: .opacity),
                                                removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
