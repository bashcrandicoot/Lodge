import SwiftUI
import AppKit

/// A file's picture: its Quick Look thumbnail, a symbol for formats macOS can't draw,
/// or (in demo mode) a theme-coloured placeholder.
struct MediaThumbnail: View {
    let clip: Clip
    let provider: ThumbnailProvider
    /// The longer side, in points.
    var points: CGFloat = 160
    /// Small list-row thumbnails leave out the file-type text.
    var compact = false

    @Environment(\.displayScale) private var scale
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var loadedKey: ThumbnailKey?

    private var fileName: String { clip.url.lastPathComponent }
    private var hasThumbnail: Bool { MediaPreviewSupport.hasThumbnail(fileName: fileName) }

    var body: some View {
        let key = ThumbnailKey(clip: clip, points: points, scale: scale)
        ZStack {
            if let image, loadedKey == key {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if provider.usesPlaceholders && hasThumbnail {
                placeholder
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityHidden(true)
        .task(id: key) {
            // Lazy: only tiles on screen ask, and leaving the screen cancels the request.
            if let hit = provider.cachedImage(for: key) {
                image = hit
                loadedKey = key
                return
            }
            guard hasThumbnail, !provider.usesPlaceholders else { return }
            let result = await provider.image(for: clip, key: key)
            guard !Task.isCancelled, let result else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                image = result
                loadedKey = key
            }
        }
    }

    /// Demo thumbnails: a slice of the theme's gradient, different for every file.
    private var placeholder: some View {
        let t = Double(StableHash.of(fileName) % 1000) / 1000
        return LinearGradient(colors: [theme.placeholder(t), theme.placeholder((t + 0.45).truncatingRemainder(dividingBy: 1))],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: clip.category.symbol)
                    .font(.system(size: max(9, points * 0.18), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
    }

    /// No picture: a quiet tile with the file's symbol (and type, e.g. "BRAW").
    private var fallback: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: MediaPreviewSupport.fallbackSymbol(fileName: fileName))
                        .font(.system(size: compact ? max(9, points * 0.4) : max(12, points * 0.16)))
                    if !compact {
                        Text(MediaPreviewSupport.fileExtension(fileName).uppercased())
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(.secondary)
                .opacity(hasThumbnail && !provider.usesPlaceholders ? 0.5 : 1)   // a thumbnail may still be on its way
            }
    }
}

/// A small, stable hash (Swift's `hashValue` changes on every launch).
enum StableHash {
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// What a grid tile shows about its file.
struct MediaTileInfo {
    enum Status: Equatable {
        /// Will be copied.
        case pending
        /// Being copied now, 0…1.
        case copying(Double)
        /// Copied and checked.
        case verified
        /// Offloaded before, copy still there.
        case offloaded
        /// Offloaded before, but the copy is gone.
        case missing
        /// A short clip left on the card.
        case skipped
    }

    let clip: Clip
    /// The new name (or the card name for files that aren't being copied).
    let name: String
    var detail: String
    var duration: Double?
    var sidecars = 0
    var status: Status = .pending
    var isReoffload = false
    var isIncludedShort = false
    var isPlaceholderName = false

    var accessibilityText: String {
        var text = "\(clip.category.title), \(name)"
        if name != clip.url.lastPathComponent { text += ", from \(clip.url.lastPathComponent)" }
        if let duration { text += ", \(DurationFormatting.short(duration)) long" }
        if sidecars > 0 { text += sidecars == 1 ? ", with 1 sidecar" : ", with \(sidecars) sidecars" }
        switch status {
        case .pending: break
        case .copying: text += ", copying now"
        case .verified: text += ", copied and verified"
        case .offloaded: text += ", already offloaded"
        case .missing: text += ", copy missing at the destination"
        case .skipped: text += ", short clip, skipped"
        }
        if isIncludedShort { text += ", short clip included anyway" }
        if isReoffload { text += ", will be re-offloaded" }
        return text
    }
}

/// One tile in the Media grid.
struct MediaTile: View {
    let info: MediaTileInfo
    let provider: ThumbnailProvider
    var isSelected = false

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var isDimmed: Bool { info.status == .offloaded || info.status == .skipped }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay { picture }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(Color.primary.opacity(0.1)),
                                      lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .topLeading) { typeBadge.padding(5) }
                .overlay(alignment: .topTrailing) { statusBadge.padding(5) }
                .overlay(alignment: .bottomTrailing) { durationBadge.padding(5) }
                .overlay { centerOverlay }
                .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.08), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(info.isPlaceholderName || isDimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(info.detail)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if info.sidecars > 0 {
                        Label("+\(info.sidecars)", systemImage: "paperclip")
                            .labelStyle(.titleAndIcon)
                            .fixedSize()
                            .help(info.sidecars == 1 ? "Has 1 sidecar file, copied with it" : "Has \(info.sidecars) sidecar files, copied with it")
                    }
                    if info.isIncludedShort {
                        Image(systemName: "timer")
                            .foregroundStyle(theme.accent)
                            .help("Shorter than the “Skip short videos” limit, included anyway")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.14) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .hoverLift(cornerRadius: 11)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.55), value: info.status)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var picture: some View {
        MediaThumbnail(clip: info.clip, provider: provider, points: 180)
            .saturation(isDimmed ? 0.25 : 1)
            .opacity(isDimmed ? 0.45 : 1)
            .overlay {
                if info.status == .skipped { StripeOverlay().opacity(0.5) }
            }
    }

