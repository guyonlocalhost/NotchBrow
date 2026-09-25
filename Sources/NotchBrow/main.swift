import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--install-update"), CommandLine.arguments.indices.contains(index + 1) {
    exit(UpdateInstaller.run(jobFile: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
