import Foundation
import CoreGraphics

public enum AddressResolver {
    /// Only HTTP(S) may be typed into the omnibox. Other schemes are never executed.
    public static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let components = URLComponents(string: text),
           let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
           let host = components.host, !host.isEmpty {
            return components.url
        }
        let first = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let local = first == "localhost" || first.hasPrefix("localhost:") || first.hasPrefix("127.0.0.1") || first.hasPrefix("[::1]")
        if !text.contains(where: { $0.isWhitespace }), !text.contains("://"),
           (first.contains(".") || local), !first.contains("@"),
           let url = URL(string: (local ? "http://" : "https://") + text), url.host != nil {
            return url
        }
        var search = URLComponents(string: "https://duckduckgo.com/")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }
}

public struct DisplayGeometry {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeTop: CGFloat
    public let hardwareNotchWidth: CGFloat
    public var hasNotch: Bool { safeTop > 0 && hardwareNotchWidth > 0 }
    public init(frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat = 0, hardwareNotchWidth: CGFloat = 0) {
        self.frame = frame; self.visibleFrame = visibleFrame
        self.safeTop = safeTop; self.hardwareNotchWidth = hardwareNotchWidth
    }
    public var notchSize: CGSize {
        hasNotch ? CGSize(width: hardwareNotchWidth + 20, height: safeTop + 7) : CGSize(width: 186, height: 30)
    }
    public var notchFrame: CGRect {
        CGRect(x: frame.midX - notchSize.width / 2, y: frame.maxY - notchSize.height,
               width: notchSize.width, height: notchSize.height)
    }
    public func browserFrame(large: Bool = false) -> CGRect {
        let top = frame.maxY - notchSize.height + 1
        let width = min(large ? 1100 : 860, max(300, visibleFrame.width - 32))
        let height = min(large ? 800 : 620, max(220, top - visibleFrame.minY - 16))
        let x = min(max(frame.midX - width / 2, visibleFrame.minX + 16), visibleFrame.maxX - width - 16)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }
}

public struct SavedPage: Codable, Equatable {
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

public final class BrowserStore {
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var bookmarks: [SavedPage] {
        get { (defaults.data(forKey: "bookmarks").flatMap { try? JSONDecoder().decode([SavedPage].self, from: $0) }) ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "bookmarks") }
    }
    public var hoverToOpen: Bool {
        get { defaults.object(forKey: "hoverToOpen") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "hoverToOpen") }
    }
    public var largePanel: Bool {
        get { defaults.bool(forKey: "largePanel") }
        set { defaults.set(newValue, forKey: "largePanel") }
    }
    public var pinned: Bool {
        get { defaults.bool(forKey: "pinned") }
        set { defaults.set(newValue, forKey: "pinned") }
    }
    public func toggleBookmark(_ page: SavedPage) {
        var pages = bookmarks
        if let index = pages.firstIndex(where: { $0.url == page.url }) { pages.remove(at: index) }
        else { pages.append(page) }
        bookmarks = pages
    }
}
