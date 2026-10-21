import Foundation

/// One ffmpeg run. stdout and stderr are read on background threads and handed to the callbacks as they arrive.
final class FFmpegProcess: @unchecked Sendable {
    struct Handlers: Sendable {
        var output: @Sendable (Data) -> Void = { _ in }
        var log: @Sendable (String) -> Void = { _ in }
        var exit: @Sendable () -> Void = {}
    }

    private let process = Process()

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
    }

    func run(_ handlers: Handlers) throws {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { handlers.output(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { handlers.log(String(decoding: data, as: UTF8.self)) }
        }
        process.terminationHandler = { _ in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            handlers.exit()
        }
        try process.run()
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
