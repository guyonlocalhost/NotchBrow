import AppKit
import NotchBrowCore

private final class UpdateRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"]
        completionHandler(request.url?.scheme == "https" && allowed.contains(request.url?.host ?? "") ? request : nil)
    }
}

@MainActor final class AppUpdater {
    private weak var app: AppDelegate?
    private var task: Task<Void, Never>?
    private var alert: NSAlert?
    private var window: NSWindow?
    private var preparingRestart = false
    private let detail = NSTextField(wrappingLabelWithString: "Checking GitHub for the latest release…")
    private let spinner = NSProgressIndicator()
    private(set) var isUpdating = false
    var onRestart: (() -> Void)?

    init(app: AppDelegate) { self.app = app }

    func start() {
        guard !isUpdating, let app else { return }
        app.show()
        let alert = NSAlert()
        alert.messageText = "Update NotchBrow"
        alert.informativeText = "A newer version will install and restart automatically. Open tabs will reload."
        alert.addButton(withTitle: "Cancel")
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 52))
        spinner.style = .spinning; spinner.controlSize = .small
        spinner.frame = NSRect(x: 0, y: 23, width: 16, height: 16); spinner.startAnimation(nil)
        detail.frame = NSRect(x: 26, y: 0, width: 304, height: 44)
        detail.stringValue = "Checking GitHub for the latest release…"
        accessory.addSubview(spinner); accessory.addSubview(detail); alert.accessoryView = accessory
        self.alert = alert; window = app.currentWindow; isUpdating = true
        app.browser.modalDepth += 1
        alert.beginSheetModal(for: app.currentWindow) { [weak self] _ in
            guard let self else { return }
            if !self.preparingRestart { self.task?.cancel() }
        }
        task = Task { [weak self] in await self?.update() }
    }

    private func update() async {
        var work: URL?
        var staged: URL?
        var handedOff = false
        defer {
            if !handedOff {
                if let staged { try? FileManager.default.removeItem(at: staged) }
                if let work { try? FileManager.default.removeItem(at: work) }
            }
        }
        do {
            let info = Bundle.main.infoDictionary ?? [:]
            guard let repo = info["UpdateRepository"] as? String, repo.split(separator: "/").count == 2,
                  let key = info["UpdatePublicKey"] as? String, !key.isEmpty,
                  let currentBuild = Int(info["CFBundleVersion"] as? String ?? "") else {
                throw UpdateFailure("This build has no update source. Install a packaged NotchBrow release first.")
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 120
            let session = URLSession(configuration: configuration, delegate: UpdateRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let base = URL(string: "https://github.com/\(repo)/releases/latest/download/")!
            let data = try await download(base.appendingPathComponent("NotchBrow-update.json"), limit: 32_768, session: session)
            let signature = try await download(base.appendingPathComponent("NotchBrow-update.sig"), limit: 64, session: session)
            let release = try UpdateManifest.verify(data, signature: signature, publicKey: key, repository: repo)
            guard release.build > currentBuild else {
                finish("You’re up to date", "NotchBrow \(info["CFBundleShortVersionString"] as? String ?? "") is the latest version available for this app.")
                return
            }
            guard release.supports(ProcessInfo.processInfo.operatingSystemVersion) else {
                throw UpdateFailure("NotchBrow \(release.version) requires macOS \(release.minimumSystemVersion) or later. Your current version will keep working.")
            }
            let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
            guard target.pathExtension == "app", !target.path.hasPrefix("/Volumes/"),
                  FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateFailure("Move NotchBrow to a writable Applications folder before updating.")
            }
            detail.stringValue = "Downloading NotchBrow \(release.version)…"
            let archive = try await download(release.archiveURL, limit: release.archiveSize, session: session)
            try Task.checkCancellation()
            try release.verifyArchive(archive)
            detail.stringValue = "Verifying and preparing the update…"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchBrow-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            work = directory
            let archiveFile = directory.appendingPathComponent("update.zip")
            try archive.write(to: archiveFile)
            let unpacked = directory.appendingPathComponent("unpacked")
            let candidate = unpacked.appendingPathComponent("NotchBrow.app")
            let stage = target.deletingLastPathComponent().appendingPathComponent(".NotchBrow-update-\(UUID().uuidString).app")
            staged = stage
            // Extraction and signature checking never block AppKit's animation/event thread.
            try await Task.detached {
                try UpdateInstaller.command("/usr/bin/ditto", ["-x", "-k", archiveFile.path, unpacked.path])
                try UpdateInstaller.validate(candidate, build: release.build, version: release.version)
                try FileManager.default.copyItem(at: candidate, to: stage)
                try UpdateInstaller.validate(stage, build: release.build, version: release.version)
            }.value
            try Task.checkCancellation()
            let helper = directory.appendingPathComponent("installer")
            try FileManager.default.copyItem(at: Bundle.main.executableURL!, to: helper)
            let job = UpdateInstaller.Job(target: target, staged: stage,
                backup: target.deletingLastPathComponent().appendingPathComponent(".NotchBrow-backup-\(UUID().uuidString).app"),
                parentPID: ProcessInfo.processInfo.processIdentifier, previousBuild: currentBuild,
                build: release.build, version: release.version)
            let jobFile = directory.appendingPathComponent("install.json")
            try JSONEncoder().encode(job).write(to: jobFile, options: .atomic)
            let process = Process(); process.executableURL = helper; process.arguments = ["--install-update", jobFile.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            // The helper first confirms it can read and validate its job before the app exits.
            let ready = directory.appendingPathComponent("ready")
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: ready.path) { break }
                guard process.isRunning else { throw UpdateFailure("The installer could not start. Your current app has not been changed.") }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard FileManager.default.fileExists(atPath: ready.path) else {
                process.terminate(); throw UpdateFailure("The installer did not respond. Please try again.")
            }
            preparingRestart = true; handedOff = true
            alert?.buttons.first?.isEnabled = false; detail.stringValue = "Restarting NotchBrow…"
            onRestart?()
            NSApp.terminate(nil)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { finish(nil, nil) }
            else { finish("Couldn’t update NotchBrow", error.localizedDescription) }
        }
    }

    private func download(_ url: URL, limit: Int, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("NotchBrow-Updater", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw UpdateFailure("No published update is available on GitHub yet. Please try again later.") }
            throw UpdateFailure("GitHub could not provide the update (HTTP \(status)). Please try again later.")
        }
        guard response.expectedContentLength <= Int64(limit) else { throw UpdateFailure("The update download is larger than expected.") }
        var result = Data(); result.reserveCapacity(min(limit, 2_000_000))
        for try await byte in bytes {
            guard result.count < limit else { throw UpdateFailure("The update download is larger than expected.") }
            result.append(byte)
        }
        try Task.checkCancellation()
        return result
    }

    private func finish(_ title: String?, _ message: String?) {
        task = nil; isUpdating = false; spinner.stopAnimation(nil)
        if let alert, let window { window.endSheet(alert.window) }
        alert = nil; app?.browser.modalDepth -= 1
        guard let title, let app else { return }
        let result = NSAlert(); result.messageText = title; result.informativeText = message ?? ""
        app.browser.modalDepth += 1
        result.beginSheetModal(for: app.currentWindow) { [weak app] _ in app?.browser.modalDepth -= 1 }
    }
}

