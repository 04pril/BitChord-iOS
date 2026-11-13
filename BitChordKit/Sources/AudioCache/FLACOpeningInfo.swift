import Foundation

/// Reads metadata already cached at offset zero; never scans audio frames or changes bytes.
struct FLACOpeningInfo {
    let sampleRate: Int?
    let channels: Int?
    let bitDepth: Int?
    let totalSamples: UInt64?
    let seekPoints: Int?
    let metadataComplete: Bool

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, Array(bytes.prefix(4)) == Array("fLaC".utf8) else { return nil }
        var sampleRate: Int?
        var channels: Int?
        var bitDepth: Int?
        var totalSamples: UInt64?
        var seekPoints: Int?
        var complete = false
        var offset = 4
        while offset + 4 <= bytes.count {
            let last = bytes[offset] & 0x80 != 0
            let type = bytes[offset] & 0x7f
            let length = Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let body = offset + 4
            guard length <= bytes.count - body else { break }
            if type == 0, length == 34 {
                var packed: UInt64 = 0
                for byte in bytes[(body + 10)..<(body + 18)] { packed = packed << 8 | UInt64(byte) }
                sampleRate = Int(packed >> 44)
                channels = Int((packed >> 41) & 7) + 1
                bitDepth = Int((packed >> 36) & 31) + 1
                totalSamples = packed & 0x0f_ffff_ffff
            } else if type == 3, length % 18 == 0 {
                var count = 0
                for point in stride(from: body, to: body + length, by: 18) {
                    if !bytes[point..<(point + 8)].allSatisfy({ $0 == 0xff }) { count += 1 }
                }
                seekPoints = count
            }
            offset = body + length
            if last { complete = true; break }
        }
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.totalSamples = totalSamples
        self.seekPoints = seekPoints ?? (complete ? 0 : nil)
        self.metadataComplete = complete
    }

    var summary: String {
        "sampleRate=\(sampleRate.map { String($0) } ?? "unknown") channels=\(channels.map { String($0) } ?? "unknown") bitDepth=\(bitDepth.map { String($0) } ?? "unknown") totalSamples=\(totalSamples.map { String($0) } ?? "unknown") seekPoints=\(seekPoints.map { String($0) } ?? "unknown") metadataComplete=\(metadataComplete)"
    }
}
