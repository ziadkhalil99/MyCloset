import SwiftUI

struct ClosetView: View {
    @Environment(ClosetStore.self) private var store
    @State private var filter: ClosetCategory?
    @State private var selected: ClosetItem?
    @State private var showScan = false
    @AppStorage("closet.screenshotTipDismissed") private var tipDismissed = false
    @Environment(\.scenePhase) private var scenePhase

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !tipDismissed { screenshotTip }
                    chips
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(store.items(in: filter)) { item in
                            Button { selected = item } label: { ItemTile(item: item, isNew: store.recentlyAdded.contains(item.id)) }
                                .buttonStyle(.plain)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .animation(.spring(duration: 0.4), value: filter)
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showScan = true } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("Scan a piece")
                }
            }
        }
        .sheet(item: $selected) { item in
            ItemSheet(item: item)
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView { showScan = false }
        }
        .sensoryFeedback(.selection, trigger: filter)
        .onChange(of: scenePhase) { _, phase in
            // Pieces may have been added from the share sheet while the app was in the background.
            if phase == .active { withAnimation(.spring(duration: 0.4)) { store.reloadSaved() } }
        }
    }

    private var screenshotTip: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.paper, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Add from screenshots")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Screenshot a piece while you shop, tap the preview, then Share → My Closet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(duration: 0.35)) { tipDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss tip")
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, Theme.screenPadding)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("My closet")
                .font(.display(36))
                .foregroundStyle(Theme.ink)
            Text("\(store.items.count) pieces · \(store.lookBook.looks.count) looks")
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, Theme.screenPadding)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", count: store.items.count, isOn: filter == nil) { filter = nil }
                ForEach(ClosetCategory.allCases) { category in
                    let count = store.items(in: category).count
                    if count > 0 {
                        chip(category.title, count: count, isOn: filter == category) { filter = category }
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text("\(count)").font(.system(size: 13, weight: .medium)).opacity(0.6)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .foregroundStyle(isOn ? .white : Theme.ink)
            .background(isOn ? Theme.ink : Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? .clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ItemTile: View {
    let item: ClosetItem
    let isNew: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(0.86, contentMode: .fit)
                .overlay {
                    item.cutoutImage
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 4)
                }
                .background(Theme.card, in: .rect(cornerRadius: Theme.tileRadius))
                .overlay(alignment: .topTrailing) {
                    if item.isWishlist {
                        Label("Wishlist", systemImage: "heart")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.paper, in: Capsule())
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isNew {
                        Text("new!")
                            .font(.hand(18))
                            .foregroundStyle(Theme.accent)
                            .rotationEffect(.degrees(10))
                            .padding(12)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
    }
}

/// Piece detail: the sticker, its tags, and every look it appears in.
private struct ItemSheet: View {
    let item: ClosetItem
    @Environment(ClosetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let looks = store.looks(containing: item)
        ScrollView {
            VStack(spacing: 20) {
                StickerImage(item: item, width: item.fittedWidth(in: CGSize(width: 220, height: 230)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 8)
                    .rotationEffect(.degrees(appeared || reduceMotion ? -3 : -18))
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
                    .frame(height: 260)
                    .padding(.top, 28)
                VStack(spacing: 6) {
                    Text(item.name)
                        .font(.display(28))
                        .foregroundStyle(Theme.ink)
                    Text("\(item.category.title) · \(item.detail)")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                    if item.isWishlist {
                        Label("On your wishlist", systemImage: "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 4)
                    }
                }
                if item.isSaved {
                    Button(role: .destructive) {
                        store.remove(item)
                        dismiss()
                    } label: {
                        Label("Remove from closet", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .tint(Theme.accent)
                }
                if !looks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(looks.count == 1 ? "IN 1 LOOK" : "IN \(looks.count) LOOKS")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, Theme.screenPadding)
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(looks) { look in
                                    LookCanvas(look: look, animateIn: false)
                                        .aspectRatio(store.lookBook.canvasAspect, contentMode: .fit)
                                        .frame(width: 140)
                                }
                            }
                            .padding(.horizontal, Theme.screenPadding)
                        }
                        .scrollIndicators(.hidden)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.paper)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) { appeared = true }
        }
    }
}

#Preview {
    ClosetView()
        .environment(ClosetStore())
}