    private var typeBadge: some View {
        Image(systemName: info.clip.category.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(.black.opacity(0.45), in: Circle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch info.status {
        case .verified:
            badge("checkmark.circle.fill", .green)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
        case .offloaded:
            if info.isReoffload { badge("arrow.clockwise.circle.fill", theme.accent, on: theme.onAccent) } else { badge("checkmark.circle.fill", .secondary) }
        case .missing:
            badge("exclamationmark.triangle.fill", .orange)
                .help("Copy missing at the destination")
        case .pending:
            if info.isReoffload { badge("arrow.clockwise.circle.fill", theme.accent, on: theme.onAccent).help("Will be copied again as a new copy") }
        case .copying, .skipped:
            EmptyView()
        }
    }

    private func badge(_ symbol: String, _ color: Color, on foreground: Color = .white) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(foreground, color)
            .background(Circle().fill(.black.opacity(0.25)).padding(1))
    }

    @ViewBuilder
    private var durationBadge: some View {
        if let duration = info.duration {
            Text(DurationFormatting.short(duration))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.black.opacity(0.55), in: Capsule())
        }
    }

    @ViewBuilder
    private var centerOverlay: some View {
        switch info.status {
        case .copying(let fraction):
            ProgressRing(fraction: fraction, color: theme.accent)
                .frame(width: 30, height: 30)
                .padding(6)
                .background(.black.opacity(0.4), in: Circle())
                .transition(.opacity)
        case .skipped:
            Label("Skipped", systemImage: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
        default:
            EmptyView()
        }
    }
}

/// A thin ring that fills clockwise.
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
        }
        .accessibilityElement()
        .accessibilityLabel("Copying")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Diagonal stripes for files that are being left on the card.
struct StripeOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 9
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(.primary.opacity(0.35)), lineWidth: 2.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// List / Grid switch for the Media stage.
struct MediaLayoutPicker: View {
    @Binding var layout: MediaLayout

    var body: some View {
        Picker("View", selection: $layout) {
            ForEach(MediaLayout.allCases) { layout in
                Label(layout.title, systemImage: layout.symbol)
                    .labelStyle(.iconOnly)
                    .help("Show as \(layout.title.lowercased())")
                    .tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .themeControlTint()
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("View as")
    }
}

/// "No preview available for .braw", shown next to a file Quick Look can't open.
struct NoPreviewPopover: View {
    let fileName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No preview available for .\(MediaPreviewSupport.fileExtension(fileName))", systemImage: "eye.slash")
                .font(.callout.weight(.semibold))
            Text("Quick Look can’t open this camera format.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }
}
