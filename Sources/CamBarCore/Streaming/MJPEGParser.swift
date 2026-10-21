import Foundation

/// Splits a concatenated MJPEG byte stream (as ffmpeg writes it) into individual JPEG images.
/// JPEG data escapes 0xFF inside entropy-coded segments, so start/end markers are unambiguous.
package struct MJPEGParser {
    private static let startMarker = Data([0xFF, 0xD8])
    private static let endMarker = Data([0xFF, 0xD9])

    private var buffer = Data()
    private let maxBufferSize: Int

    package init(maxBufferSize: Int = 8_000_000) {
        self.maxBufferSize = maxBufferSize
    }

    /// Feeds bytes and returns every complete frame found, oldest first.
    package mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while let start = buffer.firstRange(of: Self.startMarker),
              let end = buffer.firstRange(of: Self.endMarker, in: start.upperBound..<buffer.endIndex) {
            frames.append(buffer.subdata(in: start.lowerBound..<end.upperBound))
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
        }
        // a corrupt stream without end markers must not grow memory forever
        if buffer.count > maxBufferSize { buffer.removeAll(keepingCapacity: true) }
        return frames
    }
}
