import Foundation
import Testing
@testable import MidokuExtensions

@Suite("Comix image permissions")
struct ComixPermissionTests {
    @Test func bothObservedImageShardFamiliesAreAllowedButLookalikesAreNot() throws {
        let resource = try #require(BundledExtensionResources.entries.first { $0.manifestJSON.contains("dev.midoku.comix") })
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(resource.manifestJSON.utf8))
        try manifest.validate()
        let policy = SourceRequestPolicy(domains: manifest.domains)
        for host in ["jloo.wowpic1.store", "jdpw.wowpic1.store", "j24n.wowpic2.store"] {
            try policy.validate(try #require(URL(string: "https://" + host + "/page.jpg")))
        }
        for address in ["https://wowpic1.store/page.jpg", "https://evilwowpic1.store/page.jpg",
                        "https://jloo.wowpic1.store.evil.org/page.jpg", "https://127.0.0.1/page.jpg",
                        "http://jloo.wowpic1.store/page.jpg", "https://jloo.wowpic1.store:8443/page.jpg",
                        "https://unreviewed.example/page.jpg"] {
            let url = try #require(URL(string: address))
            #expect(throws: ExtensionFailure.requestNotAllowed) { try policy.validate(url) }
        }
        #expect(throws: ExtensionFailure.requestNotAllowed) { try policy.validate(headers: ["Cookie": "invalid"]) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let authored = try JSONDecoder().decode(ExtensionManifest.self,
            from: Data(contentsOf: root.appending(path: "Extensions/sources/dev.midoku.comix/manifest.json")))
        #expect(manifest == authored)
    }
}
