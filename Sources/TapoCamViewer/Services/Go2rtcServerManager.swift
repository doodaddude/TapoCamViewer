import Foundation
import Combine
import AppKit

@MainActor
public final class Go2rtcServerManager: ObservableObject {
    public static let shared = Go2rtcServerManager()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var statusMessage: String = "Stopped"

    private var process: Process?
    public let apiPort: Int = 1984
    public let rtspPort: Int = 8554

    public var apiBaseURL: String { "http://127.0.0.1:\(apiPort)" }

    private var configPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.tapo.camviewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("go2rtc.yaml")
    }

    private var binaryPath: String {
        // Look in app bundle or scratch project bin
        if let bundleBin = Bundle.main.path(forResource: "go2rtc", ofType: nil) {
            return bundleBin
        }
        let fallback = "/Users/mac/.gemini/antigravity/scratch/TapoCamViewer/bin/go2rtc"
        if FileManager.default.fileExists(atPath: fallback) {
            return fallback
        }
        return "/tmp/go2rtc"
    }

    private init() {}

    public func start(cameras: [TapoCameraConfig]) {
        stop()
        writeConfigFile(cameras: cameras)

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            statusMessage = "go2rtc binary not found"
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["-config", configPath.path]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do {
            try p.run()
            self.process = p
            self.isRunning = true
            self.statusMessage = "Streaming Engine Online (Port \(apiPort))"
        } catch {
            self.statusMessage = "Failed to launch streaming engine: \(error.localizedDescription)"
        }
    }

    public func updateCameras(_ cameras: [TapoCameraConfig]) {
        if isRunning {
            start(cameras: cameras)
        }
    }

    public func stop() {
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        isRunning = false
        statusMessage = "Stopped"
    }

    private func writeConfigFile(cameras: [TapoCameraConfig]) {
        var yaml = """
        api:
          listen: "127.0.0.1:\(apiPort)"
        rtsp:
          listen: "127.0.0.1:\(rtspPort)"
        webrtc:
          listen: "127.0.0.1:8555"

        streams:

        """

        for (_, cam) in cameras.enumerated() {
            guard cam.isEnabled, !cam.ipAddress.isEmpty else { continue }
            let streamName = "cam_\(cam.id)"
            yaml += "  \(streamName):\n"
            yaml += "    - \(cam.rtspURL)\n"
        }

        try? yaml.write(to: configPath, atomically: true, encoding: .utf8)
    }

    public func webRTCStreamURL(for camId: String) -> URL? {
        URL(string: "\(apiBaseURL)/stream.html?src=cam_\(camId)")
    }

    public func mp4StreamURL(for camId: String) -> URL? {
        URL(string: "\(apiBaseURL)/api/stream.mp4?src=cam_\(camId)")
    }

    public func mp4RecordURL(for camId: String, durationSeconds: Int) -> URL? {
        URL(string: "\(apiBaseURL)/api/stream.mp4?src=cam_\(camId)&duration=\(durationSeconds)")
    }
}
