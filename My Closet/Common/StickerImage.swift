import SwiftUI

/// The `<id>Sticker` asset is the cutout plus a white border. The border padding is
/// 4.2% of the cutout's longer side on every edge (see the asset script), so a sticker
/// laid over a cutout of the same `width` lines up exactly.
struct StickerImage: View {
    let item: ClosetItem
    /// Width of the underlying cutout, not of the sticker.
    let width: CGFloat

    static let borderFraction: CGFloat = ClothingAnalyzer.stickerBorder

    var body: some View {
        let cutoutHeight = width / item.cutoutAspect
        let pad = Self.borderFraction * max(width, cutoutHeight)
        item.stickerImage
            .resizable()
            .scaledToFit()
            .frame(width: width + pad * 2, height: cutoutHeight + pad * 2)
    }
}
