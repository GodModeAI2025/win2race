import Foundation

struct ProcessResult: Hashable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var duration: TimeInterval

    var succeeded: Bool { exitCode == 0 }
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async -> ProcessResult {
        await Task.detached(priority: .userInitiated) {
            let started = Date()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdoutCollector = PipeDataCollector()
            let stderrCollector = PipeDataCollector()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stdoutCollector.append(data)
                }
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrCollector.append(data)
                }
            }

            do {
                let termination = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    termination.signal()
                }
                try process.run()

                let timedOut = waitForProcess(process, termination: termination, timeout: timeout)

                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutCollector.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrCollector.append(stderr.fileHandleForReading.readDataToEndOfFile())

                if timedOut {
                    return ProcessResult(
                        exitCode: -2,
                        stdout: stdoutCollector.string(),
                        stderr: "Process timed out after \(Int(timeout ?? 0)) seconds.",
                        duration: Date().timeIntervalSince(started)
                    )
                }

                return ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: stdoutCollector.string(),
                    stderr: stderrCollector.string(),
                    duration: Date().timeIntervalSince(started)
                )
            } catch {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                return ProcessResult(
                    exitCode: -1,
                    stdout: "",
                    stderr: error.localizedDescription,
                    duration: Date().timeIntervalSince(started)
                )
            }
        }.value
    }

    private static func waitForProcess(
        _ process: Process,
        termination: DispatchSemaphore,
        timeout: TimeInterval?
    ) -> Bool {
        guard let timeout else {
            process.waitUntilExit()
            return false
        }

        let timedOut = termination.wait(timeout: .now() + timeout) == .timedOut
        if timedOut, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        return timedOut
    }
}

private final class PipeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }
}

@MainActor
final class RunningAgentHandle {
    let runID: UUID
    private let process: Process
    private let inputPipe: Pipe
    private let outputPipe: Pipe
    private let errorPipe: Pipe

    init(runID: UUID, process: Process, inputPipe: Pipe, outputPipe: Pipe, errorPipe: Pipe) {
        self.runID = runID
        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
    }

    func send(_ text: String) {
        guard let data = "\(text)\n".data(using: .utf8) else {
            return
        }
        inputPipe.fileHandleForWriting.write(data)
    }

    func terminate() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }
}

enum AgentRuntime {
    @MainActor
    static func start(
        runID: UUID,
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String],
        onStarted: @escaping @MainActor (RunningAgentHandle) -> Void,
        onOutput: @escaping @MainActor (String, Bool) -> Void,
        onExit: @escaping @MainActor (Int32) -> Void
    ) throws -> RunningAgentHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            Task { @MainActor in
                onOutput(text, false)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            Task { @MainActor in
                onOutput(text, true)
            }
        }

        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            let finalOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let finalError = errorPipe.fileHandleForReading.readDataToEndOfFile()
            Task { @MainActor in
                if !finalOutput.isEmpty, let text = String(data: finalOutput, encoding: .utf8) {
                    onOutput(text, false)
                }
                if !finalError.isEmpty, let text = String(data: finalError, encoding: .utf8) {
                    onOutput(text, true)
                }
                onExit(process.terminationStatus)
            }
        }

        let handle = RunningAgentHandle(
            runID: runID,
            process: process,
            inputPipe: inputPipe,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )
        onStarted(handle)
        try process.run()

        return handle
    }
}
