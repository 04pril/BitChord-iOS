import Foundation
import MachO

/// Read XML entitlements from our own signed Mach-O file when Security task introspection is
/// unavailable. This inspects the signature only; authorization remains enforced by iOS.
enum SignedApplicationGroups {
    static func read(_ bundle: Bundle) -> [String]? {
        guard let file = bundle.executableURL,
              let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count >= 32 else { return nil }
        func word(_ at: Int, big: Bool = false) -> UInt32 {
            let bytes = (0..<4).map { UInt32(data[at + $0]) }
            return big ? bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
                : bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24
        }
        guard word(0) == MH_MAGIC_64 else { return nil }
        let commands = Int(word(16)), commandBytes = Int(word(20))
        guard commandBytes <= data.count - 32, commands <= commandBytes / 8 else { return nil }
        var cursor = 32
        for _ in 0..<commands {
            guard cursor <= 32 + commandBytes - 8 else { return nil }
            let command = word(cursor), size = Int(word(cursor + 4))
            guard size >= 8, size <= 32 + commandBytes - cursor else { return nil }
            if command == LC_CODE_SIGNATURE {
                guard size >= 16 else { return nil }
                let start = Int(word(cursor + 8)), length = Int(word(cursor + 12))
                guard length >= 12, start <= data.count - length,
                      word(start, big: true) == 0xfade0cc0 else { return nil }
                let blobLength = Int(word(start + 4, big: true))
                let count = Int(word(start + 8, big: true))
                guard blobLength >= 12, blobLength <= length, count <= (blobLength - 12) / 8 else { return nil }
                for index in 0..<count {
                    let slot = start + 12 + index * 8
                    guard word(slot, big: true) == 5 else { continue }
                    let offset = Int(word(slot + 4, big: true))
                    guard offset <= blobLength - 8 else { return nil }
                    let blob = start + offset
                    let bytes = Int(word(blob + 4, big: true))
                    guard word(blob, big: true) == 0xfade7171, bytes >= 8, bytes <= blobLength - offset,
                          let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: (blob + 8)..<(blob + bytes)), options: [], format: nil) as? [String: Any] else { return nil }
                    return plist["com.apple.security.application-groups"] as? [String] ?? []
                }
                return nil // DER-only signatures use the Security fallback.
            }
            cursor += size
        }
        return nil
    }
}
