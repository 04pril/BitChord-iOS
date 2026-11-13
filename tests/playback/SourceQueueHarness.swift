import AudioCache
import AVFoundation
import BitChordCore
import Foundation
import Playback
import Sources

// Tests compile the actual app factory and its segmented-source/DSP/timeout collaborators.
// Only the remote catalogue and HTTP server are doubles. No device audio is played here.
private struct QueueCheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw QueueCheckFailure(description: message) }
}

private final class QueueHTTP: URLProtocol, @unchecked Sendable {
    static let body = Data(repeating: 42, count: 4 * 1_024 * 1_024 + 17)
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "queue.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let text = request.value(forHTTPHeaderField: "Range") ?? "bytes=0-"
        let bounds = text.replacingOccurrences(of: "bytes=", with: "").split(separator: "-", omittingEmptySubsequences: false)
        let lower = Int(bounds.first ?? "0") ?? 0
        let upper = min(Int(bounds.last ?? "") ?? (Self.body.count - 1), Self.body.count - 1)
        guard lower >= 0, lower <= upper else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let headers = ["Content-Type": "audio/flac", "Accept-Ranges": "bytes",
                       "Content-Length": String(upper - lower + 1),
                       "Content-Range": "bytes \(lower)-\(upper)/\(Self.body.count)"]
        let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body.subdata(in: lower..<(upper + 1)))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class QueueCatalogue: StreamResolving, @unchecked Sendable {
    struct Call { let id: String; let request: StreamRequest }
    private let lock = NSLock()
    private var calls: [Call] = []
    private var held = false
    init(held: Bool = false) { self.held = held }
    var log: [Call] { lock.withLock { calls } }
    func release() { lock.withLock { held = false } }
    func resolveStream(for song: Song, request: StreamRequest) async throws -> ResolvedStream {
        lock.withLock { calls.append(Call(id: song.videoId, request: request)) }
        if request.waitsForSources && request.permits(.addon) {
            while lock.withLock({ held }) { try await Task.sleep(for: .milliseconds(10)) }
            return ResolvedStream(url: URL(string: "https://queue.test/\(song.videoId).flac")!, origin: .addon,
                                  mimeType: "audio/flac", format: StreamFormat(codec: "flac"))
        }
        return ResolvedStream(url: URL(string: "https://queue.test/\(song.videoId).m4a")!, origin: .youtube,
                              mimeType: "audio/mp4", format: StreamFormat(codec: "aac", kbps: 128))
    }
}

