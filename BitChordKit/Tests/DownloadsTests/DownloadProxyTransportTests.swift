import BitChordCore
import Foundation
import Network
import XCTest
@testable import Downloads

final class DownloadProxyTransportTests: XCTestCase {
    func testAppLocalConfigurationKeepsTransfersInTheAppWithoutAnAutomaticCookieJar() {
        let config = URLSessionDownloadTransport.appLocalConfiguration()
        XCTAssertNil(config.identifier)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCache)
        XCTAssertEqual(config.timeoutIntervalForResource, 3600)
        XCTAssertEqual(config.timeoutIntervalForRequest, BitChordHTTP.requestTimeout)
    }

    func testAnAppLocalTransportReleasesAnObsoleteBackgroundEventCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = URLSessionDownloadTransport.appLocal(stagingDirectory: root)
        defer { transport.invalidate() }
        let completed = expectation(description: "background callback completed")
        transport.handleBackgroundEvents { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 2)
    }

    /// Opt-in real Foundation/Network proxy integration, using only a local fixture server.
    func testARealProxiedDownloadPreservesHeadersAndRange() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let port = env["BITCHORD_DOWNLOAD_TEST_PROXY_PORT"].flatMap(UInt16.init),
              let rawURL = env["BITCHORD_DOWNLOAD_TEST_URL"], let url = URL(string: rawURL) else {
            throw XCTSkip("Local proxy fixture is not running")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        var proxy = env["BITCHORD_DOWNLOAD_TEST_PROXY_KIND"] == "http"
            ? ProxyConfiguration(httpCONNECTProxy: endpoint) : ProxyConfiguration(socksv5Proxy: endpoint)
        proxy.allowFailover = false
        proxy.applyCredential(username: "u-fixture", password: "p-fixture")
        let config = URLSessionDownloadTransport.appLocalConfiguration()
        config.proxyConfigurations = [proxy]
        let transport = URLSessionDownloadTransport(configuration: config, stagingDirectory: root)
        defer { transport.invalidate() }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        request.setValue("download-fixture-client", forHTTPHeaderField: "User-Agent")
        request.setValue("fixture-session=1", forHTTPHeaderField: "Cookie")
        let result = try await transport.download(request, key: "fixture", progress: nil)
        XCTAssertEqual(result.statusCode, 206)
        XCTAssertEqual(try Data(contentsOf: result.fileURL), Data("0123456789".utf8))
    }
}
