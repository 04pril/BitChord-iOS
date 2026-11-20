import AVFoundation
import AudioCache
import BitChordCore
import XCTest
@testable import Playback

/// Error recovery on the engine: a failed item is retried at its position through the injected
/// re-resolve closure, a permanently unplayable one is skipped, a vanished download is streamed.
@MainActor
final class PlaybackRecoveryEngineTests: EngineTestCase {
    struct AgeGated: PermanentPlaybackError {
        var verdict: String { "age-restricted" }
    }

    func testConnectionOutageKeepsSameTrackAndPositionUntilRecovery() async throws {
        let good = try ToneFile.tone(8, in: directory, name: "outage-resume")
        let attempts = ConnectionAttempts()
        let item = PlayableItem(id: "outage", title: "N", artist: "A", source: .asset {
            if await attempts.open() == 1 { throw URLError(.cannotConnectToHost) }
            return AVURLAsset(url: good)
        })
        let next = try tone(3, name: "outage-next")
        let h = harness(queue: [item, next])
        h.engine.connectionHealth = { await attempts.check() > 1 }
        h.engine.load(item, startingAt: 2, playWhenReady: true)
        await waitUntil("waiting for connection") { h.engine.isRecoveringConnection }
        XCTAssertEqual(h.engine.currentItem?.id, item.id)
        XCTAssertEqual(h.engine.position, 2, accuracy: 0.05)
        XCTAssertTrue(h.delegate.failures.isEmpty)
        await waitUntil("same track resumed", timeout: 8) { h.engine.isPlaying }
        XCTAssertEqual(h.engine.currentItem?.id, item.id)
        XCTAssertGreaterThanOrEqual(h.engine.position, 1.9)
        XCTAssertFalse(h.engine.isRecoveringConnection)
    }

    func testPauseCancelsConnectionWaitWithoutLaterResuming() async throws {
        let item = PlayableItem(id: "offline", title: "N", artist: "A", source: .asset { throw URLError(.cannotConnectToHost) })
        let h = harness(queue: [item])
        h.engine.connectionHealth = { false }
        h.engine.load(item, playWhenReady: true)
        await waitUntil("waiting") { h.engine.isRecoveringConnection }
        h.engine.pause()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(h.engine.isRecoveringConnection)
        XCTAssertFalse(h.engine.playWhenReady)
        XCTAssertFalse(h.engine.isPlaying)
        XCTAssertEqual(h.engine.currentItem?.id, item.id)
    }

    func testSkipCancelsConnectionWaitAndDoesNotReopenOldTrack() async throws {
        let item = PlayableItem(id: "offline-skip", title: "N", artist: "A", source: .asset { throw URLError(.cannotConnectToHost) })
        let next = try tone(5, name: "outage-skip-target")
        let h = harness(queue: [item, next])
        h.engine.connectionHealth = { false }
        h.engine.load(item, playWhenReady: true)
        await waitUntil("waiting") { h.engine.isRecoveringConnection }
        h.engine.load(next, playWhenReady: true)
        await waitUntil("next playing") { h.engine.isPlaying }
        XCTAssertEqual(h.engine.currentItem?.id, next.id)
        XCTAssertFalse(h.engine.isRecoveringConnection)
        XCTAssertTrue(h.delegate.failures.isEmpty)
    }

    func testFullyBufferedShortTrackDoesNotHoldBackgroundPreparation() async throws {
        let item = try tone(4, name: "short-buffer-priority")
        let h = harness(queue: [item])
        h.engine.load(item, playWhenReady: true)
        await waitUntil("playing") { h.engine.isPlaying }
        await waitUntil("short file fully buffered") { !h.engine.hasBufferPressure }
        XCTAssertFalse(h.engine.hasBufferPressure)
        h.engine.pause()
        XCTAssertFalse(h.engine.hasBufferPressure)
    }

    func testHTTPRefusalsDoNotQualifyForProxyRepair() {
        for code in [401, 403, 429, 503] {
            XCTAssertFalse(AudioPlayerEngine.isConnectionFailure(AudioCache.AudioCacheError.httpStatus(code, url: URL(string: "https://example.com")!)))
        }
        XCTAssertTrue(AudioPlayerEngine.isConnectionFailure(URLError(.cannotConnectToHost)))
        XCTAssertFalse(AudioPlayerEngine.isConnectionFailure(URLError(.cancelled)))
    }

    private actor ConnectionAttempts {
        var opens = 0
        var checks = 0
        func open() -> Int { opens += 1; return opens }
        func check() -> Int { checks += 1; return checks }
    }

    /// A file that claims to be audio and isn't.
    func garbage(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent("\(name).m4a")
        try Data(repeating: 0x5A, count: 4_096).write(to: url)
        return url
    }

