import SwiftUI
import WidgetKit

// Gallery order: the two Liquid Artwork cards first, followed by the three original widgets.

@main
struct BitChordWidgetBundle: WidgetBundle {
    var body: some Widget {
        PosterWideWidget()
        PosterSquareWidget()
        NowPlayingSquareWidget()
        NowPlayingWideWidget()
        NowPlayingPillWidget()
    }
}

/// "Now playing 2×2".
struct NowPlayingSquareWidget: Widget {
    static let kind = "com.music.bitchord.widget.square"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            CompactWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetSquareLabel)
        .description(SharedStrings.widgetSquareDescription)
        .supportedFamilies([.systemSmall])
        // The band runs edge to edge over the cover, as on Android; the views pad themselves.
        .contentMarginsDisabled()
    }
}

/// "Now playing 4×2".
struct NowPlayingWideWidget: Widget {
    static let kind = "com.music.bitchord.widget.wide"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            WideWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetWideLabel)
        .description(SharedStrings.widgetWideDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// "Now playing 4×1". iOS has no one-row Home Screen size; the medium slot is the closest.
struct NowPlayingPillWidget: Widget {
    static let kind = "com.music.bitchord.widget.pill"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            PillWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetPillLabel)
        .description(SharedStrings.widgetPillDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// Poster 2×2, added beside the original square widget.
struct PosterSquareWidget: Widget {
    static let kind = "com.music.bitchord.widget.poster.square"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            PosterSquareWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetPosterSquareLabel)
        .description(SharedStrings.widgetPosterSquareDescription)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// Poster 4×2, the wide colour card.
struct PosterWideWidget: Widget {
    static let kind = "com.music.bitchord.widget.poster.wide"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            PosterWideWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetPosterWideLabel)
        .description(SharedStrings.widgetPosterWideDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
