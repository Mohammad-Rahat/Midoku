// Adapted from Keiyoushi's Apache-2.0 Comix Descrambler; see THIRD_PARTY_NOTICES.md.
// Swift port adds size limits, strict header validation and lossless PNG output.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ComixImageDecoder {
    static func decode(_ response: SourceHTTPResponse, processor: String?) throws -> Data {
        guard processor == "comix-v1" else { return response.body }
        func seed(_ name: String) throws -> UInt32? {
            guard let value = response.header(name) else { return nil }
            guard let number = Int64(value), number >= Int64(Int32.min), number <= Int64(UInt32.max) else { throw ExtensionFailure.invalidResponse("Invalid image seed.") }
            return UInt32(truncatingIfNeeded: number)
        }
        var bytes = response.body
        if let value = try seed("x-enc-seed"), value != 0 {
            guard let raw = response.header("x-enc-len"), let length = Int(raw), length >= 0, length <= 32 * 1024 * 1024 else { throw ExtensionFailure.invalidResponse("Invalid image length.") }
            if response.header("x-enc-algo") == "2" {
                let candidates = [(value | 1, false, false), (value, false, false), (value | 1, true, false), (value, false, true)]
                guard let decoded = candidates.lazy.map({ xor(bytes, seed: $0.0, length: length, high: $0.1, lcg: $0.2) }).first(where: isImage) else { throw ExtensionFailure.invalidResponse("Unknown image encoding.") }
                bytes = decoded
            } else { bytes = xor(bytes, seed: value, length: length, high: true, lcg: true) }
        }
        guard response.header("x-scramble-grid") != nil else { return bytes }
        guard response.header("x-scramble-grid") == "5x5", [nil, "1", "2", "3"].contains(response.header("x-scramble-algo")),
              let value = try seed("x-scramble-seed") else { throw ExtensionFailure.invalidResponse("Unsupported image layout.") }
        guard value != 0 else { return bytes }
        let hash: UInt32
        switch response.header("x-scramble-hash")?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "03632": hash = 58414
        case "02900": hash = 117532
        case nil, "": hash = 0
        default: throw ExtensionFailure.invalidResponse("Unknown image layout version.")
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width >= 5, height >= 5, width <= 20_000, height <= 20_000, width * height <= 40_000_000,
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExtensionFailure.invalidResponse("Invalid image.") }
        context.interpolationQuality = .none
        context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        let order = tileOrder(seed: value ^ hash, xorshift: response.header("x-scramble-algo") == "3")
        let tileW = width / 5, tileH = height / 5
        for destination in 0..<25 {
            let from = order[destination]
            // CGImage crop coordinates start at the top; CGContext's default coordinates start at the bottom.
            guard let tile = original.cropping(to: CGRect(x: (from % 5) * tileW, y: (from / 5) * tileH, width: tileW, height: tileH)) else { throw ExtensionFailure.invalidResponse("Invalid image tile.") }
            context.draw(tile, in: CGRect(x: (destination % 5) * tileW, y: height - (destination / 5 + 1) * tileH, width: tileW, height: tileH))
        }
        guard let image = context.makeImage() else { throw ExtensionFailure.invalidResponse("Image reconstruction failed.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw ExtensionFailure.invalidResponse("Image encoding failed.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 64 * 1024 * 1024 else { throw ExtensionFailure.responseTooLarge }
        return output as Data
    }
    static func xor(_ data: Data, seed: UInt32, length: Int, high: Bool, lcg: Bool) -> Data {
        var bytes = [UInt8](data), state = seed
        for index in 0..<min(bytes.count, max(0, length)) {
            state = lcg ? state &* 1_000_005 &+ 1_234_567_891 : next(state)
            bytes[index] ^= UInt8(truncatingIfNeeded: high ? state >> 24 : state)
        }
        return Data(bytes)
    }
    static func tileOrder(seed: UInt32, xorshift: Bool) -> [Int] {
        var order = Array(0..<25), state = xorshift ? seed | 1 : seed
        for index in stride(from: 24, through: 1, by: -1) {
            state = xorshift ? next(state) : state &* 1_664_525 &+ 1_013_904_223
            order.swapAt(index, Int(state % UInt32(index + 1)))
        }
        var inverse = Array(repeating: 0, count: 25)
        for index in order.indices { inverse[order[index]] = index }
        return inverse
    }
    private static func next(_ value: UInt32) -> UInt32 { var n = value; n ^= n << 13; n ^= n >> 17; n ^= n << 5; return n }
    private static func isImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        return bytes.count >= 12 && (bytes.starts(with: [0xff, 0xd8]) || bytes.starts(with: [0x89, 0x50, 0x4e, 0x47]) ||
            (Array(bytes[0..<4]) == Array("RIFF".utf8) && Array(bytes[8..<12]) == Array("WEBP".utf8)))
    }
}