    func testAFailedItemIsRetriedThroughTheRecoveryClosure() async throws {
        let good = try ToneFile.tone(4, in: directory, name: "recover-good")
        let bad = try garbage("recover-bad")
        let item = PlayableItem(id: "recover", title: "R", artist: "A", source: .asset { AVURLAsset(url: bad) })
        let h = harness(queue: [item])
        var reasons: [RecoveryReason] = []
        h.engine.sourceRecovery = { failed, reason in
            XCTAssertEqual(failed.id, "recover")
            reasons.append(reason)
            return .file(good)
        }
        h.engine.load(item, playWhenReady: true)
        await waitUntil("recovered and playing") { h.engine.isPlaying }
        XCTAssertEqual(reasons, [.retry(attempt: 1)])
        XCTAssertEqual(h.delegate.failures.count, 1)
        XCTAssertEqual(h.delegate.failures.first?.willRetry, true)
        XCTAssertEqual(h.delegate.failures.first?.error.itemID, "recover")
        XCTAssertEqual(h.delegate.changes.map(\.reason), [.requested], "a retry is not a new item")
        XCTAssertEqual(h.engine.currentItem?.id, "recover")
        XCTAssertNil(h.engine.lastError, "the error comes off once the retry plays")
    }

    /// A failure that was the connection's is told apart from one that was the file's, so the app
    /// keeps the copies on disk in full.
    func testARetryAfterANetworkFaultSaysSo() async throws {
        let good = try ToneFile.tone(4, in: directory, name: "recover-network")
        let item = PlayableItem(id: "network", title: "N", artist: "A", source: .asset { throw URLError(.networkConnectionLost) })
        let h = harness(queue: [item])
        var reasons: [RecoveryReason] = []
        h.engine.sourceRecovery = { _, reason in
            reasons.append(reason)
            return .file(good)
        }
        h.engine.load(item, playWhenReady: true)
        await waitUntil("recovered and playing") { h.engine.isPlaying }
        XCTAssertEqual(reasons, [.retry(attempt: 1, networkFault: true)])
    }

    func testTheRetryResumesWhereTheStreamDied() async throws {
        let good = try ToneFile.tone(8, in: directory, name: "recover-position")
        let bad = try garbage("recover-position-bad")
        let item = PlayableItem(id: "recover-pos", title: "R", artist: "A", source: .asset { AVURLAsset(url: bad) })
        let h = harness(queue: [item])
        h.engine.sourceRecovery = { _, _ in .file(good) }
        h.engine.load(item, startingAt: 3, playWhenReady: true)
        await waitUntil("playing") { h.engine.isPlaying }
        XCTAssertGreaterThanOrEqual(h.engine.position, 2.9, "a retry sounds like a hiccup, not the song starting over")
    }

    func testAnItemThatKeepsFailingIsSkippedAfterTwoRetries() async throws {
        let bad = try garbage("recover-dead")
        let dead = PlayableItem(id: "dead", title: "D", artist: "A", source: .asset { AVURLAsset(url: bad) })
        let next = try tone(3, name: "recover-next")
        let h = harness(queue: [dead, next])
        var attempts: [RecoveryReason] = []
        h.engine.sourceRecovery = { _, reason in
            attempts.append(reason)
            return nil // no alternative: the item's own factory is opened again
        }
        h.engine.load(dead, playWhenReady: true)
        await waitUntil("moved past it", timeout: 6) { h.engine.currentItem?.id == next.id }
        XCTAssertEqual(attempts, [.retry(attempt: 1), .retry(attempt: 2)])
        XCTAssertEqual(h.delegate.failures.map(\.willRetry), [true, true, false])
        guard case .skippedUnplayable = h.delegate.changes.last?.reason else {
            return XCTFail("expected a skip, got \(String(describing: h.delegate.changes.last?.reason))")
        }
        await waitUntil("next playing") { h.engine.isPlaying }
        XCTAssertTrue(h.engine.playWhenReady, "an error doesn't clear the intent to play")
    }

    func testAPermanentVerdictSkipsAtOnce() async throws {
        let blocked = PlayableItem(id: "blocked", title: "B", artist: "A", source: .asset { throw AgeGated() })
        let next = try tone(3, name: "recover-after-verdict")
        let h = harness(queue: [blocked, next])
        var asked = 0
        h.engine.sourceRecovery = { _, _ in
            asked += 1
            return nil
        }
        h.engine.load(blocked, playWhenReady: true)
        await waitUntil("skipped", timeout: 4) { h.engine.currentItem?.id == next.id }
        XCTAssertEqual(asked, 0, "no retry for a track that can never play")
        XCTAssertEqual(h.delegate.failures.count, 1)
        XCTAssertEqual(h.delegate.failures.first?.willRetry, false)
        XCTAssertEqual(h.delegate.failures.first?.error.isPermanent, true)
        XCTAssertEqual(h.delegate.changes.last?.reason, .skippedUnplayable(reason: "age-restricted"))
    }

