import Foundation

/// A published release: version, page to open and its notes.
package struct ReleaseInfo: Equatable, Sendable {
    package var version: String
    package var pageURL: URL?
    package var notes: String

    package init(version: String, pageURL: URL?, notes: String) {
        self.version = version
        self.pageURL = pageURL
        self.notes = notes
    }
}

package enum UpdateResult: Equatable, Sendable {
    case upToDate
    case available(ReleaseInfo)
    case noReleases
    case failed
}

/// Asks GitHub for the latest release and compares it with the running version. Sends nothing about the user.
package enum UpdateChecker {
    package static let repository = "LucasAlt40/CamBar"

    /// "v1.2.0" → "1.2.0"; build metadata ("+abc") and pre-release suffixes are dropped.
    package static func normalize(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespaces)
        if v.first == "v" || v.first == "V" { v.removeFirst() }
        if let cut = v.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == " " }) { v = String(v[..<cut]) }
        return v
    }

    /// Numeric comparison per component, so 1.10 is newer than 1.9 and 1.0 equals 1.0.0.
    package static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { normalize(v).split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Reads GitHub's "latest release" JSON.
    package static func parse(_ data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            let tag_name: String?
            let html_url: String?
            let body: String?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let tag = payload.tag_name, !tag.isEmpty else { return nil }
        return ReleaseInfo(version: normalize(tag), pageURL: payload.html_url.flatMap(URL.init(string:)), notes: payload.body ?? "")
    }

    package static func compare(_ latest: ReleaseInfo?, current: String) -> UpdateResult {
        guard let latest else { return .noReleases }
        return isNewer(latest.version, than: current) ? .available(latest) : .upToDate
    }

    package static func check(currentVersion: String, repository: String = repository,
                              session: URLSession = .shared) async -> UpdateResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return .failed }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("CamBar/\(normalize(currentVersion))", forHTTPHeaderField: "User-Agent")   // GitHub requires one
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        if status == 404 { return .noReleases }
        guard status == 200 else { return .failed }
        return compare(parse(data), current: currentVersion)
    }
}
