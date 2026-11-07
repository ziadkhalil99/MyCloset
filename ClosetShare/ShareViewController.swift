import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point when someone taps My Closet in the share sheet (for example from a screenshot's
/// preview). Hosts the SwiftUI review screen and hands it the shared image.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        FontRegistrar.registerBundledFonts()

        model.onClose = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: ShareReviewView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.start(with: providers) }
    }
}

@Observable
final class ShareModel {
    enum Phase { case analyzing, review, saving, saved, empty, failed(String) }

    var phase: Phase = .analyzing
    var screenshot: UIImage?
    var pieces: [DetectedPiece] = []
    /// Non-clothing subjects, kept back unless the person taps "Add it anyway".
    private var otherPieces: [DetectedPiece] = []
    var canAddAnyway: Bool { !otherPieces.isEmpty }
    var selected: Set<UUID> = []
    var isWishlist = false
    var onClose: () -> Void = {}

    func start(with providers: [NSItemProvider]) async {
        guard let image = await Self.loadImage(from: providers) else {
            phase = .failed("That doesn't look like an image. Share a screenshot or photo instead.")
            return
        }
        screenshot = image
        let result = await ClothingAnalyzer.analyze(image)
        otherPieces = result.other
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
            pieces = result.clothing
            selected = Set(result.clothing.prefix(1).map(\.id))
            phase = result.clothing.isEmpty ? .empty : .review
        }
    }

    /// Shows what was lifted even though none of it looked like clothing. Nothing is preselected.
    func addAnyway() {
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
            pieces = otherPieces
            selected = []
            phase = .review
        }
    }

    func save() {
        let chosen = pieces.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        withAnimation { phase = .saving }
        do {
            let now = Date()
            for (offset, piece) in chosen.enumerated() {
                let saved = SavedPiece(
                    id: UUID().uuidString, name: piece.name.trimmingCharacters(in: .whitespaces).isEmpty ? "New piece" : piece.name,
                    category: piece.category, color: piece.color, isWishlist: isWishlist,
                    // Keeps the reviewed order when the closet sorts newest first.
                    addedAt: now.addingTimeInterval(-Double(offset) * 0.001),
                    cutoutAspect: piece.cutoutAspect)
                try PieceLibrary.add(saved, cutout: piece.cutout, sticker: piece.sticker)
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { phase = .saved }
            Task {
                try? await Task.sleep(for: .seconds(1.3))
                onClose()
            }
        } catch {
            withAnimation { phase = .failed(error.localizedDescription) }
        }
    }

    private static func loadImage(from providers: [NSItemProvider]) async -> UIImage? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else { return nil }
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        switch item {
        case let image as UIImage: return image
        case let url as URL: return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
        case let data as Data: return UIImage(data: data)
        default: return nil
        }
    }
}
