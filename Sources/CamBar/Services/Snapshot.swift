import AppKit

/// Saves stills to `~/Pictures/CamBar`.
enum Snapshot {
    enum Failure: Error { case encoding }

    static var directory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("CamBar")
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// Writes a JPEG and returns its location.
    @discardableResult
    static func save(_ image: NSImage, cameraName: String, date: Date = Date()) throws -> URL {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let jpeg = NSBitmapImageRep(cgImage: cgImage)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { throw Failure.encoding }
        // "/" and ":" in a camera name (e.g. "Portão/Garagem") would otherwise break the path
        let safeName = cameraName.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "-")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeName) \(timestamp.string(from: date)).jpg")
        try jpeg.write(to: url)
        return url
    }
}