    func testAPermanentFailureWithNothingAfterItParksWithTheErrorShowing() async throws {
        let blocked = PlayableItem(id: "blocked-last", title: "B", artist: "A", source: .asset { throw AgeGated() })
        let h = harness(queue: [blocked])
        h.engine.load(blocked, playWhenReady: true)
        await waitUntil("failed") { h.engine.lastError != nil && !h.engine.isBuffering }
        XCTAssertEqual(h.engine.lastError?.isPermanent, true)
        XCTAssertTrue(h.engine.lastError?.message.contains("age-restricted") ?? false)
        XCTAssertEqual(h.engine.currentItem?.id, "blocked-last")
    }

    func testAVanishedDownloadIsStreamedInstead() async throws {
        let stream = try ToneFile.tone(3, in: directory, name: "recover-stream")
        let missing = directory.appendingPathComponent("gone.m4a")
        let item = PlayableItem(id: "downloaded", title: "D", artist: "A", source: .file(missing))
        let h = harness(queue: [item])
        var reasons: [RecoveryReason] = []
        h.engine.sourceRecovery = { _, reason in
            reasons.append(reason)
            guard case .missingLocalFile = reason else { return nil }
            return .stream { ResolvedStream(url: stream, origin: .youtube, mimeType: "audio/x-caf") }
        }
        h.engine.load(item, playWhenReady: true)
        await waitUntil("streaming") { h.engine.isPlaying }
        XCTAssertEqual(reasons, [.missingLocalFile(missing)])
        XCTAssertEqual(h.engine.currentItem?.id, "downloaded")
    }
}

/// Stats for nerds as measured off the playing item.
@MainActor
final class PlaybackStatsEngineTests: EngineTestCase {
    func testAnAACFileReportsItsCodecRateAndBitrate() async throws {
        let url = try ToneFile.write([.tone(frequency: 440, seconds: 3)], to: directory, name: "stats-aac", container: .aac(bitrate: 128_000))
        let item = PlayableItem(id: "stats-aac", title: "S", artist: "A", source: .file(url), declaredFormat: StreamFormat(codec: "aac", kbps: 128))
        let h = harness(queue: [item])
        h.engine.load(item, playWhenReady: true)
        await waitUntil("stats sampled") { h.engine.stats?.itemID == item.id && h.engine.stats?.codec != nil }
        let stats = try XCTUnwrap(h.engine.stats)
        XCTAssertEqual(stats.codec, "aac")
        XCTAssertEqual(stats.sampleRateHz, 44_100)
        XCTAssertEqual(stats.channels, 2)
        // The container's average rate: what the encoder actually spent, which on a pure sine is
        // far below the 128 kbps it was asked for.
        let rate = try XCTUnwrap(stats.estimatedBitrateKbps)
        XCTAssertGreaterThan(rate, 8)
        XCTAssertLessThanOrEqual(rate, 160)
        XCTAssertEqual(stats.declared?.kbps, 128)
        XCTAssertNotNil(stats.bitrateKbps)
    }

    func testAPCMFileShowsTheLosslessDataRate() async throws {
        let item = try tone(3, name: "stats-pcm")
        let h = harness(queue: [item])
        h.engine.load(item, playWhenReady: false)
        await waitUntil("stats sampled") { h.engine.stats?.codec != nil }
        let stats = try XCTUnwrap(h.engine.stats)
        XCTAssertEqual(stats.codec, "lpcm")
        XCTAssertEqual(stats.bitDepth, 32)
        XCTAssertEqual(stats.bitrateKbps, 44_100 * 2 * 32 / 1_000)
        XCTAssertEqual(stats.measuredFormat.sampleRateHz, 44_100)
    }

    func testStatsAreDroppedWhenTheItemChanges() async throws {
        let first = try tone(3, name: "stats-first")
        let second = try tone(3, frequency: 550, name: "stats-second")
        let h = harness(queue: [first, second])
        h.engine.load(first, playWhenReady: false)
        await waitUntil("stats") { h.engine.stats?.itemID == first.id }
        h.engine.load(second, playWhenReady: false)
        XCTAssertNil(h.engine.stats, "never the previous track's numbers under the new title")
        await waitUntil("new stats") { h.engine.stats?.itemID == second.id }
    }

    func testCodecNamesFollowTheContainer() {
        XCTAssertEqual(PlaybackStatsSampler.codecName(kAudioFormatMPEG4AAC_HE), "aac")
        XCTAssertEqual(PlaybackStatsSampler.codecName(kAudioFormatFLAC), "flac")
        XCTAssertEqual(PlaybackStatsSampler.codecName(kAudioFormatAppleLossless), "alac")
        XCTAssertEqual(PlaybackStatsSampler.codecName(kAudioFormatEnhancedAC3), "ec-3")
        XCTAssertEqual(PlaybackStatsSampler.codecName(kAudioFormatOpus), "opus")
    }
}
