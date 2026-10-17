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

    public struct HelperStatus: Equatable, Sendable {
        public let isInstalled: Bool
        public let isRunning: Bool
        public let pid: Int?

        public init(isInstalled: Bool, isRunning: Bool, pid: Int?) {
            self.isInstalled = isInstalled
            self.isRunning = isRunning
            self.pid = pid
        }
    }

    public static func helperStatus(plistURL: URL = Self.plistURL) -> HelperStatus {
        let installed = isInstalled(at: plistURL)
        var running = false
        var foundPid: Int? = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    let regex = try? NSRegularExpression(pattern: "\"PID\"\\s*=\\s*(\\d+);")
                    if let match = regex?.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
                       let range = Range(match.range(at: 1), in: str),
                       let parsedPid = Int(str[range]) {
                        running = true
                        foundPid = parsedPid
                    }
                }
            }
        } catch { }

        if !running {
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-x", "m14ttouch"]
            let pgrepOutput = Pipe()
            pgrep.standardOutput = pgrepOutput
            pgrep.standardError = pgrepOutput
            if (try? pgrep.run()) != nil {
                pgrep.waitUntilExit()
                if pgrep.terminationStatus == 0 {
                    let pgrepData = pgrepOutput.fileHandleForReading.readDataToEndOfFile()
                    if let pgrepStr = String(data: pgrepData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let firstLine = pgrepStr.split(separator: "\n").first,
                       let parsedPid = Int(firstLine) {
                        running = true
                        foundPid = parsedPid
                    }
                }
            }
        }

        return HelperStatus(isInstalled: installed, isRunning: running, pid: foundPid)
    }

    public static func start(helperURL: URL, plistURL: URL = Self.plistURL) throws {
        if !isInstalled(at: plistURL) {
            try install(helperURL: helperURL, plistURL: plistURL)
        }
        try bootstrap(plistURL: plistURL)
    }

    public static func stop(plistURL: URL = Self.plistURL) throws {
        try bootout(plistURL: plistURL)
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
