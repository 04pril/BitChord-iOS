import AudioCache
import AVFoundation
import BitChordCore
import XCTest
@testable import Playback

/// Keep app-owned assets on the sender. Real AirPlay receiver output needs a device check;
/// these tests cover the player policy and offline cache playback it must preserve.
@MainActor
final class AirPlayPlaybackTests: EngineTestCase {
    func testBothAudioDecksKeepAppOwnedLoadingAfterMediaServicesReset() {
        let h = harness()
        let originalA = h.engine.active.player
        let originalB = h.engine.standby.player
        XCTAssertFalse(originalA.allowsExternalPlayback)
        XCTAssertFalse(originalB.allowsExternalPlayback)

        h.engine.handleAudioSessionEvent(.mediaServicesReset)

        XCTAssertFalse(h.engine.active.player === originalA)
        XCTAssertFalse(h.engine.standby.player === originalB)
        XCTAssertFalse(h.engine.active.player.allowsExternalPlayback)
        XCTAssertFalse(h.engine.standby.player.allowsExternalPlayback)
    }

    func testCachedAACStillPlaysPausesAndSeeksWithSenderSideRendering() async throws {
        let fragments = try await FragmentedAAC.make(seconds: 8, segmentSeconds: 2)
        let bytes = fragments.segments.reduce(into: fragments.initialization) { $0.append($1.data) }
        let server = try LocalHTTPServer()
        defer { server.stop() }
        server.serve("/audio.m4a", bytes, contentType: "audio/mp4")
        try await server.start()
        let cache = try AudioStreamCache(configuration: .init(
            directory: directory.appendingPathComponent("cache"), limitBytes: 16 * 1_024 * 1_024,
            minimumFreeBytes: 0, availableCapacity: { _ in 1_024 * 1_024 * 1_024 }))
        let key = AudioCacheKey.youtube(videoId: "airplay-cache")
        let source = HTTPAudioSource(stream: ResolvedStream(
            url: server.baseURL.appendingPathComponent("audio.m4a"), origin: .youtube, mimeType: "audio/mp4",
            contentLength: Int64(bytes.count)),
                                     session: .init(configuration: .ephemeral))
        await cache.warmRange(key, source: source, range: 0..<Int64(bytes.count))
        // A fetch can hand over its last bytes before the disk span is committed. Go offline
        // only after that commit, just as the app's whole-on-disk check requires.
        let deadline = ContinuousClock.now + .seconds(5)
        while !(await cache.isFullyCached(key)), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let complete = await cache.isFullyCached(key)
        guard complete else {
            return XCTFail("fixture cache fill failed: \(TrackLog.shared.heldLines.suffix(12).map(\.text))")
        }
        server.stop()

        let item = PlayableItem(id: "airplay-cache", title: "Cached AAC", artist: "Test", source: .asset {
            cache.makeAsset(for: key, source: nil)
        })
        let h = harness(queue: [item], scansAheadForSilence: false)
        h.engine.load(item, playWhenReady: true)
        await waitUntil("cached AAC playing") { h.engine.isPlaying && h.engine.position > 0.3 }
        XCTAssertEqual((h.engine.active.current?.asset as? AVURLAsset)?.url.scheme, AudioStreamCache.urlScheme)
        XCTAssertFalse(h.engine.active.player.allowsExternalPlayback)
        let processor = try XCTUnwrap(h.processors[h.engine.activeDeckID])
        await waitUntil("local audio processing receives samples") { processor.frames > 0 }

        h.engine.pausePlayback()
        XCTAssertFalse(h.engine.playWhenReady)
        h.engine.seek(to: 4)
        h.engine.play()
        await waitUntil("cached AAC plays after seek") { h.engine.isPlaying && h.engine.position > 4.2 }
        XCTAssertTrue(h.delegate.failures.isEmpty, "\(h.delegate.failures)")
        XCTAssertNil(h.engine.lastError)
    }
}
