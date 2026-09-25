import Foundation
import CryptoKit

func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
let args = CommandLine.arguments
guard args.count >= 3 else { fail("Usage: release-tool keygen KEY | sign KEY APP ZIP OUTPUT REPOSITORY PUBLIC_KEY") }
let keyURL = URL(fileURLWithPath: args[2])
if args[1] == "keygen" {
    if !FileManager.default.fileExists(atPath: keyURL.path) {
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = Curve25519.Signing.PrivateKey()
        try key.rawRepresentation.write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if args[1] == "sign", args.count == 8 {
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
    guard key.publicKey.rawRepresentation.base64EncodedString() == args[7] else { fail("Signing key does not match the app's pinned update key.") }
    let app = URL(fileURLWithPath: args[3]); let zip = URL(fileURLWithPath: args[4])
    let output = URL(fileURLWithPath: args[5])
    let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
    guard info["UpdateRepository"] as? String == args[6], info["UpdatePublicKey"] as? String == args[7] else { fail("App update configuration does not match this release.") }
    let version = info["CFBundleShortVersionString"] as! String
    let archive = try Data(contentsOf: zip)
    let manifest: [String: Any] = ["format": 1, "version": version, "build": Int(info["CFBundleVersion"] as! String)!,
        "minimumSystemVersion": info["LSMinimumSystemVersion"] as! String,
        "bundleIdentifier": info["CFBundleIdentifier"] as! String,
        "archiveURL": "https://github.com/\(args[6])/releases/download/v\(version)/NotchBrow-universal.zip",
        "archiveSize": archive.count, "sha256": SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()]
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: output.appendingPathComponent("NotchBrow-update.json"))
    try key.signature(for: data).write(to: output.appendingPathComponent("NotchBrow-update.sig"))
    print("Signed NotchBrow \(version) for \(args[6])")
} else { fail("Unknown release command") }
