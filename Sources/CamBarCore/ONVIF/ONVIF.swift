import CryptoKit
import Foundation

/// Where to send PTZ commands for one camera.
package struct PTZEndpoint: Equatable, Sendable {
    package var url: URL
    package var profileToken: String

    package init(url: URL, profileToken: String) {
        self.url = url
        self.profileToken = profileToken
    }
}

/// SOAP messages, WS-Security and response parsing for the few ONVIF calls CamBar needs.
package enum ONVIF {
    // MARK: Request bodies

    package static let getCapabilities = "<tds:GetCapabilities><tds:Category>All</tds:Category></tds:GetCapabilities>"
    package static let getProfiles = "<trt:GetProfiles/>"

    package static func continuousMove(token: String, pan: Double, tilt: Double, zoom: Double) -> String {
        "<tptz:ContinuousMove><tptz:ProfileToken>\(token.xmlEscaped)</tptz:ProfileToken><tptz:Velocity>"
            + "<tt:PanTilt x=\"\(pan)\" y=\"\(tilt)\"/><tt:Zoom x=\"\(zoom)\"/></tptz:Velocity></tptz:ContinuousMove>"
    }

    package static func stop(token: String) -> String {
        "<tptz:Stop><tptz:ProfileToken>\(token.xmlEscaped)</tptz:ProfileToken>"
            + "<tptz:PanTilt>true</tptz:PanTilt><tptz:Zoom>true</tptz:Zoom></tptz:Stop>"
    }

    package static func gotoHome(token: String) -> String {
        "<tptz:GotoHomePosition><tptz:ProfileToken>\(token.xmlEscaped)</tptz:ProfileToken></tptz:GotoHomePosition>"
    }

    // MARK: Envelope and WS-Security

    package static func envelope(body: String, header: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" \
        xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:trt="http://www.onvif.org/ver10/media/wsdl" \
        xmlns:tptz="http://www.onvif.org/ver20/ptz/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">\
        \(header)<s:Body>\(body)</s:Body></s:Envelope>
        """
    }

    /// WS-Security digest: Base64(SHA1(nonce + created + password)).
    package static func passwordDigest(nonce: Data, created: String, password: String) -> String {
        Data(Insecure.SHA1.hash(data: nonce + Data(created.utf8) + Data(password.utf8))).base64EncodedString()
    }

    package static func securityHeader(username: String, password: String, nonce: Data, created: String) -> String {
        let digest = passwordDigest(nonce: nonce, created: created, password: password)
        return """
        <s:Header><wsse:Security s:mustUnderstand="1" \
        xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" \
        xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">\
        <wsse:UsernameToken><wsse:Username>\(username.xmlEscaped)</wsse:Username>\
        <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">\(digest)</wsse:Password>\
        <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">\(nonce.base64EncodedString())</wsse:Nonce>\
        <wsu:Created>\(created)</wsu:Created></wsse:UsernameToken></wsse:Security></s:Header>
        """
    }

    // MARK: Response parsing

    /// The `XAddr` of a service in a GetCapabilities response (`Media`, `PTZ`, …).
    package static func serviceAddress(_ service: String, in xml: String) -> String? {
        let pattern = "<[\\w]*:?\(service)>\\s*<[\\w]*:?XAddr>([^<]+)</"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let profileRegex = try! NSRegularExpression(
        pattern: "<[\\w]*:?Profiles[^>]*token=\"([^\"]+)\"[^>]*>(.*?)</[\\w]*:?Profiles>",
        options: [.dotMatchesLineSeparators])

    /// Token of the first media profile that has a PTZ configuration (none means the camera is fixed).
    package static func ptzProfileToken(in xml: String) -> String? {
        for match in profileRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            guard let token = Range(match.range(at: 1), in: xml),
                  let body = Range(match.range(at: 2), in: xml) else { continue }
            if xml[body].contains("PTZConfiguration") { return String(xml[token]) }
        }
        return nil
    }

    /// Cameras often advertise an internal address; keep the path but talk to the host the user configured.
    package static func rewrite(_ address: String, host: String) -> URL? {
        guard var components = URLComponents(string: address) else { return nil }
        components.host = host
        return components.url
    }
}

/// Minimal ONVIF client: discovery of the PTZ service and continuous moves.
package struct ONVIFClient: Sendable {
    /// Ports tried when the camera has none configured (5000 is common on Yoosee-style cameras).
    package static let defaultPorts = [5000, 80, 8080]

    private let username: String
    private let password: String
    private let session: URLSession
    private let log: FileLog?

    package init(username: String, password: String, session: URLSession = .shared, log: FileLog? = nil) {
        self.username = username
        self.password = password
        self.session = session
        self.log = log
    }

    /// Finds the PTZ service and a profile that supports it. `nil` means fixed camera or no ONVIF.
    package func discoverPTZ(host: String, ports: [Int]) async -> PTZEndpoint? {
        for port in ports {
            guard let device = URL(string: "http://\(host):\(port)/onvif/device_service"),
                  let capabilities = await call(device, ONVIF.getCapabilities),
                  let ptzAddress = ONVIF.serviceAddress("PTZ", in: capabilities),
                  let ptzURL = ONVIF.rewrite(ptzAddress, host: host) else { continue }
            let mediaURL = ONVIF.serviceAddress("Media", in: capabilities).flatMap { ONVIF.rewrite($0, host: host) } ?? device
            guard let profiles = await call(mediaURL, ONVIF.getProfiles),
                  let token = ONVIF.ptzProfileToken(in: profiles) else { continue }
            return PTZEndpoint(url: ptzURL, profileToken: token)
        }
        return nil
    }

    package func continuousMove(_ endpoint: PTZEndpoint, pan: Double, tilt: Double, zoom: Double) async {
        _ = await call(endpoint.url, ONVIF.continuousMove(token: endpoint.profileToken, pan: pan, tilt: tilt, zoom: zoom))
    }

    package func stop(_ endpoint: PTZEndpoint) async {
        _ = await call(endpoint.url, ONVIF.stop(token: endpoint.profileToken))
    }

    package func goHome(_ endpoint: PTZEndpoint) async {
        _ = await call(endpoint.url, ONVIF.gotoHome(token: endpoint.profileToken))
    }

    // MARK: Transport

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Returns the response body on HTTP 200. Responses (never requests, which carry credentials) are logged.
    private func call(_ url: URL, _ body: String) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/soap+xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(ONVIF.envelope(body: body, header: securityHeader()).utf8)

        let action = body.dropFirst().prefix(while: { $0 != ">" && $0 != " " && $0 != "/" })
        guard let (data, response) = try? await session.data(for: request) else {
            log?.append("\(url.absoluteString) \(action): sem resposta")
            return nil
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        log?.append("\(url.absoluteString) \(action): HTTP \(status) \(text.prefix(300).replacingOccurrences(of: "\n", with: " "))")
        return status == 200 ? text : nil
    }

    private func securityHeader() -> String {
        guard !username.isEmpty else { return "" }
        var nonce = Data(count: 16)
        _ = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return ONVIF.securityHeader(username: username, password: password, nonce: nonce,
                                    created: Self.timestamp.string(from: Date()))
    }
}

extension String {
    /// Escapes the five XML special characters.
    package var xmlEscaped: String {
        var out = ""
        out.reserveCapacity(count)
        for ch in self {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}
