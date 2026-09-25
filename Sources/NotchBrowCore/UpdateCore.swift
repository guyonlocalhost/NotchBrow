import Foundation
import CryptoKit

public struct UpdateFailure: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct UpdateManifest: Codable {
    public let format: Int
    public let version: String
    public let build: Int
    public let minimumSystemVersion: String
    public let bundleIdentifier: String
    public let archiveURL: URL
    public let archiveSize: Int
    public let sha256: String

    public static let maximumArchiveSize = 8_000_000

    public static func verify(_ data: Data, signature: Data, publicKey: String, repository: String) throws -> Self {
        guard data.count <= 32_768, let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signature, for: data) else {
            throw UpdateFailure("The update signature is invalid. Your current app has not been changed.")
        }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        let components = URLComponents(url: manifest.archiveURL, resolvingAgainstBaseURL: false)
        let path = manifest.archiveURL.path
        let prefix = "/\(repository)/releases/download/"
        let versionParts = manifest.version.split(separator: ".", omittingEmptySubsequences: false)
        guard manifest.format == 1, manifest.build > 0,
              versionParts.count == 3, versionParts.allSatisfy({ Int($0).map { $0 >= 0 } == true }),
              manifest.bundleIdentifier == "app.notchbrow.browser",
              manifest.archiveSize > 0, manifest.archiveSize <= maximumArchiveSize,
              manifest.sha256.count == 64, manifest.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              components?.scheme == "https", components?.host == "github.com",
              components?.user == nil, components?.password == nil, components?.port == nil,
              components?.query == nil, components?.fragment == nil,
              path == "\(prefix)v\(manifest.version)/NotchBrow-universal.zip",
              systemVersion(manifest.minimumSystemVersion) != nil else {
            throw UpdateFailure("The release contains invalid update information.")
        }
        return manifest
    }

    public func verifyArchive(_ data: Data) throws {
        guard data.count == archiveSize, Self.digest(data) == sha256 else {
            throw UpdateFailure("The update download is incomplete or damaged. Please try again.")
        }
    }

    public func supports(_ os: OperatingSystemVersion) -> Bool {
        guard let required = Self.systemVersion(minimumSystemVersion) else { return false }
        return [os.majorVersion, os.minorVersion, os.patchVersion].lexicographicallyPrecedes(required) == false
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func systemVersion(_ string: String) -> [Int]? {
        let pieces = string.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0) }
        guard (2...3).contains(pieces.count), numbers.count == pieces.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}

/// Same-volume renames keep a recoverable copy until the replacement actually launches.
public enum UpdateTransaction {
    public static func install(staged: URL, target: URL, backup: URL, launch: (URL) -> Bool) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: backup.path), files.fileExists(atPath: staged.path),
              staged.deletingLastPathComponent() == target.deletingLastPathComponent(),
              backup.deletingLastPathComponent() == target.deletingLastPathComponent() else {
            throw UpdateFailure("The update could not be prepared safely.")
        }
        try files.moveItem(at: target, to: backup)
        do {
            try files.moveItem(at: staged, to: target)
            guard launch(target) else { throw UpdateFailure("The updated app could not start. The previous version was restored.") }
        } catch {
            // Preserve the old bundle even if rollback itself fails (for example, disk failure).
            if files.fileExists(atPath: target.path) { try files.moveItem(at: target, to: staged) }
            try files.moveItem(at: backup, to: target)
            throw error
        }
        try? files.removeItem(at: backup)
    }
}
