import Foundation
import CoreGraphics
import CryptoKit
import NotchBrowCore

final class CoreTests {
    func testSignedUpdatesAndRollback() {
        do {
            let key = Curve25519.Signing.PrivateKey()
            let archive = Data("release archive fixture".utf8)
            var fields: [String: Any] = ["format": 1, "version": "0.3.0", "build": 7,
                "minimumSystemVersion": "13.0", "bundleIdentifier": "app.notchbrow.browser",
                "archiveURL": "https://github.com/owner/NotchBrow/releases/download/v0.3.0/NotchBrow-universal.zip",
                "archiveSize": archive.count, "sha256": UpdateManifest.digest(archive)]
            func verify(_ fields: [String: Any]) throws -> UpdateManifest {
                let data = try JSONSerialization.data(withJSONObject: fields)
                return try UpdateManifest.verify(data, signature: key.signature(for: data),
                    publicKey: key.publicKey.rawRepresentation.base64EncodedString(), repository: "owner/NotchBrow")
            }
            let valid = try verify(fields)
            expectEqual(valid.build, 7)
            try valid.verifyArchive(archive)
            expectTrue(valid.supports(OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)))
            expectFalse(valid.supports(OperatingSystemVersion(majorVersion: 12, minorVersion: 9, patchVersion: 0)))
            expectTrue((try? valid.verifyArchive(Data("tampered".utf8))) == nil)
            let data = try JSONSerialization.data(withJSONObject: fields)
            let signature = try key.signature(for: data)
            let otherKey = Curve25519.Signing.PrivateKey()
            expectNil(try? UpdateManifest.verify(data, signature: signature, publicKey: otherKey.publicKey.rawRepresentation.base64EncodedString(), repository: "owner/NotchBrow"))
            expectNil(try? UpdateManifest.verify(data + Data([0]), signature: signature, publicKey: key.publicKey.rawRepresentation.base64EncodedString(), repository: "owner/NotchBrow"))
            for url in ["http://github.com/owner/NotchBrow/releases/download/v0.3.0/NotchBrow-universal.zip", "https://example.com/app.zip", "https://github.com/other/NotchBrow/releases/download/v0.3.0/NotchBrow-universal.zip", "https://github.com/owner/NotchBrow/releases/download/v0.2.0/NotchBrow-universal.zip"] {
                var invalid = fields; invalid["archiveURL"] = url
                expectNil(try? verify(invalid))
            }
            for (name, value) in [("build", 0 as Any), ("format", 2), ("minimumSystemVersion", "13.bad"), ("archiveSize", 9_000_000), ("bundleIdentifier", "other.app"), ("version", "0.3.0-beta")] {
                var invalid = fields; invalid[name] = value
                expectNil(try? verify(invalid))
            }
            fields["archiveSize"] = 0; expectNil(try? verify(fields))

            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchBrow-transaction-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: directory) }
            let target = directory.appendingPathComponent("app"), stage = directory.appendingPathComponent("stage"), backup = directory.appendingPathComponent("backup")
            try Data("old".utf8).write(to: target); try Data("new".utf8).write(to: stage)
            var launched = false
            try UpdateTransaction.install(staged: stage, target: target, backup: backup) { app in
                launched = (try? Data(contentsOf: app)) == Data("new".utf8)
                return launched
            }
            expectTrue(launched); expectFalse(FileManager.default.fileExists(atPath: backup.path))
            try Data("broken".utf8).write(to: stage)
            expectTrue((try? UpdateTransaction.install(staged: stage, target: target, backup: backup, launch: { _ in false })) == nil)
            expectEqual(try Data(contentsOf: target), Data("new".utf8))
            expectEqual(try Data(contentsOf: stage), Data("broken".utf8))
            try Data("existing backup".utf8).write(to: backup)
            expectTrue((try? UpdateTransaction.install(staged: stage, target: target, backup: backup, launch: { _ in true })) == nil)
            expectEqual(try Data(contentsOf: target), Data("new".utf8))
        } catch { check(false, "Update checks failed: \(error)", line: #line) }
    }
    func testAddressesAndSearch() {
        expectNil(AddressResolver.resolve("  \n "))
        expectEqual(AddressResolver.resolve("example.com/path")?.absoluteString, "https://example.com/path")
        expectEqual(AddressResolver.resolve(" https://example.com?q=one&x=2 ")?.host, "example.com")
        expectEqual(AddressResolver.resolve("localhost:8080/test")?.absoluteString, "http://localhost:8080/test")
        expectEqual(AddressResolver.resolve("127.0.0.1:9000")?.scheme, "http")
        expectEqual(AddressResolver.resolve("[::1]:8000")?.host, "::1")
        let query = URLComponents(url: AddressResolver.resolve("space & café #1")!, resolvingAgainstBaseURL: false)
        expectEqual(query?.queryItems?.first?.value, "space & café #1")
        expectEqual(AddressResolver.resolve("javascript:alert(1)")?.host, "duckduckgo.com")
        expectEqual(AddressResolver.resolve("file:///etc/passwd")?.host, "duckduckgo.com")
        expectEqual(AddressResolver.resolve("me@example.com")?.host, "duckduckgo.com")
    }
    func testPhysicalNotchAvoidsCameraHousing() {
        let screen = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 906), safeTop: 38, hardwareNotchWidth: 184)
        expectTrue(screen.hasNotch)
        expectEqual(screen.notchFrame.maxY, 982)
        expectEqual(screen.notchSize.width, 204)
        expectEqual(screen.notchSize.height, 45)
        expectAtMost(screen.browserFrame().maxY, 982 - 38)
        expectAtLeast(screen.browserFrame().minY, screen.visibleFrame.minY + 16)
    }
    func testArtificialNotchOnIntelLaptop() {
        let screen = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 50, width: 1440, height: 825))
        expectFalse(screen.hasNotch)
        expectEqual(screen.notchFrame.width, 186)
        expectEqual(screen.notchFrame.height, 30)
        expectEqual(screen.notchFrame.midX, 720)
        expectEqual(screen.notchFrame.maxY, 900)
        expectEqual(screen.browserFrame().midX, screen.notchFrame.midX)
    }
    func testSmallAndOffsetDisplaysWithDocks() {
        for frame in [CGRect(x: -1920, y: 80, width: 1920, height: 1080), CGRect(x: 0, y: -768, width: 1024, height: 768), CGRect(x: 1440, y: 0, width: 800, height: 600)] {
            let visible = frame.insetBy(dx: 60, dy: 30)
            let screen = DisplayGeometry(frame: frame, visibleFrame: visible)
            for large in [false, true] {
                let panel = screen.browserFrame(large: large)
                expectAtLeast(panel.minX, visible.minX)
                expectAtMost(panel.maxX, visible.maxX)
                expectAtLeast(panel.minY, visible.minY)
                expectAtMost(panel.maxY, screen.notchFrame.minY + 1)
            }
            expectEqual(screen.notchFrame.midX, frame.midX)
            expectEqual(screen.notchFrame.maxY, frame.maxY)
        }
    }
    func testBookmarksToggleAndSurviveRecreation() {
        let name = "NotchBrow.UnitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = BrowserStore(defaults: defaults)
        expectFalse(store.hoverToOpen)
        let page = SavedPage(title: "Example", url: "https://example.com")
        store.toggleBookmark(page)
        expectEqual(BrowserStore(defaults: defaults).bookmarks, [page])
        store.toggleBookmark(page)
        expectTrue(store.bookmarks.isEmpty)
        defaults.set(Data("corrupt".utf8), forKey: "bookmarks")
        expectTrue(store.bookmarks.isEmpty)
        store.pinned = true; store.largePanel = true
        expectTrue(BrowserStore(defaults: defaults).pinned)
        expectTrue(BrowserStore(defaults: defaults).largePanel)
    }
}

