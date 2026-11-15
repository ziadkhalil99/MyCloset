import SwiftUI

/// "Fill your closet from your photos": what the photo scan does, the privacy promise, and the
/// way out to the camera scan for anyone who'd rather not share their library.
struct PhotoIntroView: View {
    let onStart: () -> Void
    let onCamera: () -> Void

    private let shelves: [(String, [String])] = [
        ("Tops", ["cardiganCherry", "hoodieGreen"]),
        ("Bottoms", ["jeansDark", "skirtBrown"]),
        ("Shoes", ["sneakersSamba", "sneakers530"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Fill your closet from your photos")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 32)
            Text("We find the photos of you, cut out what you're wearing and file each piece on its shelf.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            shelvesPreview
                .frame(maxHeight: .infinity)
                .padding(.vertical, 20)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
                Text("Your photos are read on this iPhone and never uploaded. Only the pieces we cut out are sent to our AI, to turn them into studio photos.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button("Fill my closet", action: onStart)
                .buttonStyle(PrimaryButtonStyle())
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
    }

    private var shelvesPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(shelves.enumerated()), id: \.offset) { index, shelf in
                VStack(alignment: .leading, spacing: 6) {
                    Text(shelf.0.lowercased())
                        .font(.hand(17))
                        .foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 10) {
                        ForEach(shelf.1, id: \.self) { id in
                            Image(id + "Sticker")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 64)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if index < shelves.count - 1 { Divider().overlay(Theme.line) }
            }
        }
        .frame(maxWidth: 250)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityHidden(true)
    }
}

#Preview {
    PhotoIntroView(onStart: {}, onCamera: {})
}
