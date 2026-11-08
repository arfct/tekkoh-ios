import ImageIO
import Photos
import PhotosUI
import SwiftUI

/// The day's photos, like prints taped into the notebook: a caption under
/// each, typed in place; a small × to take one out; the day's own camera
/// roll offered above, one tap to add.
struct PhotoShelf: View {
    enum Layout { case strip, grid }

    let journal: Journal
    let day: String
    let layout: Layout
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: Photo?
    @State private var adding = 0

    var body: some View {
        let photos = journal.entry(day).photos
        VStack(alignment: .leading, spacing: 10) {
            DaySuggestions(journal: journal, day: day, adding: $adding)
            switch layout {
            case .strip:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(photos) { p in card(p).frame(width: 168) }
                        addTile.frame(width: 110, height: 150)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
            case .grid:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(photos) { p in card(p) }
                    addTile.frame(height: 150)
                }
            }
        }
        .sheet(item: $viewing) { p in PhotoViewer(journal: journal, day: day, photo: p) }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await add(items) }
        }
    }

    private func card(_ p: Photo) -> some View {
        PhotoCard(journal: journal, day: day, photo: p) { viewing = p }
            .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.9))))
    }

    private var addTile: some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 12, matching: .images, photoLibrary: .shared()) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Ink.faint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                if adding > 0 {
                    ProgressView()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 20, weight: .light))
                        Text("PHOTO").font(.label(9)).tracking(2)
                    }
                    .foregroundStyle(Ink.muted)
                }
            }
        }
        .accessibilityLabel("Add photos")
    }

    private func add(_ items: [PhotosPickerItem]) async {
        adding += items.count
        for item in items {
            defer { adding -= 1 }
            guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { continue }
            let taken = Self.takenAt(data)
            withAnimation(.spring(duration: 0.4)) {
                try? journal.addPhoto(img, to: day, takenAt: taken, asset: item.itemIdentifier)
            }
        }
    }

    /// When the photo was taken, from its EXIF.
    static func takenAt(_ data: Data) -> Date? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}

/// A print with its caption underneath.
struct PhotoCard: View {
    let journal: Journal
    let day: String
    let photo: Photo
    let open: () -> Void
    @State private var image: UIImage?
    @State private var caption = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Ink.paperEdge
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(.rect)
            .onTapGesture(perform: open)
            TextField("add a caption", text: $caption, axis: .vertical)
                .font(.serif(13).italic())
                .foregroundStyle(Ink.text)
                .lineLimit(1...3)
                .focused($editing)
                .submitLabel(.done)
                .onSubmit { editing = false }
        }
        .padding(7)
        .background(Ink.card, in: .rect(cornerRadius: 2))
        .shadow(color: .black.opacity(0.10), radius: 3, y: 1.5)
        .rotationEffect(.degrees(tilt))
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.spring(duration: 0.35)) { journal.removePhoto(photo, from: day) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ink.muted)
                    .frame(width: 22, height: 22)
                    .background(Ink.card, in: .circle)
                    .overlay(Circle().strokeBorder(Ink.grid, lineWidth: 0.5))
            }
            .offset(x: 7, y: -7)
            .accessibilityLabel("Remove photo")
        }
        .contextMenu {
            Button("Edit caption", systemImage: "character.cursor.ibeam") { editing = true }
            Button("Remove", systemImage: "trash", role: .destructive) {
                withAnimation(.spring(duration: 0.35)) { journal.removePhoto(photo, from: day) }
            }
        }
        .task(id: photo.id) {
            caption = photo.caption
            image = await journal.image(photo)
        }
        .onChange(of: editing) { _, e in
            if !e, caption != photo.caption { journal.caption(photo, in: day, caption) }
        }
        .task(id: caption) {
            guard caption != photo.caption else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { journal.caption(photo, in: day, caption) }
        }
    }

    /// Prints sit a little crooked, each its own way.
    private var tilt: Double {
        let h = photo.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Double(h % 5) * 0.35 - 0.7
    }
}

/// The photos taken that day, not yet on the page.
struct DaySuggestions: View {
    let journal: Journal
    let day: String
    @Binding var adding: Int
    @State private var assets: [PHAsset] = []
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        Group {
            if status == .authorized || status == .limited {
                if !fresh.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FROM THIS DAY").font(.label(9)).tracking(2).foregroundStyle(Ink.faint)
                            .padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(fresh, id: \.localIdentifier) { a in
                                    AssetThumb(asset: a) { Task { await add(a) } }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            } else if status == .notDetermined, day >= Day.add(-7, to: Day.today) {
                Button {
                    Task {
                        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        load()
                    }
                } label: {
                    Label("Show this day's photos", systemImage: "photo.on.rectangle.angled")
                        .font(.label(10)).foregroundStyle(Ink.muted)
                }
                .padding(.horizontal, 20)
            }
        }
        .task(id: day) { load() }
    }

    private var fresh: [PHAsset] {
        let used = Set(journal.entry(day).photos.compactMap(\.asset))
        return assets.filter { !used.contains($0.localIdentifier) }
    }

    private func load() {
        guard status == .authorized || status == .limited else { return }
        let span = Day.interval(day)
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
                                     span.start as NSDate, span.end as NSDate, PHAssetMediaType.image.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        opts.fetchLimit = 60
        var out: [PHAsset] = []
        PHAsset.fetchAssets(with: opts).enumerateObjects { a, _, _ in
            if !a.mediaSubtypes.contains(.photoScreenshot) { out.append(a) }
        }
        assets = out
    }

    private func add(_ a: PHAsset) async {
        adding += 1
        defer { adding -= 1 }
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        let img: UIImage? = await withCheckedContinuation { c in
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 2048, height: 2048), contentMode: .aspectFit, options: opts) { img, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                c.resume(returning: img)
            }
        }
        guard let img else { return }
        withAnimation(.spring(duration: 0.4)) {
            try? journal.addPhoto(img, to: day, takenAt: a.creationDate, asset: a.localIdentifier)
        }
    }
}

struct AssetThumb: View {
    let asset: PHAsset
    let tap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: tap) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFill() } else { Ink.paperEdge }
                }
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 3))
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Ink.vermillion)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add photo from \(asset.creationDate?.formatted(date: .omitted, time: .shortened) ?? "this day")")
        .task {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 140, height: 140), contentMode: .aspectFill, options: opts) { img, _ in
                if let img { image = img }
            }
        }
    }
}

/// One photo, large, with its caption.
struct PhotoViewer: View {
    let journal: Journal
    let day: String
    let photo: Photo
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var caption = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TextField("add a caption", text: $caption, axis: .vertical)
                    .font(.serif(17).italic())
                    .multilineTextAlignment(.center)
                    .lineLimit(1...4)
                    .padding(.horizontal, 24)
                if let t = photo.takenAt {
                    Text(t.formatted(date: .omitted, time: .shortened)).font(.label(10)).foregroundStyle(Ink.faint)
                }
            }
            .padding(.vertical, 16)
            .background(PageBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if caption != photo.caption { journal.caption(photo, in: day, caption) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        journal.removePhoto(photo, from: day)
                        dismiss()
                    }
                }
            }
            .task {
                caption = photo.caption
                image = await journal.image(photo, full: true)
            }
        }
    }
}
