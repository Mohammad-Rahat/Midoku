import Foundation
import Testing
import CoreGraphics
import ImageIO
@testable import MidokuExtensions

@Suite("Comix image decoding")
struct ComixImageTests {
    @Test func gridRestoresTilePositionsAndPreservesRemainderPixels() throws {
        let width = 12, height = 13
        var pixels: [UInt8] = []
        for y in 0..<height { for x in 0..<width {
            let value = x < 10 && y < 10 ? UInt8((y / 2 * 5 + x / 2) * 8) : 250
            pixels += [value, value, value, 255]
        } }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let original = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let target = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(target, original, nil)
        #expect(CGImageDestinationFinalize(target))
        let response = SourceHTTPResponse(url: try #require(URL(string: "https://comix.to/image")), status: 200,
            headers: ["x-scramble-grid":"5x5", "x-scramble-seed":"42", "x-scramble-algo":"1"], body: encoded as Data)
        let decoded = try ComixImageDecoder.decode(response, processor: "comix-v1")
        let source = try #require(CGImageSourceCreateWithData(decoded as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // Reference vector from upstream's UInt32 LCG permutation for seed 42.
        let expected = [4,10,2,22,23,3,0,5,8,12,14,9,21,6,13,11,18,7,17,16,19,20,1,24,15]
        for y in 0..<height { for x in 0..<width {
            let tile = try #require(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            let sample = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            sample.draw(tile, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let data = try #require(sample.data).assumingMemoryBound(to: UInt8.self)
            let value = x < 10 && y < 10 ? expected[y / 2 * 5 + x / 2] * 8 : 250
            #expect(abs(Int(data[0]) - value) <= 1)
        } }
    }
    @Test func xorRoundTripAndTailPreservation() throws {
        let original = Data([0xff, 0xd8, 0xff, 0xe0] + Array(0...60))
        for lcg in [false, true] {
            let encoded = ComixImageDecoder.xor(original, seed: 42, length: 24, high: lcg, lcg: lcg)
            #expect(encoded.suffix(20) == original.suffix(20))
            #expect(encoded != original)
            #expect(ComixImageDecoder.xor(encoded, seed: 42, length: 24, high: lcg, lcg: lcg) == original)
        }
    }
    @Test func permutationAndMalformedHeaders() throws {
        for mode in [false, true] {
            #expect(ComixImageDecoder.tileOrder(seed: 42, xorshift: mode).sorted() == Array(0..<25))
        }
        let url = try #require(URL(string: "https://comix.to/i/page.jpg"))
        let response = SourceHTTPResponse(url: url, status: 200, headers: ["X-Scramble-Grid":"6x6"], body: Data([1,2,3]))
        #expect(throws: ExtensionFailure.self) { try ComixImageDecoder.decode(response, processor: "comix-v1") }
        #expect(try ComixImageDecoder.decode(response, processor: nil) == response.body)
    }
}
