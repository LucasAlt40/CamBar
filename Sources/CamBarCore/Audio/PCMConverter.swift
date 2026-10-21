import Foundation

/// Turns chunks of little-endian 16-bit mono PCM into Float samples in -1...1.
/// Chunks can split a sample in half; the odd byte is carried over to the next call.
package struct PCMConverter {
    private var carry: UInt8?

    package init() {}

    package mutating func convert(_ chunk: Data) -> [Float] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(chunk.count + 1)
        if let carry { bytes.append(carry) }
        bytes.append(contentsOf: chunk)

        let usable = bytes.count & ~1
        carry = usable < bytes.count ? bytes[usable] : nil

        var samples = [Float](repeating: 0, count: usable / 2)
        for i in samples.indices {
            let value = Int16(bitPattern: UInt16(bytes[2 * i]) | UInt16(bytes[2 * i + 1]) << 8)
            samples[i] = Float(value) / 32768
        }
        return samples
    }
}
