import XCTest
import BitChordTestSupport
@testable import BitChordCore

@MainActor
final class LyricsTypographyTests: XCTestCase {
    func testDefaultIsSmallerAndLighterThanOriginal() {
        let value = LyricsTypography.standard
        XCTAssertFalse(value.separateScripts)
        XCTAssertEqual(value.common.size, 32)
        XCTAssertEqual(value.common.weight, .bold)
    }

    func testSeparateChoicesSurviveRestartAndBackup() {
        let defaults = makeEphemeralDefaults()
        let source = AppSettings(defaults: defaults, credentials: InMemoryCredentialStore())
        source.lyricsTypography.separateScripts = true
        source.lyricsTypography.korean = LyricsFontChoice(size: 28, weight: .medium)
        source.lyricsTypography.english = LyricsFontChoice(size: 35, weight: .semibold)
        let restored = AppSettings(defaults: defaults, credentials: InMemoryCredentialStore())
        XCTAssertEqual(restored.lyricsTypography, source.lyricsTypography)
        let other = AppSettings(defaults: makeEphemeralDefaults(), credentials: InMemoryCredentialStore())
        other.importPrefs(source.exportPrefs())
        XCTAssertEqual(other.lyricsTypography, source.lyricsTypography)
    }

    func testChangingCommonModeRetainsPerScriptChoices() {
        var value = LyricsTypography.standard
        value.english = LyricsFontChoice(size: 30, weight: .regular)
        value.korean = LyricsFontChoice(size: 33, weight: .bold)
        value.separateScripts = false
        value.common.size = 26
        let restored = LyricsTypography.restore(value.persisted)
        XCTAssertEqual(restored.english, value.english)
        XCTAssertEqual(restored.korean, value.korean)
        XCTAssertEqual(restored.common.size, 26)
    }

    func testInvalidStoredDataRestoresUsableDefaults() {
        XCTAssertEqual(LyricsTypography.restore("broken"), .standard)
        var value = LyricsTypography.standard
        value.korean.size = 900
        value.english.size = -1
        value.common.size = .nan
        let restored = LyricsTypography.restore(value.persisted)
        XCTAssertEqual(restored.korean.size, 44)
        XCTAssertEqual(restored.english.size, 22)
        XCTAssertEqual(restored.common.size, 32)
    }
}
