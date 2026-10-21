import Foundation
import CryptoKit

/// Pan/tilt/zoom over ONVIF (SOAP + WS-Security digest). Controls only appear when the camera answers as motorized.
final class PTZController: ObservableObject {
    enum State { case idle, detecting, available, unavailable }

    @Published private(set) var state: State = .idle

    private var ptzURL: URL?
    private var token = ""
    private var username = ""
    private var password = ""
    @Published private(set) var activeKey: String?

    static let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/CamBar-ptz.log")

    /// Appends what the camera answered (never the request, so no credentials end up in the file).
    private static func log(_ line: String) {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
    }

    func detect(camera: Camera, password: String) {
        guard state == .idle else { return }
        try? Data().write(to: Self.logURL)
        state = .detecting
        username = camera.username
        self.password = password
        let ports = camera.onvifPort.map { [$0] } ?? [5000, 80, 8080]
        Task {
            for port in ports {
                if let found = await probe(host: camera.host, port: port) {
                    await MainActor.run { self.ptzURL = found.url; self.token = found.token; self.state = .available }
                    return
                }
            }
            await MainActor.run { self.state = .unavailable }
        }
    }

    /// Starts a continuous move that lasts until `stop()`.
    func begin(key: String, pan: Double, tilt: Double, zoom: Double) {
        guard state == .available, activeKey != key, let url = ptzURL else { return }
        activeKey = key
        let body = """
        <tptz:ContinuousMove><tptz:ProfileToken>\(token)</tptz:ProfileToken><tptz:Velocity>\
        <tt:PanTilt x="\(pan)" y="\(tilt)"/><tt:Zoom x="\(zoom)"/></tptz:Velocity></tptz:ContinuousMove>
        """
        Task { _ = await soap(url, body) }
    }

    /// Joystick input in -1...1 on each axis (y up); only re-sends when the quantized direction changes.
    func drive(dx: Double, dy: Double) {
        func q(_ v: Double) -> Double { abs(v) < 0.25 ? 0 : (v * 4).rounded() / 4 }
        let pan = q(dx), tilt = q(dy)
        if pan == 0 && tilt == 0 { stop(); return }
        begin(key: "joy \(pan) \(tilt)", pan: pan, tilt: tilt, zoom: 0)
    }

    func stop() {
        guard activeKey != nil, let url = ptzURL else { return }
        activeKey = nil
        let body = "<tptz:Stop><tptz:ProfileToken>\(token)</tptz:ProfileToken><tptz:PanTilt>true</tptz:PanTilt><tptz:Zoom>true</tptz:Zoom></tptz:Stop>"
        Task { _ = await soap(url, body) }
    }

    func goHome() {
        guard state == .available, let url = ptzURL else { return }
        let body = "<tptz:GotoHomePosition><tptz:ProfileToken>\(token)</tptz:ProfileToken></tptz:GotoHomePosition>"
        Task { _ = await soap(url, body) }
    }

    // MARK: ONVIF plumbing

    private func probe(host: String, port: Int) async -> (url: URL, token: String)? {
        guard let device = URL(string: "http://\(host):\(port)/onvif/device_service"),
              let caps = await soap(device, "<tds:GetCapabilities><tds:Category>All</tds:Category></tds:GetCapabilities>"),
              let ptzAddr = xaddr("PTZ", in: caps), let ptz = rewrite(ptzAddr, host: host) else { return nil }
        let media = xaddr("Media", in: caps).flatMap { rewrite($0, host: host) } ?? device
        guard let profiles = await soap(media, "<trt:GetProfiles/>"), let token = ptzProfileToken(in: profiles) else { return nil }
        return (ptz, token)
    }

    private func xaddr(_ service: String, in xml: String) -> String? {
        let pattern = "<[\\w]*:?\(service)>\\s*<[\\w]*:?XAddr>([^<]+)</"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let r = Range(m.range(at: 1), in: xml) else { return nil }
        return String(xml[r])
    }

    /// Cameras often report their internal address; keep the path but talk to the host we were given.
    private func rewrite(_ address: String, host: String) -> URL? {
        guard var c = URLComponents(string: address) else { return nil }
        c.host = host
        return c.url
    }

    private func ptzProfileToken(in xml: String) -> String? {
        let pattern = "<[\\w]*:?Profiles[^>]*token=\"([^\"]+)\"[^>]*>(.*?)</[\\w]*:?Profiles>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        for m in re.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            guard let t = Range(m.range(at: 1), in: xml), let b = Range(m.range(at: 2), in: xml) else { continue }
            if xml[b].contains("PTZConfiguration") { return String(xml[t]) }
        }
        return nil
    }

    private func soap(_ url: URL, _ body: String) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        req.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(envelope(body).utf8)
        let name = body.prefix(while: { $0 != ">" && $0 != " " && $0 != "/" })
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            Self.log("\(url.absoluteString) \(name): sem resposta")
            return nil
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        Self.log("\(url.absoluteString) \(name): HTTP \(code) \(text.prefix(300).replacingOccurrences(of: "\n", with: " "))")
        return code == 200 ? text : nil
    }

    private func envelope(_ body: String) -> String {
        var header = ""
        if !username.isEmpty {
            var nonce = Data(count: 16)
            _ = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            let created = f.string(from: Date())
            let digest = Data(Insecure.SHA1.hash(data: nonce + Data(created.utf8) + Data(password.utf8))).base64EncodedString()
            header = """
            <s:Header><wsse:Security s:mustUnderstand="1" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"><wsse:UsernameToken><wsse:Username>\(username)</wsse:Username><wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">\(digest)</wsse:Password><wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">\(nonce.base64EncodedString())</wsse:Nonce><wsu:Created>\(created)</wsu:Created></wsse:UsernameToken></wsse:Security></s:Header>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" \
        xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:trt="http://www.onvif.org/ver10/media/wsdl" \
        xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">\(header)<s:Body>\(body)</s:Body></s:Envelope>
        """
    }
}
