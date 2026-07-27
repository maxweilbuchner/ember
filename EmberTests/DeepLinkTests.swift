// DeepLinkTests.swift

import Foundation
import Testing
@testable import Ember

@Suite("Deep links")
struct DeepLinkTests {
    @Test func parsesCapture() {
        #expect(DeepLink(url: URL(string: "ember://capture")!) == .capture)
        #expect(DeepLink(url: URL(string: "EMBER://Capture")!) == .capture, "scheme and host are case-insensitive")
    }

    @Test func parsesCompose() {
        let id = UUID()
        let link = DeepLink(url: URL(string: "ember://compose/\(id.uuidString)")!)
        #expect(link == .compose(id))
    }

    @Test func rejectsGarbage() {
        #expect(DeepLink(url: URL(string: "ember://compose/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "ember://compose")!) == nil)
        #expect(DeepLink(url: URL(string: "ember://unknown")!) == nil)
        #expect(DeepLink(url: URL(string: "https://capture")!) == nil, "foreign schemes are ignored")
    }
}

@Suite("Image store")
struct ImageStoreTests {
    @Test func saveResolveDeleteRoundTrip() throws {
        let store = ImageStore()
        let data = Data("fake-jpeg-bytes".utf8)
        let filename = try store.save(data)

        #expect(!filename.contains("/"), "store keeps filenames, never paths")
        #expect(filename.hasSuffix(".jpg"))

        let url = store.url(for: filename)
        #expect(try Data(contentsOf: url) == data)

        store.delete(filename)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
