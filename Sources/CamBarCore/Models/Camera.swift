import Foundation

/// How ffmpeg talks RTSP to the camera.
package enum RTSPTransport: String, Codable, CaseIterable, Sendable {
    case auto, udp, tcp, http

    /// Arguments that force this transport; `auto` lets ffmpeg negotiate.
    package var ffmpegArguments: [String] {
        self == .auto ? [] : ["-rtsp_transport", rawValue]
    }
}

/// A camera as the user configured it. The password is not part of it: it lives in the Keychain.
package struct Camera: Identifiable, Hashable, Sendable {
    package var id: UUID
    package var name: String
    package var host: String
    package var port: Int
    package var path: String
    package var username: String
    package var transport: RTSPTransport
    /// ONVIF service port used for PTZ; `nil` tries the usual ones.
    package var onvifPort: Int?

    package init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 554,
        path: String = "/",
        username: String = "",
        transport: RTSPTransport = .auto,
        onvifPort: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.path = path
        self.username = username
        self.transport = transport
        self.onvifPort = onvifPort
    }

    package var normalizedPath: String { path.hasPrefix("/") ? path : "/" + path }

    /// `host:port`, for labels.
    package var endpoint: String { "\(host):\(port)" }

    /// Stream address without credentials, safe to show on screen.
    package var displayURL: String { "rtsp://\(host.isEmpty ? "…" : host):\(port)\(normalizedPath)" }

    /// Full stream address. Credentials are percent-encoded, so passwords with `@`, `:` or `/` work.
    package func rtspURL(password: String) -> String {
        var auth = ""
        if !username.isEmpty {
            let user = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let pass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            auth = password.isEmpty ? "\(user)@" : "\(user):\(pass)@"
        }
        return "rtsp://\(auth)\(host):\(port)\(normalizedPath)"
    }
}

extension Camera: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, path, username, transport, onvifPort
    }

    /// Tolerates data saved by older versions (missing fields, `transport` stored as null).
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 554
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? "/"
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        transport = (try? c.decodeIfPresent(RTSPTransport.self, forKey: .transport)) ?? .auto
        onvifPort = try c.decodeIfPresent(Int.self, forKey: .onvifPort)
    }
}
