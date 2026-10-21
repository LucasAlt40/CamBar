import Foundation

/// Append-only log in `~/Library/Logs`. Masks RTSP credentials, tags lines and stays under a size cap,
/// so several cameras can share one file without wiping each other's history.
package final class FileLog: @unchecked Sendable {
    package let url: URL
    private let maxBytes: Int
    private let queue: DispatchQueue

    package init(name: String, maxBytes: Int = 1_000_000, directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        url = dir.appendingPathComponent("\(name).log")
        self.maxBytes = maxBytes
        queue = DispatchQueue(label: "cambar.log.\(name)")
    }

    package func append(_ text: String, tag: String? = nil) {
        queue.async { [self] in
            let prefix = tag.map { "[\($0)] " } ?? ""
            let lines = Self.mask(text)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { prefix + $0 }
            guard !lines.isEmpty else { return }
            write(Data((lines.joined(separator: "\n") + "\n").utf8))
        }
    }

    package func clear() {
        queue.async { [self] in try? Data().write(to: url) }
    }

    /// Replaces `user:password@` in any URL with `***@`.
    package static func mask(_ text: String) -> String {
        text.replacingOccurrences(of: #"://[^/@\s]*@"#, with: "://***@", options: .regularExpression)
    }

    private func write(_ data: Data) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
            return
        }
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if Int(size) + data.count > maxBytes {
            // keep the newest half so the file never grows without bound
            try? handle.seek(toOffset: size / 2)
            let tail = (try? handle.readToEnd()) ?? Data()
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: tail)
        }
        try? handle.write(contentsOf: data)
    }
}
