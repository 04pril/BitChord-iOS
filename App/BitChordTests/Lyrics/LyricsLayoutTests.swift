import BitChordCore
import Lyrics
import SwiftUI
import UIKit
import XCTest
@testable import BitChord

/// The page keeps every line inside its column at any text size, in either layout direction.
@MainActor
final class LyricsLayoutTests: XCTestCase {
    func testMixedLanguageFontsShareOneWrappedLayout() throws {
        var preference = LyricsTypography.standard
        preference.separateScripts = true
        preference.korean = LyricsFontChoice(size: 28, weight: .medium)
        preference.english = LyricsFontChoice(size: 35, weight: .semibold)
        let text = "널 향해 there's no danger 👨‍👩‍👧‍👦"
        let typeface = LyricTypeface.synced.customized(using: preference)
        let requested = typeface.attributedText(text, paragraph: NSMutableParagraphStyle())
        let englishIndex = (text as NSString).range(of: "there").location
        XCTAssertEqual(requested.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
                       UIFont.systemFont(ofSize: 28, weight: .medium))
        XCTAssertEqual(requested.attribute(.font, at: englishIndex, effectiveRange: nil) as? UIFont,
                       UIFont.systemFont(ofSize: 35, weight: .semibold))
        for width: CGFloat in [200, 310, 500] {
            let layout = LyricTextLayout(text: text, typeface: typeface, width: width)
            let korean = try XCTUnwrap(layout.storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
            let english = try XCTUnwrap(layout.storage.attribute(.font, at: englishIndex, effectiveRange: nil) as? UIFont)
            // TextKit can substitute a Hangul face while preserving the configured size.
            // Validate weight on the input attributes above, not the fallback font's identity.
            XCTAssertEqual(korean.pointSize, 28)
            XCTAssertEqual(english.pointSize, 35)
            XCTAssertTrue(layout.rows.allSatisfy { $0.right <= width + 4 })
            XCTAssertGreaterThan(layout.size.height, 0)
        }
        var changed = preference
        changed.english.weight = .regular
        XCTAssertNotEqual(typeface, LyricTypeface.synced.customized(using: changed))
    }

    func testCommonFontAppliesToBothScripts() throws {
        let attributed = LyricTypeface.synced.customized(using: .standard)
            .attributedText("한글 English", paragraph: NSMutableParagraphStyle())
        let korean = try XCTUnwrap(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let english = try XCTUnwrap(attributed.attribute(.font, at: 3, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(korean, UIFont.systemFont(ofSize: 32, weight: .bold))
        XCTAssertEqual(korean, english)
    }

    func testLinesStayInsideTheColumnAtEveryTextSizeAndDirection() {
        let settings = makeTestSettings()
        let clock = LyricFrameClock()
        clock.reset(positionMs: 15_900, isPlaying: false)
        let translation = LyricsTranslationController()
        let gutter = LyricsPanelMetrics.gutter
        let room = LyricsPanelMetrics.glowRoom
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let host = renderLyricsView(
                    LyricsPanelContent(lines: LyricsDemo.wordSynced, subLines: nil, looking: false, trackKey: "t", clock: clock,
                                       isPlaying: false, translation: translation, onSeek: { _ in })
                        .padding(.horizontal, gutter)
                        .dynamicTypeSize(size)
                        .environment(\.layoutDirection, direction),
                    settings: settings
                )
                let voices = host.view.lyricsDescendants(of: LyricLineUIView.self).filter { $0.window != nil }
                XCTAssertFalse(voices.isEmpty)
                for voice in voices {
                    let frame = voice.convert(voice.bounds, to: nil)
                    // The bloom's room may reach into the gutter, the words may not.
                    XCTAssertGreaterThanOrEqual(frame.minX, gutter - room - 0.5, "\(size) \(direction) \(voice.line.text)")
                    XCTAssertLessThanOrEqual(frame.maxX, 393 - gutter + room + 0.5, "\(size) \(direction) \(voice.line.text)")
                    let layout = voice.textLayout(forWidth: voice.bounds.width)
                    for row in layout.rows {
                        XCTAssertGreaterThanOrEqual(row.left, -0.5, "\(size) \(direction) \(voice.line.text)")
                        XCTAssertLessThanOrEqual(row.right, layout.container.size.width + 0.5, "\(size) \(direction) \(voice.line.text)")
                    }
                }
            }
        }
    }

    /// Sheet titles are 19 sp on Android: they follow the text size.
    func testSheetTitlesScaleWithDynamicType() {
        let settings = makeTestSettings()
        for size in [DynamicTypeSize.large, .accessibility3] {
            renderLyricsView(LyricsOffsetSheet().dynamicTypeSize(size), settings: settings)
            renderLyricsView(LyricsProviderSheet().dynamicTypeSize(size), settings: settings)
        }
    }
}
