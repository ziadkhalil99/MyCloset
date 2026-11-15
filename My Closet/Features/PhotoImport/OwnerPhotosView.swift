import PhotosUI
import SwiftUI

/// "Show us it's you": she picks one to three photos of herself so the scan can recognise her and
/// leave everyone else in her library alone. Only face fingerprints are kept, on this iPhone.
struct OwnerPhotosView: View {
    let onContinue: () -> Void
    let onCamera: () -> Void

    private struct Pick: Identifiable {
        let id = UUID()
        let image: UIImage
        /// The face fingerprint, or why this photo can't be used.
        let result: Result<FaceMatcher.Embedding, PickError>
    }

    private enum PickError: Error {
        case noFace, severalFaces, unreadable

        var message: String {
            switch self {
            case .noFace: "No face found"
            case .severalFaces: "Pick one of just you"
            case .unreadable: "Couldn't open it"
            }
        }
    }

    private static let maxPhotos = 3

    @State private var selection: [PhotosPickerItem] = []
    @State private var picks: [Pick] = []
    @State private var isReading = false

    private var faces: [FaceMatcher.Embedding] {
        picks.compactMap { try? $0.result.get() }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Show us it's you")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .padding(.top, 32)
            Text("Add 1–3 photos of just you with your face visible. A full-length mirror selfie is perfect. We'll only take outfits from photos of you, never your friends'.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 12) {
                ForEach(0..<Self.maxPhotos, id: \.self) { index in
                    if index < picks.count {
                        tile(for: picks[index])
                    } else {
                        addTile
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 24)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
                Text("Face matching happens on this iPhone. We keep a face fingerprint, not the photos, and never upload either.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                OwnerFaces.save(faces)
                onContinue()
            } label: {
                if isReading { ProgressView().tint(.white) } else { Text("Find my outfits") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: faces.isEmpty ? Theme.inkSoft.opacity(0.4) : Theme.ink))
            .disabled(faces.isEmpty || isReading)
            .padding(.top, 16)
            Button("Scan pieces with the camera instead", action: onCamera)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(minHeight: 44)
                .padding(.top, 4)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 8)
        .background(Theme.paper.ignoresSafeArea())
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await read(items) }
        }
    }

    // MARK: - Tiles

    private var addTile: some View {
        PhotosPicker(selection: $selection, maxSelectionCount: Self.maxPhotos - picks.count,
                     matching: .images, photoLibrary: .shared()) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .aspectRatio(0.66, contentMode: .fit)
        }
        .disabled(isReading)
        .accessibilityLabel("Add a photo of you")
    }

    private func tile(for pick: Pick) -> some View {
        // A fixed-shape slot with the photo filling it, so wide photos can't push the layout out.
        Color.clear
            .aspectRatio(0.66, contentMode: .fit)
            .overlay {
                Image(uiImage: pick.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .bottom) {
                Group {
                    switch pick.result {
                    case .success:
                        Label("You", systemImage: "checkmark.circle.fill")
                    case .failure(let error):
                        Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    picks.removeAll { $0.id == pick.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 24, height: 24)
                        .background(.white, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove photo")
            }
    }

    // MARK: - Reading

    private func read(_ items: [PhotosPickerItem]) async {
        isReading = true
        defer {
            isReading = false
            selection = []
        }
        for item in items.prefix(Self.maxPhotos - picks.count) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }
            let result = await Self.faceFingerprint(of: image)
            picks.append(Pick(image: image, result: result))
        }
    }

    @concurrent
    private static func faceFingerprint(of image: UIImage) async -> Result<FaceMatcher.Embedding, PickError> {
        guard let cgImage = ClothingAnalyzer.normalized(image) else { return .failure(.unreadable) }
        let faces = FaceMatcher.embeddings(in: cgImage)
        switch faces.count {
        case 0: return .failure(.noFace)
        case 1: return .success(faces[0])
        default: return .failure(.severalFaces)
        }
    }
}

#Preview {
    OwnerPhotosView(onContinue: {}, onCamera: {})
}
