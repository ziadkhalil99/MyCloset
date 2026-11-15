import PhotosUI
import SwiftUI

/// Fill the closet from outfit photos she picks herself. First she shows us her face (a selfie
/// or a photo), so in every outfit photo we read only her clothes, never a friend's. Then she
/// chooses up to 15 outfit photos, we cut out what she's wearing, and she keeps what's hers,
/// drops what's wrong, moves a piece to the right shelf, or scans a better photo of it.
/// Pieces from her outfit photos turn into clean studio photos in the background.
struct OutfitPhotosView: View {
    let onDone: () -> Void
    let onCamera: () -> Void

    @Environment(ClosetStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Photo: Identifiable {
        let id = UUID()
        let item: PhotosPickerItem
        let thumbnail: UIImage
        var skip: OutfitPhotoReader.Skip?
    }

    private struct Reference: Identifiable {
        let id = UUID()
        let image: UIImage
        let result: Result<FaceMatcher.Embedding, OutfitPhotoReader.ReferenceError>
    }

    private struct RetakeTarget: Identifiable { let id: UUID }

    private enum Phase: Equatable { case me, picking, reading(Int), review }

    private static let maxPhotos = 15
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    @State private var selection: [PhotosPickerItem] = []
    @State private var photos: [Photo] = []
    @State private var isLoadingPicks = false
    /// Always starts with her selfie, so every outfit photo is read against a fresh face.
    @State private var phase: Phase = .me
    @State private var references: [Reference] = []
    @State private var referenceItem: PhotosPickerItem?
    @State private var isReadingReference = false
    @State private var showSelfieCamera = false
    @State private var showSelfieTips = false
    @State private var showReferencePicker = false
    /// The how-to sheet comes up by itself the first time she lands on this step.
    @State private var shownSelfieTipsOnce = false
    @State private var retakeTarget: RetakeTarget?
    @State private var candidates: [OutfitPhotoReader.Candidate] = []
    @State private var dropped: Set<UUID> = []
    @State private var shelf: [UUID: String] = [:]
    @State private var readTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var appeared = false

    private var referenceFaces: [FaceMatcher.Embedding] { references.compactMap { try? $0.result.get() } }

    private var kept: [OutfitPhotoReader.Candidate] { candidates.filter { !dropped.contains($0.id) } }

    private func category(of candidate: OutfitPhotoReader.Candidate) -> String {
        shelf[candidate.id] ?? candidate.piece.category
    }

    private var canStyle: Bool {
        let categories = Set(kept.map(category(of:)))
        let upper = categories.contains("tops") || categories.contains("outerwear")
        return (upper && categories.contains("bottoms")) || categories.contains("dresses")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Theme.screenPadding)
            Group {
                switch phase {
                case .me: meContent
                case .picking: pickingContent
                case .reading, .review: reviewContent
                }
            }
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(Theme.paper.ignoresSafeArea())
        .animation(.spring(duration: 0.45, bounce: 0.15), value: phase)
        .onAppear { appeared = true }
        .onDisappear { readTask?.cancel() }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicks(items) }
        }
        .onChange(of: referenceItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                referenceItem = nil
                if let data, let image = UIImage(data: data) { await addReference(image) }
            }
        }
        .sheet(isPresented: $showSelfieTips) {
            SelfieTipsSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .presentationBackground(Theme.paper)
        }
        .photosPicker(isPresented: $showReferencePicker, selection: $referenceItem, matching: .images,
                      photoLibrary: .shared())
        .task(id: phase) {
            // The selfie guide comes up by itself the first time she lands on this step.
            guard canAutoPresentSelfieTips else { return }
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, canAutoPresentSelfieTips else { return }
            shownSelfieTipsOnce = true
            showSelfieTips = true
        }
        .fullScreenCover(isPresented: $showSelfieCamera) {
            CameraPicker(device: .front) { image in
                showSelfieCamera = false
                if let image { Task { await addReference(image) } }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $retakeTarget) { target in
            if let candidate = candidates.first(where: { $0.id == target.id }) {
                PieceRetakeView(category: ClosetCategory(rawValue: category(of: candidate)) ?? .tops,
                                current: candidate.thumbnail) { piece in
                    replace(target.id, with: piece)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: dropped)
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .review }
        .alert("Couldn't save your pieces", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.display(30))
                .foregroundStyle(Theme.ink)
                .contentTransition(.opacity)
                .padding(.top, 32)
                .entrance(appeared, delay: 0, reduceMotion: reduceMotion)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .entrance(appeared, delay: 0.05, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch phase {
        case .me: "First, a selfie"
        case .picking: "Show us your outfits"
        case .reading: "Finding your clothes"
        case .review: "Keep what's yours"
        }
    }

    private var subtitle: String {
        switch phase {
        case .me:
            "A clear photo of your face, so we only take clothes from you in your photos, never your friends'."
        case .picking:
            "Pick photos of you in different outfits. Mirror selfies and full-length shots work best."
        case .reading(let index):
            "Photo \(min(index + 1, photos.count)) of \(photos.count). Pieces show up as we find them."
        case .review:
            "Tap a piece to drop it, hold to change its shelf, or tap its camera to scan a better photo. The rest become clean product photos."
        }
    }

    // MARK: - Her face

    private var meContent: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                ForEach(references) { reference in
                    referenceCircle(reference)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if references.isEmpty {
                    selfiePlaceholder
                        .overlay(alignment: .bottomTrailing) {
                            selfieInfoButton
                                .offset(x: 6, y: 6)
                        }
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.3), value: references.map(\.id))

            if let error = references.last.flatMap({ reference -> OutfitPhotoReader.ReferenceError? in
                if case .failure(let error) = reference.result { return error } else { return nil }
            }) {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else if !referenceFaces.isEmpty {
                Label(referenceFaces.count == 1 ? "Got it. Another photo makes matching even better."
                                                : "Got it. We'll know you in your photos.",
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
                Text("We keep a face fingerprint on this iPhone, never the photo, and never upload it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 12)
        .entrance(appeared, delay: 0.12, reduceMotion: reduceMotion)
    }

    private var selfiePlaceholder: some View {
        Circle()
            .fill(Theme.card)
            .frame(width: 150, height: 150)
            .overlay {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.inkSoft)
            }
            .overlay(Circle().strokeBorder(Theme.inkSoft.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6])))
            .overlay { if isReadingReference { ProgressView() } }
            .accessibilityLabel("Selfie placeholder")
    }

    private var selfieInfoButton: some View {
        Button {
            showSelfieTips = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 36, height: 36)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See how to take a selfie")
    }

    private func referenceCircle(_ reference: Reference) -> some View {
        let size: CGFloat = references.count == 1 ? 150 : 96
        let isGood = (try? reference.result.get()) != nil
        return Image(uiImage: reference.image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
                    .overlay(Circle().strokeBorder(isGood ? Theme.success : Theme.accent, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isGood ? "checkmark" : "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(isGood ? Theme.success : Theme.accent, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 2))
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    references.removeAll { $0.id == reference.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 24, height: 24)
                        .background(.white, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .offset(x: 10, y: -10)
                .accessibilityLabel("Remove photo")
            }
            .accessibilityLabel(isGood ? "Your face" : "Photo that can't be used")
    }

    // MARK: - Picking

    private var pickingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    phase = .me
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text("Only your clothes")
                        Text("· Change face").foregroundStyle(Theme.inkSoft)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.line))
                }
                .buttonStyle(PressScaleStyle())
                if photos.isEmpty {
                    emptyPicker
                } else {
                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        ForEach(photos) { photo in
                            photoTile(photo)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        if photos.count < Self.maxPhotos { addTile }
                    }
                }
                HStack(spacing: 14) {
                    ForEach(["Just you", "Head to toe", "Different outfits"], id: \.self) { tip in
                        Label(tip, systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .animation(.spring(duration: 0.4, bounce: 0.25), value: photos.map(\.id))
        }
        .entrance(appeared, delay: 0.12, reduceMotion: reduceMotion)
    }

    private var emptyPicker: some View {
        picker {
            VStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Theme.ink)
                Text("Choose outfit photos")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Up to \(Self.maxPhotos). The more outfits, the more pieces.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.inkSoft.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
            }
            .overlay { if isLoadingPicks { ProgressView() } }
        }
    }

    private var addTile: some View {
        picker {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.inkSoft.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                }
                .overlay {
                    if isLoadingPicks {
                        ProgressView()
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .aspectRatio(0.75, contentMode: .fit)
        }
        .accessibilityLabel("Add more photos")
    }

    private func picker(@ViewBuilder label: () -> some View) -> some View {
        PhotosPicker(selection: $selection, maxSelectionCount: Self.maxPhotos - photos.count,
                     selectionBehavior: .ordered, matching: .images, photoLibrary: .shared(), label: label)
            .disabled(isLoadingPicks)
    }

    private func photoTile(_ photo: Photo) -> some View {
        Color.clear
            .aspectRatio(0.75, contentMode: .fit)
            .overlay { Image(uiImage: photo.thumbnail).resizable().scaledToFill() }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    photos.removeAll { $0.id == photo.id }
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

    // MARK: - Reading and review

    private var reviewContent: some View {
        VStack(spacing: 0) {
            photoStrip
                .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(ClosetCategory.allCases) { category in
                        let pieces = candidates.filter { self.category(of: $0) == category.rawValue }
                        if !pieces.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.title.lowercased())
                                    .font(.hand(20))
                                    .foregroundStyle(Theme.inkSoft)
                                LazyVGrid(columns: Self.columns, spacing: 10) {
                                    ForEach(pieces) { candidate in
                                        candidateTile(candidate)
                                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                                    }
                                }
                            }
                        }
                    }
                    if case .reading = phase {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Cutting out pieces…")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if candidates.isEmpty {
                        Text("We couldn't find clothes in these photos. Try full-length photos of just you.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .animation(.spring(duration: 0.45, bounce: 0.3), value: candidates.map(\.id))
                .animation(.spring(duration: 0.4, bounce: 0.2), value: shelf)
            }
        }
    }

    /// Her photos in a row: the one being read pulses, skipped ones say why.
    private var photoStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        let isCurrent = phase == .reading(index)
                        Image(uiImage: photo.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if photo.skip != nil {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.5))
                                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isCurrent ? Theme.ink : .clear, lineWidth: 2)
                            }
                            .scaleEffect(isCurrent ? 1.08 : 1)
                            .opacity(isDone(index) || isCurrent ? 1 : 0.45)
                            .id(index)
                            .accessibilityLabel(photo.skip?.message ?? "Photo \(index + 1)")
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 4)
                .animation(.spring(duration: 0.35), value: phase)
            }
            .onChange(of: phase) { _, new in
                if case .reading(let index) = new { withAnimation { proxy.scrollTo(index, anchor: .center) } }
            }
        }
        .frame(height: 76)
    }

    private func isDone(_ index: Int) -> Bool {
        switch phase {
        case .me, .picking: false
        case .reading(let current): index < current
        case .review: true
        }
    }

    private func candidateTile(_ candidate: OutfitPhotoReader.Candidate) -> some View {
        let isKept = !dropped.contains(candidate.id)
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                if isKept { dropped.insert(candidate.id) } else { dropped.remove(candidate.id) }
            }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    Image(uiImage: candidate.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .saturation(isKept ? 1 : 0)
                        .opacity(isKept ? 1 : 0.35)
                }
                .overlay(alignment: .bottomLeading) {
                    if isKept {
                        Button {
                            retakeTarget = RetakeTarget(id: candidate.id)
                        } label: {
                            Image(systemName: candidate.isRetaken ? "camera.fill" : "camera")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(candidate.isRetaken ? .white : Theme.ink)
                                .frame(width: 28, height: 28)
                                .background(candidate.isRetaken ? Theme.ink : .white, in: Circle())
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Scan a better photo of this piece")
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isKept ? "checkmark" : "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isKept ? .white : Theme.inkSoft)
                        .frame(width: 22, height: 22)
                        .background(isKept ? Theme.ink : Theme.line, in: Circle())
                        .padding(7)
                        .contentTransition(.symbolEffect(.replace))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isKept ? Theme.ink.opacity(0.85) : Theme.line,
                                      style: StrokeStyle(lineWidth: isKept ? 1.5 : 1, dash: isKept ? [] : [5, 4]))
                }
                .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(PressScaleStyle(pressed: 0.93))
        .contextMenu {
            Picker("Shelf", selection: Binding(
                get: { category(of: candidate) },
                set: { shelf[candidate.id] = $0 }
            )) {
                ForEach(ClosetCategory.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("Scan a better photo", systemImage: "camera") {
                retakeTarget = RetakeTarget(id: candidate.id)
            }
            Button(isKept ? "Not mine" : "Keep it", systemImage: isKept ? "xmark" : "checkmark") {
                if isKept { dropped.insert(candidate.id) } else { dropped.remove(candidate.id) }
            }
        }
        .accessibilityLabel(candidate.piece.name)
        .accessibilityValue(isKept ? "Kept" : "Dropped")
    }

    // MARK: - Bottom bar

    /// Skip the delayed how-to sheet if she already started capture — presenting both at
    /// once fights over the window.
    private var canAutoPresentSelfieTips: Bool {
        phase == .me
            && references.isEmpty
            && !shownSelfieTipsOnce
            && !showSelfieCamera
            && !showReferencePicker
    }

    @ViewBuilder
    private var selfieSourceButtons: some View {
        Button("Take a selfie") { startSelfieCapture(.camera) }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
            .disabled(isReadingReference || !CameraPicker.isAvailable)
            .opacity(CameraPicker.isAvailable ? 1 : 0.45)
        Button("Choose a photo instead") { startSelfieCapture(.library) }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
            .disabled(isReadingReference)
    }

    private enum SelfieSource { case camera, library }

    private func startSelfieCapture(_ source: SelfieSource) {
        shownSelfieTipsOnce = true
        showSelfieTips = false
        switch source {
        case .camera: showSelfieCamera = true
        case .library: showReferencePicker = true
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 4) {
            switch phase {
            case .me:
                if !referenceFaces.isEmpty {
                    Button("That's me") {
                        OwnerFaces.save(referenceFaces)
                        phase = .picking
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if references.count < 3 {
                    selfieSourceButtons
                }
            case .picking:
                Button("Find my clothes", action: startReading)
                    .buttonStyle(PrimaryButtonStyle(fill: photos.isEmpty ? Theme.inkSoft.opacity(0.4) : Theme.ink))
                    .disabled(photos.isEmpty || isLoadingPicks)
                Button("Scan pieces with the camera instead", action: onCamera)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 44)
            case .reading, .review:
                if case .review = phase, !candidates.isEmpty, !canStyle {
                    Text("Keep a top and a bottom, or a dress, to style your first look")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 6)
                }
                Button(action: save) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(kept.isEmpty ? "Add pieces" : "Add \(kept.count) \(kept.count == 1 ? "piece" : "pieces")")
                            .contentTransition(.numericText(value: Double(kept.count)))
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: phase == .review && canStyle ? Theme.ink : Theme.inkSoft.opacity(0.4)))
                .disabled(phase != .review || !canStyle || isSaving)
                Button("Add more photos", action: backToPicking)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 44)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: kept.count)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Theme.paper
                .shadow(color: .black.opacity(phase == .picking ? 0 : 0.06), radius: 12, y: -4)
                .ignoresSafeArea()
        }
    }

    // MARK: - Actions

    private func addPicks(_ items: [PhotosPickerItem]) async {
        isLoadingPicks = true
        defer {
            isLoadingPicks = false
            selection = []
        }
        for item in items.prefix(Self.maxPhotos - photos.count) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let thumbnail = await Self.thumbnail(from: data)
            else { continue }
            withAnimation { photos.append(Photo(item: item, thumbnail: thumbnail)) }
        }
    }

    @concurrent
    private static func thumbnail(from data: Data) async -> UIImage? {
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 300, height: 400))
    }

    private func startReading() {
        candidates = []
        dropped = []
        shelf = [:]
        for index in photos.indices { photos[index].skip = nil }
        phase = .reading(0)
        let items = photos.map(\.item)
        readTask = Task {
            for await event in OutfitPhotoReader.read(items, owner: OwnerFaces.load()) {
                switch event {
                case .reading(let index):
                    phase = .reading(index)
                case .found(let candidate):
                    candidates.append(candidate)
                case .skipped(let index, let reason):
                    if photos.indices.contains(index) { photos[index].skip = reason }
                case .finished:
                    phase = .review
                }
            }
        }
    }

    private func addReference(_ image: UIImage) async {
        isReadingReference = true
        defer { isReadingReference = false }
        // A failed photo is replaced by the next one rather than piling up.
        references.removeAll { (try? $0.result.get()) == nil }
        let result = await OutfitPhotoReader.referenceFace(in: image)
        let thumbnail = image.preparingThumbnail(of: CGSize(width: 300, height: 300)) ?? image
        withAnimation { references.append(Reference(image: thumbnail, result: result)) }
    }

    private func replace(_ id: UUID, with piece: DetectedPiece) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            candidates[index].piece = piece
            candidates[index].thumbnail = PhotoLibraryScanner.thumbnail(of: piece.sticker)
            candidates[index].isRetaken = true
            dropped.remove(id)
        }
    }

    private func backToPicking() {
        readTask?.cancel()
        phase = .picking
    }

    private func save() {
        isSaving = true
        let entries = kept.map { candidate in
            let category = category(of: candidate)
            var piece = candidate.piece
            if category != piece.category {
                piece.category = category
                piece.name = "\(piece.color) \((ClosetCategory(rawValue: category) ?? .tops).noun)"
            }
            return (piece: piece, category: category, retaken: candidate.isRetaken)
        }
        Task {
            do {
                try await OutfitPhotoReader.save(entries)
                store.reloadSaved()
                onDone()
            } catch {
                isSaving = false
                saveFailed = true
            }
        }
    }
}

#Preview {
    OutfitPhotosView(onDone: {}, onCamera: {})
        .environment(ClosetStore())
}
