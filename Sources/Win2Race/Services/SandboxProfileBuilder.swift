import Foundation

enum SandboxProfileBuilder {
    static var sandboxExecPath: String? {
        let path = "/usr/bin/sandbox-exec"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static func writeProfile(workspaceURL: URL, runDirectoryURL: URL) throws -> URL {
        let profileURL = runDirectoryURL.appendingPathComponent("sandbox.sb")
        let workspace = escape(workspaceURL.path)
        let runDirectory = escape(runDirectoryURL.path)
        let temporary = escape(NSTemporaryDirectory())

        let content = """
        (version 1)
        (allow default)
        (deny file-write*)
        (allow file-write*
          (subpath "\(workspace)")
          (subpath "\(runDirectory)")
          (subpath "\(temporary)")
          (subpath "/private/tmp")
          (subpath "/tmp"))
        (allow network-outbound)
        """

        try content.write(to: profileURL, atomically: true, encoding: .utf8)
        return profileURL
    }

    static func wrapIfAvailable(executable: String, arguments: [String], profileURL: URL?) -> (String, [String], String) {
        guard let sandboxExecPath, let profileURL else {
            return (executable, arguments, "macOS sandbox-exec unavailable; running without OS sandbox.")
        }
        return (sandboxExecPath, ["-f", profileURL.path, executable] + arguments, "macOS sandbox-exec profile active.")
    }

    private static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
