import SwiftUI

// MARK: - Sticker pile

/// The pile of stickers that grows with every answer and follows her through the questions.
struct StickerPile: View {
    let itemIDs: [String]
    var tapeLabel: String?

    /// Slot centre (x as a fraction of width, y in points), cutout width, clockwise rotation.
    private static let slots: [(x: CGFloat, y: CGFloat, w: CGFloat, rot: Double)] = [
        (0.50, 62, 96, -6), (0.27, 70, 82, -10), (0.73, 60, 84, 7), (0.10, 84, 62, -12),
        (0.92, 74, 58, 11), (0.38, 98, 58, 5), (0.62, 98, 56, -8), (0.50, 28, 50, 3),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(itemIDs.enumerated()), id: \.element) { index, id in
                    if let item = ClosetItem.item(id: id) {
                        let slot = Self.slots[index % Self.slots.count]
                        StickerImage(item: item, width: min(slot.w, item.fittedWidth(in: CGSize(width: slot.w, height: 92))))
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
                            .rotationEffect(.degrees(slot.rot))
                            .position(x: slot.x * geo.size.width, y: slot.y)
                            .transition(.stickerDrop)
                    }
                }
                if let tapeLabel {
                    TapeLabel(text: tapeLabel)
                        .position(x: geo.size.width / 2, y: 124)
                        .transition(.tapeSlap)
                }
            }
        }
        .frame(height: 136)
        .animation(.spring(duration: 0.6, bounce: 0.4), value: itemIDs)
        .animation(.spring(duration: 0.45, bounce: 0.45), value: tapeLabel == nil)
    }
}

/// Handwritten label on a strip of masking tape ("Sara's closet ♡").
struct TapeLabel: View {
    let text: String
    var size: CGFloat = 26

    var body: some View {
        Text(text)
            .font(.hand(size))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background(Color(hex: 0xEFE6C8).opacity(0.95))
            .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
            .rotationEffect(.degrees(-4))
            .accessibilityLabel(text)
    }
}

private struct DropIn: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 1.35 : 1)
            .rotationEffect(.degrees(active ? -20 : 0))
            .offset(y: active ? -90 : 0)
            .opacity(active ? 0 : 1)
    }
}

private struct Slap: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 1.6 : 1)
            .rotationEffect(.degrees(active ? -10 : 0))
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static var stickerDrop: AnyTransition {
        .asymmetric(insertion: .modifier(active: DropIn(active: true), identity: DropIn(active: false)),
                    removal: .scale(scale: 0.6).combined(with: .opacity))
    }

    static var tapeSlap: AnyTransition {
        .modifier(active: Slap(active: true), identity: Slap(active: false))
    }
}

// MARK: - Controls

struct OnboardingProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(Theme.ink).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 4)
        .animation(.spring(duration: 0.5), value: progress)
        .accessibilityElement()
        .accessibilityLabel("Step progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// Single-choice answer row (Figma "Option Row").
struct OptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(.horizontal, 18)
                .background(isSelected ? Theme.ink : Theme.card, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isSelected ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Multi-select occasion chip (Figma "Chip").
struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(isSelected ? Theme.ink : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(pressed: 0.9))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PressScaleStyle: ButtonStyle {
    var pressed: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressed : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// Wraps children onto new lines, left-aligned.
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + lineSpacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
