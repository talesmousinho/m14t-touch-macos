import Foundation

public enum LaunchAgentManager {
    public static let label = "com.talesfonseca.m14ttouch"

    public static var plistURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func isInstalled(at plistURL: URL = Self.plistURL) -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func install(helperURL: URL, plistURL: URL = Self.plistURL) throws {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                helperURL.path,
                "--no-accessibility-prompt"
            ],
            "RunAtLoad": true,
            "KeepAlive": [
                "SuccessfulExit": false
            ],
            "StandardInPath": "/dev/null",
            "StandardErrorPath": FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/M14tTouch/helper.err.log")
                .path,
            "StandardOutPath": "/dev/null"
        ]

        let logDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/M14tTouch", isDirectory: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    public static func remove(plistURL: URL = Self.plistURL) throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    public static func bootstrap(plistURL: URL = Self.plistURL) throws {
        _ = try runLaunchctl(["bootout", guiDomain, plistURL.path], allowFailure: true)
        try runLaunchctl(["bootstrap", guiDomain, plistURL.path])
        _ = try runLaunchctl(["kickstart", "-k", "\(guiDomain)/\(label)"], allowFailure: true)
    }

    public static func bootout(plistURL: URL = Self.plistURL) throws {
        _ = try runLaunchctl(["bootout", guiDomain, plistURL.path], allowFailure: true)
    }

    public static func restart(plistURL: URL = Self.plistURL) throws {
        if isInstalled(at: plistURL) {
            try bootstrap(plistURL: plistURL)
        }
    }

    private static var guiDomain: String {
        "gui/\(getuid())"
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !allowFailure {
            throw LaunchAgentError.launchctlFailed(arguments: arguments, status: process.terminationStatus, output: message)
        }

        return message
    }
}

public enum LaunchAgentError: LocalizedError {
    case launchctlFailed(arguments: [String], status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .launchctlFailed(let arguments, let status, let output):
            let command = (["launchctl"] + arguments).joined(separator: " ")
            return "\(command) failed with status \(status): \(output)"
        }
    }
}
