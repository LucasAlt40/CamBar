import CamBarCore
import Foundation

// Self-checks for CamBarCore. Run with `swift run CamBarChecks`.
// (XCTest and Swift Testing are not available without a full Xcode install.)

var failures = 0
var total = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    total += 1
    if !condition() {
        failures += 1
        print("  ✗ \(message) (linha \(line))")
    }
}

func suite(_ name: String, _ body: () throws -> Void) {
    print("• \(name)")
    do { try body() } catch {
        failures += 1
        print("  ✗ erro inesperado: \(error)")
    }
}

suite("Camera") {
    let cam = Camera(name: "Garagem", host: "192.168.1.10", path: "onvif1", username: "admin")
    check(cam.normalizedPath == "/onvif1", "caminho ganha a barra inicial")
    check(cam.rtspURL(password: "@ab:c/d") == "rtsp://admin:%40ab%3Ac%2Fd@192.168.1.10:554/onvif1",
          "senha com @ : / é codificada")
    check(cam.rtspURL(password: "") == "rtsp://admin@192.168.1.10:554/onvif1", "sem senha mantém só o usuário")
    check(Camera(host: "1.2.3.4").rtspURL(password: "x") == "rtsp://1.2.3.4:554/", "sem usuário não envia credenciais")
    check(cam.displayURL == "rtsp://192.168.1.10:554/onvif1", "displayURL não mostra credenciais")

    let legacy = #"[{"id":"7C1C3A5E-2F14-4E0E-9C3C-1B8D4F6A9E21","name":"A","host":"h","port":554,"path":"/","username":"u","transport":null}]"#
    let decoded = try JSONDecoder().decode([Camera].self, from: Data(legacy.utf8))
    check(decoded.first?.transport == .auto, "dado antigo com transport null vira automático")
    check(decoded.first?.onvifPort == nil, "dado antigo sem onvifPort")

    let roundTrip = try JSONDecoder().decode(Camera.self, from: JSONEncoder().encode(cam))
    check(roundTrip == cam, "codifica e decodifica sem perda")
}

suite("Transporte e comando do ffmpeg") {
    check(RTSPTransport.auto.ffmpegArguments.isEmpty, "automático não força transporte")
    check(RTSPTransport.tcp.ffmpegArguments == ["-rtsp_transport", "tcp"], "tcp forçado")

    let standby = FFmpeg.videoArguments(url: "rtsp://x", transport: .udp, profile: .standby)
    check(standby.contains("nokey"), "espera decodifica só quadros-chave")
    check(standby.contains("scale='min(480,iw)':-2"), "espera usa 480 px")
    let hd = FFmpeg.videoArguments(url: "rtsp://x", transport: .auto, profile: .hd)
    check(!hd.contains("nokey"), "HD decodifica todos os quadros")
    check(hd.contains("scale='min(1280,iw)':-2"), "HD usa 1280 px")
    check(hd.last == "pipe:1", "saída no stdout")
}

suite("MJPEGParser") {
    let frameA = Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9])
    let frameB = Data([0xFF, 0xD8, 0x03, 0xFF, 0xD9])
    var parser = MJPEGParser()
    check(parser.append(Data([0x00, 0x11]) + frameA.prefix(3)).isEmpty, "quadro incompleto não sai")
    let out = parser.append(frameA.dropFirst(3) + frameB)
    check(out == [frameA, frameB], "junta pedaços e separa dois quadros")

    var small = MJPEGParser(maxBufferSize: 4)
    _ = small.append(Data([0xFF, 0xD8, 1, 2, 3, 4, 5]))
    check(small.append(frameA) == [frameA], "buffer corrompido é descartado")
}

suite("Log do ffmpeg") {
    var parser = FFmpegLogParser()
    let changed = parser.consume("""
      Stream #0:0: Video: h264 (Main), 1 reference frame, yuvj420p(pc, bt709, progressive, left), 2304x1296, 15 fps, 15 tbr, 90k tbn
      Stream #0:1: Audio: pcm_alaw, 16000 Hz, mono, s16, 128 kb/s
      Stream #0:0: Video: mjpeg, 1 reference frame, yuvj420p(pc, bt709, progressive), 1280x720, q=2-31, 200 kb/s, 12 fps
    """)
    check(changed, "telemetria encontrada")
    check(parser.info == StreamInfo(width: 2304, height: 1296, fps: 15, codec: "H.264 Main", hasAudio: true),
          "lê a entrada e ignora a saída mjpeg")
    check(parser.info?.summary == "2304×1296 • 15 FPS • H.264 Main", "resumo da telemetria")

    let hevc = FFmpegLogParser.parseVideo("Stream #0:0: Video: hevc (Main), yuv420p(tv), 1920x1080, 15 fps, 15 tbr")
    check(hevc?.codec == "H.265 Main" && hevc?.width == 1920, "H.265")

    var split = FFmpegLogParser()
    split.consume("  Stream #0:1: Audio: pcm_alaw, 16000 Hz, mono\n  Stream #0:0: Video: hevc (Main), yuv420p(tv), 19")
    check(split.info?.hasVideo == false, "linha cortada ainda não conta")
    split.consume("20x1080, 15 fps, 15 tbr\n")
    check(split.info?.resolution == "1920×1080" && split.info?.hasAudio == true, "junta linha dividida em dois pedaços")

    parser.consume("Error opening input files: Server returned 400 Bad Request")
    parser.finish()
    check(StreamFailure.classify(parser.lastError) == .badRequest, "guarda a última linha de erro")
}