private var failures = 0
private var checks = 0
func check(_ condition: Bool, _ message: String, line: UInt) {
    checks += 1
    if !condition { failures += 1; print("FAIL line \(line): \(message)") }
}
func expectNil<T>(_ value: T?, line: UInt = #line) { check(value == nil, "Expected nil", line: line) }
func expectEqual<T: Equatable>(_ a: T, _ b: T, line: UInt = #line) { check(a == b, "\(a) != \(b)", line: line) }
func expectTrue(_ value: Bool, line: UInt = #line) { check(value, "Expected true", line: line) }
func expectFalse(_ value: Bool, line: UInt = #line) { check(!value, "Expected false", line: line) }
func expectAtMost<T: Comparable>(_ a: T, _ b: T, line: UInt = #line) { check(a <= b, "\(a) > \(b)", line: line) }
func expectAtLeast<T: Comparable>(_ a: T, _ b: T, line: UInt = #line) { check(a >= b, "\(a) < \(b)", line: line) }

@main enum TestRunner {
    static func main() {
        let suite = CoreTests()
        suite.testAddressesAndSearch()
        suite.testPhysicalNotchAvoidsCameraHousing()
        suite.testArtificialNotchOnIntelLaptop()
        suite.testSmallAndOffsetDisplaysWithDocks()
        suite.testBookmarksToggleAndSurviveRecreation()
        suite.testSignedUpdatesAndRollback()
        print("Core checks: \(checks - failures)/\(checks) passed")
        if failures > 0 { exit(1) }
    }
}
