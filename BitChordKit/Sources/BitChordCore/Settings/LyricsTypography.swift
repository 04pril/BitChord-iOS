import Foundation

public enum LyricsFontWeight: String, Codable, CaseIterable, Hashable, Sendable {
    case regular, medium, semibold, bold, heavy
}

public struct LyricsFontChoice: Codable, Hashable, Sendable {
    public var size: Double
    public var weight: LyricsFontWeight

    public init(size: Double = 32, weight: LyricsFontWeight = .bold) {
        self.size = size
        self.weight = weight
    }

    public var normalized: Self {
        Self(size: size.isFinite ? min(max(size, 22), 44) : 32, weight: weight)
    }
}

/// Common typography, or per-script choices in the same mixed-language line.
public struct LyricsTypography: Codable, Hashable, Sendable {
    public var separateScripts = false
    public var common = LyricsFontChoice()
    public var korean = LyricsFontChoice()
    public var english = LyricsFontChoice()

    public init() {}
    public static let standard = LyricsTypography()

    public var normalized: Self {
        var result = self
        result.common = common.normalized
        result.korean = korean.normalized
        result.english = english.normalized
        return result
    }

    public var persisted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(normalized)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    public static func restore(_ string: String) -> Self {
        guard let data = string.data(using: .utf8),
              let result = try? JSONDecoder().decode(Self.self, from: data) else { return .standard }
        return result.normalized
    }
}
