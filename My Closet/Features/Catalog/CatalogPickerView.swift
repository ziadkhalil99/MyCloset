import SwiftUI

/// "Tap what you own": the fast way to fill her closet. A grid of everyday basics by category;
/// each tap drops the piece onto a little pile at the bottom, and once there's a top and a
/// bottom (or a dress) she can go straight to her looks. Scanning stays one tap away.
struct CatalogPickerView: View {
    let onDone: () -> Void
    let onMoreWays: () -> Void

    @Environment(ClosetStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// In the order she tapped them.
    @State private var picks: [StarterPiece] = []
    @State private var visibleCategory: ClosetCategory?
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var appeared = false

    private static let columnCount = 3

    private var canStyle: Bool { StarterCatalog.canStyle(picks) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.screenPadding)
            categoryBar
                .padding(.top, 14)
                .entrance(appeared, delay: 0.1, reduceMotion: reduceMotion)
            grid
                .entrance(appeared, delay: 0.16, reduceMotion: reduceMotion)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(Theme.paper.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: picks.count)
        .sensoryFeedback(.success, trigger: canStyle) { old, new in !old && new }
        .onAppear { appeared = true }
        .alert("Couldn't save your pieces", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("More ways to add", action: onMoreWays)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 44)
            }
            Text("Tap what you own")
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .entrance(appeared, delay: 0, reduceMotion: reduceMotion)
            Text("Close enough counts. You can scan your real pieces any time.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .entrance(appeared, delay: 0.05, reduceMotion: reduceMotion)
        }
    }

    /// Category chips that jump to their shelf and follow along while she scrolls.
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StarterCatalog.sections, id: \.category) { section in
                    let count = picks.filter { $0.category == section.category }.count
                    ChoiceChip(title: count > 0 ? "\(section.category.title) · \(count)" : section.category.title,
                               isSelected: (visibleCategory ?? .tops) == section.category) {
                        withAnimation(.spring(duration: 0.45, bounce: 0.1)) { visibleCategory = section.category }
                    }
                    .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .scrollClipDisabled()
    }

    // MARK: - Grid

    /// Not lazy: with 43 small tiles everything can be laid out up front, which keeps the chip
    /// jumps exact (a lazy stack guesses the height of shelves it hasn't drawn and lands short).
    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(StarterCatalog.sections, id: \.category) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.category.title.lowercased())
                            .font(.hand(20))
                            .foregroundStyle(Theme.inkSoft)
                        Grid(horizontalSpacing: 10, verticalSpacing: 12) {
                            ForEach(Array(stride(from: 0, to: section.pieces.count, by: Self.columnCount)), id: \.self) { start in
                                GridRow {
                                    ForEach(start..<start + Self.columnCount, id: \.self) { index in
                                        if index < section.pieces.count {
                                            let piece = section.pieces[index]
                                            PieceTile(piece: piece, isPicked: picks.contains(piece)) { toggle(piece) }
                                        } else {
                                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .id(section.category)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollPosition(id: $visibleCategory, anchor: .top)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PickPile(picks: picks)
                VStack(alignment: .leading, spacing: 2) {
                    Text(picks.isEmpty ? "Nothing picked yet" : "\(picks.count) \(picks.count == 1 ? "piece" : "pieces") picked")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: Double(picks.count)))
                    Text(StarterCatalog.missing(picks) ?? "Ready to style. Add more for more looks.")
                        .font(.system(size: 13))
                        .foregroundStyle(canStyle ? Theme.inkSoft : Theme.accent)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.easeInOut(duration: 0.2), value: picks.count)
                Spacer(minLength: 0)
            }

            Button(action: finish) {
                if isSaving { ProgressView().tint(.white) } else { Text("Style my looks") }
            }
            .buttonStyle(PrimaryButtonStyle(fill: canStyle ? Theme.ink : Theme.inkSoft.opacity(0.4)))
            .disabled(!canStyle || isSaving)
            .animation(.easeInOut(duration: 0.2), value: canStyle)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            Theme.paper
                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
                .ignoresSafeArea()
        }
    }

    // MARK: - Actions

    private func toggle(_ piece: StarterPiece) {
        withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
            if let index = picks.firstIndex(of: piece) {
                picks.remove(at: index)
            } else {
                picks.append(piece)
            }
        }
    }

    private func finish() {
        isSaving = true
        let chosen = picks
        Task {
            do {
                try await StarterCatalog.save(chosen)
                store.reloadSaved()
                onDone()
            } catch {
                isSaving = false
                saveFailed = true
            }
        }
    }
}

/// One basic on its card. Picked: ink border, a check, and the piece lifts a little.
private struct PieceTile: View {
    let piece: StarterPiece
    let isPicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)
                    .overlay {
                        if let image = StarterCatalog.image(for: piece) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                                .scaleEffect(isPicked ? 1.06 : 1)
                                .shadow(color: .black.opacity(isPicked ? 0.16 : 0.06), radius: isPicked ? 8 : 4, y: isPicked ? 5 : 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPicked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Theme.ink, in: Circle())
                                .padding(8)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isPicked ? Theme.ink : Theme.line, lineWidth: isPicked ? 2 : 1)
                    }
                    .aspectRatio(1, contentMode: .fit)
                Text(piece.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isPicked ? Theme.ink : Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .buttonStyle(PressScaleStyle(pressed: 0.93))
        .accessibilityLabel(piece.name)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// The last few picks as a little fanned pile; each new one drops on top.
private struct PickPile: View {
    let picks: [StarterPiece]

    private static let shown = 4
    private static let tilts: [Double] = [-8, 6, -3, 9]

    var body: some View {
        let recent = Array(picks.suffix(Self.shown))
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .opacity(picks.isEmpty ? 1 : 0)
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, piece in
                if let image = StarterCatalog.image(for: piece) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                        .rotationEffect(.degrees(Self.tilts[(picks.count - recent.count + index) % Self.tilts.count]))
                        .offset(x: CGFloat(index - recent.count + 1) * 7)
                        .transition(.stickerDrop)
                }
            }
        }
        .frame(width: 64, height: 52)
        .accessibilityHidden(true)
    }
}

#Preview {
    CatalogPickerView(onDone: {}, onMoreWays: {})
        .environment(ClosetStore())
}