@main
private struct SourceQueueHarness {
    @MainActor
    private static func until(_ message: String, timeout: Duration = .seconds(10),
                              _ condition: () async -> Bool) async throws {
        let end = ContinuousClock.now + timeout
        while !(await condition()) {
            if ContinuousClock.now >= end { throw QueueCheckFailure(description: message) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private static func fixture(request: StreamRequest, catalogue: QueueCatalogue = QueueCatalogue(),
                                unmetered: Bool = false, allowMetered: Bool = false)
        throws -> (PlaybackSourceFactory, AudioStreamCache, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "source-queue-\(UUID())")
        let cache = try AudioStreamCache(configuration: .init(directory: folder, minimumFreeBytes: 0, prefetchDelay: .zero,
            queueWarmUpStagger: .zero, availableCapacity: { _ in nil }))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueueHTTP.self]
        let factory = PlaybackSourceFactory(resolver: catalogue, youTube: catalogue, cache: cache,
            facts: StreamFactsBook(), session: URLSession(configuration: configuration), request: { request }, atmosAllowed: { true })
        factory.isPinnedToOriginal = { _ in false }
        factory.canSubstitute = { $0.permits(.addon) }
        factory.isUnmetered = { unmetered }
        factory.preloadNextOnMetered = { allowMetered }
        factory.isSounding = { true }
        return (factory, cache, folder)
    }

    @MainActor
    private static func bytes(_ cache: AudioStreamCache, _ id: String) async -> Int64 {
        await cache.cachedRanges(of: .substitute(videoId: id, atmosAllowed: true))
            .reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }

    @MainActor
    private static func queueCaching(unmetered: Bool, allowMetered: Bool) async throws {
        let catalogue = QueueCatalogue()
        let request = StreamRequest.playback(.lossless, directSource: .always, sourceWaitSeconds: 5)
        let (factory, cache, folder) = try fixture(request: request, catalogue: catalogue,
                                                  unmetered: unmetered, allowMetered: allowMetered)
        defer { try? FileManager.default.removeItem(at: folder) }
        let songs = (0..<6).map { Song(videoId: "track\($0)", title: "Track \($0)", artist: "Artist") }
        let plan = factory.prefetchItems(for: songs)
        try check(plan.count == 4, "prepare four upcoming tracks, not the whole queue")
        await cache.prefetch(plan)
        let full = unmetered || allowMetered
        try await until("queue copies were not cached") {
            let first = await bytes(cache, "track0")
            guard first == (full ? Int64(QueueHTTP.body.count) : PlaybackSourceFactory.openingBytes) else { return false }
            for i in 1..<4 {
                if await bytes(cache, "track\(i)") != PlaybackSourceFactory.openingBytes { return false }
            }
            return true
        }
        try await Task.sleep(for: .milliseconds(100))
        for i in 1..<4 {
            let held = await bytes(cache, "track\(i)")
            try check(held == PlaybackSourceFactory.openingBytes, "farther tracks must retain only their opening")
        }
        try check(Set(catalogue.log.map(\.id)) == Set(songs.prefix(4).map(\.videoId)), "only four catalogue lookups")
        try check(catalogue.log.count == 4, "the full-track pass and URL preparation must share their lookup")
        try check(catalogue.log.allSatisfy { $0.request.waitsForSources && $0.request.readsAheadFromSources }, "background lookups use the background budget")
        await cache.cancelPrefetch()
    }

    @MainActor
    private static func meteredYouTubeFallback() async throws {
        let request = StreamRequest.playback(.medium, directSource: .always, sourceWaitSeconds: 5)
        let catalogue = QueueCatalogue()
        let (factory, cache, folder) = try fixture(request: request, catalogue: catalogue)
        defer { try? FileManager.default.removeItem(at: folder) }
        let songs = (0..<4).map { Song(videoId: "backup\($0)", title: "Backup \($0)", artist: "Artist") }
        let plan = factory.prefetchItems(for: songs)
        try check(plan.first?.source == nil, "mobile fallback must not schedule a full-file pass")
        await cache.prefetch(plan)
        try await until("YouTube fallback openings were not prepared") {
            for song in songs {
                let held = await cache.cachedRanges(of: .youtube(videoId: song.videoId))
                    .reduce(Int64(0)) { $0 + $1.upperBound - $1.lowerBound }
                if held != PlaybackSourceFactory.openingBytes { return false }
            }
            return true
        }
        try await Task.sleep(for: .milliseconds(100))
        let held = await cache.cachedRanges(of: .youtube(videoId: songs[0].videoId))
            .reduce(Int64(0)) { $0 + $1.upperBound - $1.lowerBound }
        try check(held == PlaybackSourceFactory.openingBytes, "mobile fallback must stop at the opening")
        await cache.cancelPrefetch()
    }

    @MainActor
    private static func preparedCopy() async throws {
        let request = StreamRequest.playback(.lossless, directSource: .always, sourceWaitSeconds: 5)
        let catalogue = QueueCatalogue()
        let (factory, cache, folder) = try fixture(request: request, catalogue: catalogue)
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = Song(videoId: "ready", title: "Ready", artist: "Artist")
        let ready = ResolvedStream(url: URL(string: "https://queue.test/ready.flac")!, origin: .addon,
                                   mimeType: "audio/flac", format: StreamFormat(codec: "flac"))
        factory.readAheadStreams.put(ready, for: song.videoId, request: request, atmosAllowed: true)
        factory.isPlaying = { _ in true }
        guard case .resolvedAsset(let open) = factory.item(for: song).source else { throw QueueCheckFailure(description: "expected stream factory") }
        let result = try await open()
        try check(result.stream?.origin == .addon, "ready addon copy should start directly")
        try check(catalogue.log.isEmpty, "a prepared copy must not be searched again")
        await cache.cancelPrefetch()
    }

    @MainActor
    private static func pendingCopy(answerWithinBudget: Bool) async throws {
        let request = StreamRequest.playback(.lossless, directSource: .always, sourceWaitSeconds: 0.25)
        let catalogue = QueueCatalogue(held: true)
        let (factory, cache, folder) = try fixture(request: request, catalogue: catalogue)
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = Song(videoId: "pending", title: "Pending", artist: "Artist")
        let warm = Task { try await factory.prefetchItems(for: [song]).first?.warmUp?() }
        try await until("background lookup did not start") { !catalogue.log.isEmpty }
        factory.playbackRequested(song)
        factory.isPlaying = { _ in true }
        if answerWithinBudget {
            Task { try? await Task.sleep(for: .milliseconds(60)); catalogue.release() }
        }
        guard case .resolvedAsset(let open) = factory.item(for: song).source else { throw QueueCheckFailure(description: "expected stream factory") }
        let began = ContinuousClock.now
        let result = try await open()
        let elapsed = began.duration(to: .now)
        try check(elapsed < .milliseconds(700), "joining a background lookup must not add another foreground wait")
        try check(result.stream?.origin == (answerWithinBudget ? .addon : .youtube), "wrong selected source")
        if !answerWithinBudget {
            try check(elapsed >= .milliseconds(180), "addon-first should spend its configured join budget")
            try check(catalogue.log.count == 2, "one shared background lookup, then one YouTube-only backup")
            let backup = catalogue.log.last!.request
            try check(!backup.waitsForSources && backup.permittedSources == [.youtube], "fallback must not re-arm addons")
        } else {
            try check(catalogue.log.count == 1, "a timely queue result should be reused")
        }
        catalogue.release()
        _ = try? await warm.value
        try await Task.sleep(for: .milliseconds(100))
        try check(factory.facts.stream(for: factory.engineItemID(for: song))?.origin == result.stream?.origin,
                  "a late background answer must not replace the current stream")
        await cache.cancelPrefetch()
    }

    @MainActor
    private static func fastMode() async throws {
        let catalogue = QueueCatalogue()
        let request = StreamRequest.playback(.lossless, directSource: .off)
        let (factory, cache, folder) = try fixture(request: request, catalogue: catalogue)
        defer { try? FileManager.default.removeItem(at: folder) }
        let song = Song(videoId: "fast", title: "Fast", artist: "Artist")
        try await factory.prefetchItems(for: [song]).first?.warmUp?()
        try check(catalogue.log.count == 1 && catalogue.log[0].request.permittedSources == [.youtube],
                  "fast mode must remain YouTube-only")
        await cache.cancelPrefetch()
    }

    @MainActor static func main() async throws {
        try await queueCaching(unmetered: true, allowMetered: false)
        print("PASS wifi: full next track, three openings, shared lookups")
        try await queueCaching(unmetered: false, allowMetered: false)
        print("PASS metered default: openings only")
        try await queueCaching(unmetered: false, allowMetered: true)
        print("PASS metered opt-in: full next track only")
        try await meteredYouTubeFallback()
        print("PASS metered YouTube fallback: no whole-file pass")
        try await preparedCopy()
        print("PASS ready addon copy reused without lookup")
        try await pendingCopy(answerWithinBudget: true)
        print("PASS pending addon answer inside start budget")
        try await pendingCopy(answerWithinBudget: false)
        print("PASS deadline fallback: no second wait or late source replacement")
        try await fastMode()
        print("PASS fast mode remains YouTube-only")
        print("Source queue integration: 8 cases passed")
    }
}
