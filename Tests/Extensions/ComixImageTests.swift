import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Comix image decoding")
struct ComixImageTests {
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