enum UpdateInstaller {
    struct Job: Codable {
        let target: URL
        let staged: URL
        let backup: URL
        let parentPID: Int32
        let previousBuild: Int
        let build: Int
        let version: String
    }

    static func command(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure("The update could not be unpacked or verified. Your current app has not been changed.") }
    }

    static func validate(_ app: URL, build: Int, version: String? = nil) throws {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == "app.notchbrow.browser",
              info?["CFBundleExecutable"] as? String == "NotchBrow",
              info?["CFBundleVersion"] as? String == String(build),
              version == nil || info?["CFBundleShortVersionString"] as? String == version else {
            throw UpdateFailure("The downloaded app does not match this release.")
        }
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey])!
        var size = 0
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw UpdateFailure("The update contains an unexpected linked file.") }
            size += values.fileSize ?? 0
        }
        guard size < 3_000_000 else { throw UpdateFailure("The downloaded app is larger than expected.") }
        try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    static func run(jobFile: URL) -> Int32 {
        let files = FileManager.default
        let work = jobFile.deletingLastPathComponent()
        do {
            let job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: jobFile))
            guard job.build > job.previousBuild, job.target.pathExtension == "app",
                  job.staged.lastPathComponent.hasPrefix(".NotchBrow-update-"),
                  job.backup.lastPathComponent.hasPrefix(".NotchBrow-backup-"), job.parentPID > 1 else {
                throw UpdateFailure("Invalid installation job.")
            }
            try validate(job.target, build: job.previousBuild)
            try validate(job.staged, build: job.build, version: job.version)
            try Data().write(to: work.appendingPathComponent("ready"))
            for _ in 0..<600 {
                if kill(job.parentPID, 0) != 0 { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard kill(job.parentPID, 0) != 0 else { throw UpdateFailure("NotchBrow did not quit. No update was installed.") }
            try validate(job.target, build: job.previousBuild)
            let receipt = work.appendingPathComponent("launched")
            do {
                try UpdateTransaction.install(staged: job.staged, target: job.target, backup: job.backup) { target in
                    do {
                        try command("/usr/bin/open", ["-n", target.path, "--args", "--update-receipt", receipt.path])
                        for _ in 0..<300 {
                            if files.fileExists(atPath: receipt.path) { return true }
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                        // Close only this replacement before restoring the old bundle.
                        for running in NSRunningApplication.runningApplications(withBundleIdentifier: "app.notchbrow.browser")
                        where running.bundleURL?.resolvingSymlinksInPath() == target {
                            running.forceTerminate()
                        }
                        Thread.sleep(forTimeInterval: 0.3)
                    } catch { }
                    return false
                }
            } catch {
                try? command("/usr/bin/open", ["-n", job.target.path])
                throw error
            }
            try? files.removeItem(at: work)
            return 0
        } catch {
            // Leave diagnostic information and any backup in place on failure.
            try? Data(error.localizedDescription.utf8).write(to: work.appendingPathComponent("failure.txt"))
            return 1
        }
    }
}
