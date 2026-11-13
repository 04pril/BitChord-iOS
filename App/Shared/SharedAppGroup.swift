import Foundation
import Security
import Darwin

/// Resolve the group actually granted to this process after sideload re-signing.
/// A defaults suite alone is not proof that the app and extension share a container.
enum SharedAppGroup {
    static let declaredIdentifier = "group.com.music.bitchord.logincheck1113204816"
    static let signedIdentifiers: [String]? = readSignedIdentifiers()
    static var packagedWidgetIdentifiers: [String]? {
        var host = Bundle.main
        if host.bundleURL.pathExtension == "appex" {
            host = Bundle(url: host.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) ?? host
        }
        guard let widget = Bundle(url: host.bundleURL.appending(path: "PlugIns/BitChordWidgetExtension.appex")) else { return nil }
        return SignedApplicationGroups.read(widget)
    }
    static let selection: (identifier: String, container: URL)? = {
        let own = signedIdentifiers
        var bundle = Bundle.main
        if bundle.bundleURL.pathExtension == "appex" {
            bundle = Bundle(url: bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()) ?? bundle
        }
        let hostGroup = "group." + (bundle.bundleIdentifier ?? "com.music.bitchord.logincheck1113204816")
        let granted = own ?? [declaredIdentifier]
        var candidates = [hostGroup, declaredIdentifier].filter { granted.contains($0) }
        candidates += granted.filter { $0.lowercased().contains("bitchord") }.sorted()
        if granted.count == 1 { candidates += granted }
        // A sideload profile can replace the original group with several numbered IDs
        // that do not contain the app name. Keep only IDs present on both this process
        // and the widget, in one sorted order, so both open the same container.
        if let widgetGroups = packagedWidgetIdentifiers {
            let shared = Set(widgetGroups)
            candidates += granted.filter { shared.contains($0) }.sorted()
        }
        var seen = Set<String>()
        for identifier in candidates where seen.insert(identifier).inserted {
            if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                return (identifier, container)
            }
        }
        return nil
    }()

    static var defaults: UserDefaults? {
        guard let selection else { return nil }
        return UserDefaults(suiteName: selection.identifier)
    }
    static var containerURL: URL? { selection?.container }
    static var diagnostics: String {
        "bundle=\(Bundle.main.bundleIdentifier ?? "unknown")\nsignedGroups=\(signedIdentifiers.map { $0.joined(separator: ", ") } ?? "unavailable")\npackagedWidgetGroups=\(packagedWidgetIdentifiers.map { $0.joined(separator: ", ") } ?? "unavailable")\nselectedGroup=\(selection?.identifier ?? "none")\nsharedContainer=\(containerURL == nil ? "unavailable" : "available")"
    }

    static func probeContainer() throws {
        guard let container = containerURL else {
            throw NSError(domain: "BitChordWidget", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group shared container is unavailable"])
        }
        let file = container.appending(path: "widget-probe-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(UUID().uuidString.utf8)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard try Data(contentsOf: file) == data else {
            throw NSError(domain: "BitChordWidget", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Shared container read-back failed"])
        }
    }

    private static func readSignedIdentifiers() -> [String]? {
        if let groups = SignedApplicationGroups.read(Bundle.main) { return groups.filter { !$0.isEmpty } }
        // Like the existing sideload MediaRemote patch, resolve Security task introspection
        // dynamically: these symbols are not declared in the public iOS SDK.
        typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
        typealias Copy = @convention(c) (CFTypeRef, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let createSymbol = dlsym(handle, "SecTaskCreateFromSelf"),
              let copySymbol = dlsym(handle, "SecTaskCopyValueForEntitlement"),
              let task = unsafeBitCast(createSymbol, to: Create.self)(nil)?.takeRetainedValue() else { return nil }
        let value = unsafeBitCast(copySymbol, to: Copy.self)(task, "com.apple.security.application-groups" as CFString, nil)?.takeRetainedValue()
        guard let value else { return [] }
        return (value as? [String])?.filter { !$0.isEmpty }
    }
}
