import Foundation

/// Splits a concatenated MJPEG byte stream (as ffmpeg writes it) into individual JPEG images.
/// JPEG data escapes 0xFF inside entropy-coded segments, so start/end markers are unambiguous.
package struct MJPEGParser {
    private static let startMarker = Data([0xFF, 0xD8])
    private static let endMarker = Data([0xFF, 0xD9])

    private var buffer = Data()
    /// Bytes after the start marker already searched for the end marker, so big frames arriving in
    /// many chunks are scanned once instead of from the start on every chunk.
    private var scanned = 0
    private let maxBufferSize: Int

    package init(maxBufferSize: Int = 8_000_000) {
        self.maxBufferSize = maxBufferSize
    }

    /// Feeds bytes and returns every complete frame found, oldest first.
    package mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while let start = buffer.firstRange(of: Self.startMarker) {
            // step back one byte: the marker may straddle the previous chunk
            let from = max(start.upperBound, buffer.startIndex + scanned - 1)
            guard let end = buffer.firstRange(of: Self.endMarker, in: from..<buffer.endIndex) else {
                scanned = buffer.count
                break
            }
            frames.append(buffer.subdata(in: start.lowerBound..<end.upperBound))
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            scanned = 0
        }
        // a corrupt stream without end markers must not grow memory forever
        if buffer.count > maxBufferSize {
            buffer.removeAll(keepingCapacity: true)
            scanned = 0
        }
        return frames
    }
}