suite("Classificação de erros") {
    check(StreamFailure.classify("Server returned 4XX Client Error, but not one of 40{0,1,3,4}") == .notRTSP, "405")
    check(StreamFailure.classify("method DESCRIBE failed: 401 Unauthorized") == .unauthorized, "401")
    check(StreamFailure.classify("Server returned 404 Not Found") == .pathNotFound, "404")
    check(StreamFailure.classify("Connection to tcp://1.2.3.4:554 failed: Connection refused") == .unreachable, "recusado")
    check(StreamFailure.classify("algo estranho") == .unknown, "desconhecido")
}

suite("Mascaramento do log") {
    check(FileLog.mask("rtsp://admin:%40x@192.168.1.10:554/onvif1") == "rtsp://***@192.168.1.10:554/onvif1", "esconde credenciais")
    check(FileLog.mask("rtsp://192.168.1.10:554/onvif1") == "rtsp://192.168.1.10:554/onvif1", "URL sem credenciais intacta")
}

suite("PCMConverter") {
    var converter = PCMConverter()
    check(converter.convert(Data([0x00])).isEmpty, "meio sample fica guardado")
    check(converter.convert(Data([0x80, 0xFF, 0x7F])) == [-1, Float(32767) / 32768], "junta o byte guardado")
    check(converter.convert(Data()).isEmpty, "chunk vazio")
}

suite("ONVIF") {
    // Example from the ONVIF Application Programmer's Guide.
    let digest = ONVIF.passwordDigest(nonce: Data(base64Encoded: "LKqI6G/AikKCQrN0zqZFlg==")!,
                                      created: "2010-09-16T07:50:45Z", password: "userpassword")
    check(digest == "tuOSpGlFlIXsozq4HFNeeGeFLEI=", "digest WS-Security")

    let caps = """
    <tt:Media><tt:XAddr>http://10.0.0.9:5000/onvif/media</tt:XAddr></tt:Media>
    <tt:PTZ> <tt:XAddr>http://10.0.0.9:5000/onvif/ptz</tt:XAddr></tt:PTZ>
    """
    check(ONVIF.serviceAddress("PTZ", in: caps) == "http://10.0.0.9:5000/onvif/ptz", "endereço do PTZ")
    check(ONVIF.rewrite("http://10.0.0.9:5000/onvif/ptz", host: "192.168.1.10")?.absoluteString
          == "http://192.168.1.10:5000/onvif/ptz", "troca o host interno pelo configurado")

    let profiles = """
    <trt:Profiles token="fixed"><tt:Name>a</tt:Name></trt:Profiles>
    <trt:Profiles fixed="true" token="moving"><tt:PTZConfiguration token="p"/></trt:Profiles>
    """
    check(ONVIF.ptzProfileToken(in: profiles) == "moving", "escolhe o perfil com PTZ")
    check(ONVIF.ptzProfileToken(in: "<trt:Profiles token=\"x\"></trt:Profiles>") == nil, "câmera fixa")
    check("a<b>&\"'".xmlEscaped == "a&lt;b&gt;&amp;&quot;&apos;", "escapa XML")
}

suite("Repositórios em memória") {
    let repo = InMemoryCameraRepository()
    repo.save([Camera(name: "X")])
    check(repo.load().map(\.name) == ["X"], "salva e carrega")
    let creds = InMemoryCredentialStore()
    let id = UUID()
    creds.setPassword("s", for: id)
    check(creds.password(for: id) == "s", "guarda senha")
    creds.setPassword("", for: id)
    check(creds.password(for: id).isEmpty, "senha vazia remove")
}

print(failures == 0 ? "\n\(total) checks passaram." : "\n\(failures) de \(total) checks falharam.")
exit(failures == 0 ? 0 : 1)
