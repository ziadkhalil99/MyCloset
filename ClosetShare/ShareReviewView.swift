import SwiftUI

/// Analyse → review → save, inside the share sheet. The person picks which found pieces to keep,
/// can rename or recategorise them, and says whether they own them or just want them.
struct ShareReviewView: View {
    @Bindable var model: ShareModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switch model.phase {
            case .analyzing:
                AnalyzingView(screenshot: model.screenshot)
            case .review, .saving:
                review
            case .saved:
                message(icon: "checkmark", title: model.isWishlist ? "Added to your wishlist" : "Added to your closet",
                        body: "Open My Closet to style it into looks.", showClose: false)
            case .empty:
                message(icon: "eye.slash", title: "No clothes found",
                        body: "Try a screenshot where the piece is large and clearly visible.", showClose: true,
                        showAddAnyway: model.canAddAnyway)
            case .failed(let reason):
                message(icon: "exclamationmark", title: "Couldn't add that", body: reason, showClose: true)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .tint(Theme.ink)
        .sensoryFeedback(.success, trigger: model.phase.isSaved)
    }

    private var topBar: some View {
        HStack {
            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Cancel")
            Spacer()
            Text("My Closet")
                .font(.display(20))
                .foregroundStyle(Theme.ink)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Review

    private var review: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.pieces.count == 1 ? "Found 1 piece" : "Found \(model.pieces.count) pieces")
                            .font(.display(30))
                            .foregroundStyle(Theme.ink)
                        Text("Pick what to add. Tap a name to change it.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    ForEach($model.pieces) { $piece in
                        PieceRow(piece: $piece, isSelected: model.selected.contains(piece.id)) {
                            withAnimation(.spring(duration: 0.3)) {
                                if model.selected.contains(piece.id) {
                                    model.selected.remove(piece.id)
                                } else {
                                    model.selected.insert(piece.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 14) {
                Picker("Status", selection: $model.isWishlist) {
                    Text("I own it").tag(false)
                    Text("Wishlist").tag(true)
                }
                .pickerStyle(.segmented)

                Button(action: model.save) {
                    if model.phase.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(addTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.selected.isEmpty || model.phase.isSaving)
                .opacity(model.selected.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Theme.paper)
        }
        .transition(.opacity)
    }

    private var addTitle: String {
        let count = model.selected.count
        let noun = count == 1 ? "piece" : "\(count) pieces"
        return model.isWishlist ? "Add \(noun == "piece" ? "it" : noun) to wishlist" : "Add \(noun == "piece" ? "it" : noun) to closet"
    }

    // MARK: - Messages

    private func message(icon: String, title: String, body: String, showClose: Bool,
                         showAddAnyway: Bool = false) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(model.phase.isSaved ? Theme.accent : Theme.ink, in: Circle())
                .transition(.scale.combined(with: .opacity))
            Text(title)
                .font(.display(28))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            Spacer()
            if showAddAnyway {
                Button("Add it anyway", action: model.addAnyway)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            if showClose {
                Button("Close", action: model.onClose)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }
}

private struct PieceRow: View {
    @Binding var piece: DetectedPiece
    let isSelected: Bool
    let toggle: () -> Void

    private static let categories: [(String, String)] = [
        ("tops", "Tops"), ("outerwear", "Outerwear"), ("bottoms", "Bottoms"),
        ("dresses", "Dresses"), ("shoes", "Shoes"), ("bags", "Bags"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                Image(uiImage: piece.sticker)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(width: 92, height: 104)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                    .background(Theme.paper, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(piece.name)" : "Select \(piece.name)")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Name", text: $piece.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.done)
                Menu {
                    Picker("Category", selection: $piece.category) {
                        ForEach(Self.categories, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.categories.first { $0.0 == piece.category }?.1 ?? "Tops")
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.paper, in: Capsule())
                }
                Text(piece.color)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)

            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.line)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(isSelected ? Theme.accent : Theme.line,
                                                                 lineWidth: isSelected ? 2 : 1))
        .opacity(isSelected ? 1 : 0.75)
    }
}

/// The screenshot with a light band sweeping down it while Vision works.
private struct AnalyzingView: View {
    let screenshot: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            GeometryReader { geo in
                let size = fitted(in: geo.size)
                ZStack(alignment: .top) {
                    if let screenshot {
                        Image(uiImage: screenshot).resizable().scaledToFill()
                    } else {
                        Theme.card
                    }
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, .white.opacity(0.7), .white, .white.opacity(0.7), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 30)
                            .blendMode(.plusLighter)
                            .offset(y: sweep * size.height - 15)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding the clothes…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, Theme.screenPadding)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { sweep = 1 }
        }
    }

    private func fitted(in box: CGSize) -> CGSize {
        let aspect = screenshot.map { $0.size.width / max($0.size.height, 1) } ?? 0.46
        let width = min(box.width, box.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }
}

private extension ShareModel.Phase {
    var isSaved: Bool { if case .saved = self { true } else { false } }
    var isSaving: Bool { if case .saving = self { true } else { false } }
}
