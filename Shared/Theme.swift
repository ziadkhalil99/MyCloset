import SwiftUI
import CoreText

/// Editorial "paper" palette: warm off-white surfaces, ink text, one burgundy accent.
/// The demo is pinned to light mode (see `RootView`) — the look is built around paper.
enum Theme {
    static let paper = Color(hex: 0xF3EDE4)
    static let card = Color(hex: 0xFBF8F3)
    static let ink = Color(hex: 0x1B1714)
    static let inkSoft = Color(hex: 0x7A6F66)
    static let line = Color(hex: 0xE4DBCF)
    static let accent = Color(hex: 0x6E1F2B)

    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 22
}

extension Font {
    /// Serif display face (Fraunces SemiBold, bundled) for titles — matches the Figma design.
    static func display(_ size: CGFloat) -> Font { .custom("Fraunces-SemiBold", fixedSize: size) }
    static func displayItalic(_ size: CGFloat) -> Font { .custom("Fraunces-SemiBoldItalic", fixedSize: size) }
    /// Handwritten face (Caveat Bold, bundled). Caveat runs small, so sizes are scaled up 20%
    /// to keep the visual size the captions were laid out for.
    static func hand(_ size: CGFloat) -> Font { .custom("Caveat-Bold", fixedSize: size * 1.2) }
}

/// Registers the fonts in Resources/Fonts at launch, so no Info.plist `UIAppFonts` entry is needed
/// (the target generates its Info.plist).
enum FontRegistrar {
    static func registerBundledFonts() {
        for name in ["Fraunces-SemiBold", "Fraunces-SemiBoldItalic", "Caveat-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing font \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(hexString: String) {
        self.init(hex: UInt32(hexString, radix: 16) ?? 0xEADFD0)
    }
}

/// Black pill used for every primary action.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.ink
    var text: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
