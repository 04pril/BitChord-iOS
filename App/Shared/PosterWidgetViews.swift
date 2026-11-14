import SwiftUI

// Poster cards added beside the original three widgets. The wide card follows WidgetPod's medium
// now-playing widget: Liquid Artwork, curved cover, track/artist and Apple Music glyph.

struct PosterBackground: View {
    var art: WidgetArt?

    var body: some View {
        if let art {
            Image(uiImage: art.wash)
                .resizable()
                .widgetFullColorArtwork()
                .accessibilityHidden(true)
        } else {
            Color(uiColor: WidgetArt.posterFallbackBackground)
        }
    }
}

struct PosterCover: View {
    var art: WidgetArt?
    var side: CGFloat
    var cornerRadius: CGFloat? = nil

    /// WidgetPod's curved cover is about 11.5% of the art side.
    private var radius: CGFloat { cornerRadius ?? min(max(side * 0.115, 8), side * 0.2) }

    var body: some View {
        Group {
            if let art {
                Image(uiImage: art.cover).resizable()
                    .widgetFullColorArtwork().scaledToFill()
            } else {
                WidgetPlaceholderArt()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
        .shadow(color: .black.opacity(0.22), radius: max(4, side * 0.045), y: max(2, side * 0.03))
        .accessibilityLabel(SharedStrings.widgetArtwork)
    }
}
/// Apple Music player icon in Glyph style: two beamed eighth notes, using the reference silhouette.
struct PosterNote: View {
    var art: WidgetArt?
    var size: CGFloat

    var body: some View {
        Image(uiImage: UIImage(named: "WidgetMusicGlyph") ?? UIImage())
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.77).opacity(art == nil ? 0.55 : 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Previous, play/pause and next. The skip marks are the same `backward.fill` / `forward.fill`
/// glyphs the original 4×1 uses.
struct PosterTransport: View {
    var face: WidgetFace
    var skip: CGFloat
    var pause: CGFloat
    var height: CGFloat
    var spacing: CGFloat = 28
    /// Wide card: the three controls sit across the column, with the play button in the middle.
    var spreads = false

    var body: some View {
        HStack(spacing: spreads ? 0 : spacing) {
            WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill", label: SharedStrings.widgetPrevious,
                          opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: skip, height: height, fillsWidth: false)
            if spreads { Spacer(minLength: 0) }
            WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol, label: face.toggleLabel,
                          opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: pause, height: height, fillsWidth: false)
            if spreads { Spacer(minLength: 0) }
            WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill", label: SharedStrings.widgetNext,
                          opacity: face.opacity(.next), isLive: face.hasTrack, glyph: skip, height: height, fillsWidth: false)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PosterTitles: View {
    var face: WidgetFace
    var title: CGFloat
    var artist: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text(face.title)
                .font(.system(size: title, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if face.hasTrack, let name = face.artist {
                Text(name)
                    .font(.system(size: artist, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The reference’s small card is its own layout: upper-left artwork, upper-right glyph,
/// then single-line title and artist aligned left above a full-width transport row.
struct PosterSquareWidgetView: View {
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?
    var canvas: WidgetCanvas = .widgetKit

    var body: some View {
        let face = WidgetFace(snapshot)
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 158
            ZStack(alignment: .topLeading) {
                PosterCover(art: art, side: 67 * scale, cornerRadius: 10.5 * scale)
                    .position(x: 49 * scale, y: 49 * scale)
                Text(face.title)
                    .font(.system(size: 12.5 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 127 * scale, height: 18 * scale, alignment: .leading)
                    .position(x: 79 * scale, y: 95 * scale)
                if face.hasTrack, let artist = face.artist {
                    Text(artist)
                        .font(.system(size: 12.5 * scale, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                        .frame(width: 127 * scale, height: 18 * scale, alignment: .leading)
                        .position(x: 79 * scale, y: 111 * scale)
                }
                WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill", label: SharedStrings.widgetPrevious,
                              opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 16.5 * scale,
                              height: 36 * scale, fillsWidth: false, weight: .regular)
                    .position(x: 26 * scale, y: 135.5 * scale)
                WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol, label: face.toggleLabel,
                              opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 26 * scale,
                              height: 36 * scale, fillsWidth: false, weight: .regular)
                    .position(x: 79 * scale, y: 135.5 * scale)
                WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill", label: SharedStrings.widgetNext,
                              opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 16.5 * scale,
                              height: 36 * scale, fillsWidth: false, weight: .regular)
                    .position(x: 132 * scale, y: 135.5 * scale)
                PosterNote(art: art, size: 22 * scale)
                    .position(x: 132 * scale, y: 26 * scale)
            }
            .frame(width: 158 * scale, height: 158 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .dynamicTypeSize(.large)
        .widgetBackground(canvas, inlineCornerRadius: 26) { PosterBackground(art: art) }
        .overlay {
            if canvas == .inline {
                RoundedRectangle(cornerRadius: 26, style: .circular)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                    .allowsHitTesting(false)
            } else {
                ContainerRelativeShape()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
        }
        .widgetURL(SharedConstants.openPlayerURL)
    }
}

/// WidgetPod reference: default artwork, curved corners, Liquid Artwork, title and artist.
/// Measured in a 338×158 medium widget; explicit bounds keep long titles and Dynamic Type
/// from pushing the controls into the artwork or out to the edges.
struct PosterWideWidgetView: View {
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?
    var canvas: WidgetCanvas = .widgetKit

    var body: some View {
        let face = WidgetFace(snapshot)
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 338, proxy.size.height / 158)
            ZStack(alignment: .topLeading) {
                PosterCover(art: art, side: 135.5 * scale)
                    .position(x: 79.25 * scale, y: 79 * scale)
                VStack(spacing: 2 * scale) {
                    Text(face.title)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 148 * scale)
                    if face.hasTrack, let artist = face.artist {
                        Text(artist)
                            .font(.system(size: 13.5 * scale, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                            .frame(width: 148 * scale)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 148 * scale)
                .position(x: 243 * scale, y: 64 * scale)
                WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill", label: SharedStrings.widgetPrevious,
                              opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 18 * scale,
                              height: 38 * scale, fillsWidth: false, weight: .regular)
                    .position(x: 183 * scale, y: 119 * scale)
                WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol, label: face.toggleLabel,
                              opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 26 * scale,
                              height: 38 * scale, fillsWidth: false, weight: .regular)
                    .position(x: 243 * scale, y: 119 * scale)
                WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill", label: SharedStrings.widgetNext,
                              opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 18 * scale,
                              height: 38 * scale, fillsWidth: false, weight: .regular)
                    .position(x: 303 * scale, y: 119 * scale)
                PosterNote(art: art, size: 22 * scale)
                    .position(x: 312 * scale, y: 25 * scale)
            }
            .frame(width: 338 * scale, height: 158 * scale)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .dynamicTypeSize(.large)
        .widgetBackground(canvas, inlineCornerRadius: 26) { PosterBackground(art: art) }
        .overlay {
            if canvas == .inline {
                RoundedRectangle(cornerRadius: 26, style: .circular)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                    .allowsHitTesting(false)
            } else {
                ContainerRelativeShape()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6)
                    .allowsHitTesting(false)
            }
        }
        .widgetURL(SharedConstants.openPlayerURL)
    }
}

/// systemMedium row. Same field, cover and buttons.
struct PosterPillWidgetView: View {
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?
    var canvas: WidgetCanvas = .widgetKit

    var body: some View {
        let face = WidgetFace(snapshot)
        GeometryReader { proxy in
            let side = min(max(68, proxy.size.height - 40), 100) * 1.04
            HStack(alignment: .center, spacing: 14) {
                PosterCover(art: art, side: side)
                VStack(spacing: 10) {
                    PosterTitles(face: face, title: 16, artist: 13)
                    PosterTransport(face: face, skip: 16, pause: 20, height: 30, spacing: 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                PosterNote(art: art, size: 20).padding(.top, 10).padding(.trailing, 12)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .widgetBackground(canvas) { PosterBackground(art: art) }
        .widgetURL(SharedConstants.openPlayerURL)
    }
}
