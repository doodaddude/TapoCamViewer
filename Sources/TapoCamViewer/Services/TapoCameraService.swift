import Foundation

public final class TapoCameraService {
    public static let shared = TapoCameraService()

    private init() {}

    private func getPythonCredentials(for camera: TapoCameraConfig) -> (user: String, pass: String) {
        let cloudUser = UserDefaults.standard.string(forKey: "tapo_cloud_username") ?? camera.username
        let cloudPass = UserDefaults.standard.string(forKey: "tapo_cloud_password") ?? (camera.cloudPassword.isEmpty ? camera.password : camera.cloudPassword)
        return (cloudUser, cloudPass)
    }

    private func executeBridge(action: String, payload: [String: Any]) async -> [String: Any]? {
        let scriptURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/TapoRecordingBridge.py")
        let scriptPath = FileManager.default.fileExists(atPath: scriptURL.path)
            ? scriptURL.path
            : "/Users/mac/.gemini/antigravity/scratch/TapoCamViewer/Sources/TapoCamViewer/Services/TapoRecordingBridge.py"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath, action]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    stdinPipe.fileHandleForWriting.write(jsonData)
                    try? stdinPipe.fileHandleForWriting.close()
                    process.waitUntilExit()

                    let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if let json = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any] {
                        continuation.resume(returning: json)
                        return
                    }
                } catch {
                    print("Error executing bridge action \(action):", error)
                }
                continuation.resume(returning: nil)
            }
        }
    }

    /// Query the camera for recorded entries from its SD card, enriched with detection event types.
    /// Returns the clip array and an optional count of raw detection events used for enrichment.
    public func fetchRecordingsWithEventCount(camera: TapoCameraConfig, dateString: String) async -> ([TapoRecordingClip], Int?) {
        let cleanIP = camera.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIP.isEmpty else { return ([], nil) }

        let creds = getPythonCredentials(for: camera)
        let payload: [String: Any] = [
            "ip":       cleanIP,
            "user":     creds.user,
            "password": creds.pass,
            "date":     dateString
        ]

        guard let json = await executeBridge(action: "get_recordings", payload: payload),
              let clipsArray = json["clips"] as? [[String: Any]] else {
            return ([], nil)
        }

        let eventCount = json["eventCount"] as? Int

        var result: [TapoRecordingClip] = []
        for item in clipsArray {
            if let st = item["startTime"] as? Int,
               let et = item["endTime"] as? Int {
                let rawType   = item["type"]      as? Int    ?? 1
                let eventCode = item["eventCode"] as? Int    ?? 1
                let eventType = item["eventType"] as? String ?? "Continuous"
                let iconName  = item["iconName"]  as? String ?? "film"
                let color     = item["color"]     as? String ?? "gray"
                result.append(TapoRecordingClip(
                    startTime:  st,
                    endTime:    et,
                    rawType:    rawType,
                    eventCode:  eventCode,
                    eventType:  eventType,
                    iconName:   iconName,
                    eventColor: color
                ))
            }
        }
        return (result, eventCount)
    }

    /// Legacy variant — delegates to enriched version.
    public func fetchRecordings(camera: TapoCameraConfig, dateString: String) async -> [TapoRecordingClip] {
        let (clips, _) = await fetchRecordingsWithEventCount(camera: camera, dateString: dateString)
        return clips
    }

    /// Fetch Alarm status and all detection capabilities from the Tapo Camera
    public func fetchSecurityState(camera: TapoCameraConfig) async -> TapoSecurityState? {
        let cleanIP = camera.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIP.isEmpty else { return nil }

        let creds = getPythonCredentials(for: camera)
        let payload: [String: Any] = [
            "ip": cleanIP,
            "user": creds.user,
            "password": creds.pass
        ]

        guard let json = await executeBridge(action: "get_alarm_and_detections", payload: payload),
              json["status"] as? String == "ok" else {
            return nil
        }

        // Parse Alarm
        var alarmSettings = TapoAlarmSettings()
        if let alarmDict = json["alarm"] as? [String: Any] {
            let isUnsupported = alarmDict["unsupported"] as? Bool ?? false
            alarmSettings.isSupported = !isUnsupported
            alarmSettings.isEnabled = (alarmDict["enabled"] as? String) == "on"
            alarmSettings.soundEnabled = (alarmDict["sound_alarm_enabled"] as? String) == "on" ||
                ((alarmDict["alarm_mode"] as? [String])?.contains("sound") ?? false)
            alarmSettings.lightEnabled = (alarmDict["light_alarm_enabled"] as? String) == "on" ||
                ((alarmDict["alarm_mode"] as? [String])?.contains("light") ?? false)
        }

        // Helper to parse detection config
        func parseDetection(key: String, title: String, icon: String) -> TapoDetectionItem {
            guard let dict = json[key] as? [String: Any] else {
                return TapoDetectionItem(key: key, title: title, iconName: icon, isSupported: false, isEnabled: false, sensitivity: nil)
            }
            if dict["unsupported"] as? Bool == true {
                return TapoDetectionItem(key: key, title: title, iconName: icon, isSupported: false, isEnabled: false, sensitivity: nil)
            }
            let isEnabled = (dict["enabled"] as? String) == "on"
            var sens: Int? = nil
            if let sStr = dict["sensitivity"] as? String, let sVal = Int(sStr) {
                sens = sVal
            } else if let sNum = dict["digital_sensitivity"] as? String, let sVal = Int(sNum) {
                sens = sVal
            }
            return TapoDetectionItem(key: key, title: title, iconName: icon, isSupported: true, isEnabled: isEnabled, sensitivity: sens)
        }

        let detections: [TapoDetectionItem] = [
            parseDetection(key: "person", title: "Person Detection", icon: "figure.walk"),
            parseDetection(key: "motion", title: "Motion Detection", icon: "sensor.tag.radiowaves.forward.fill"),
            parseDetection(key: "vehicle", title: "Vehicle Detection", icon: "car.fill"),
            parseDetection(key: "pet", title: "Pet Detection", icon: "pawprint.fill"),
            parseDetection(key: "tamper", title: "Tamper Detection", icon: "shield.exclamationmark.fill"),
            parseDetection(key: "baby_cry", title: "Baby Crying Detection", icon: "waveform.path.ecg"),
            parseDetection(key: "bark", title: "Bark Detection", icon: "speaker.wave.3.fill"),
            parseDetection(key: "glass", title: "Glass Break Detection", icon: "sparkles.rectangle.stack.fill")
        ]

        return TapoSecurityState(alarm: alarmSettings, detections: detections)
    }

    /// Update the Alarm settings on the Tapo camera
    public func setAlarm(
        camera: TapoCameraConfig,
        enabled: Bool,
        soundEnabled: Bool,
        lightEnabled: Bool
    ) async -> Bool {
        let cleanIP = camera.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIP.isEmpty else { return false }

        let creds = getPythonCredentials(for: camera)
        let payload: [String: Any] = [
            "ip": cleanIP,
            "user": creds.user,
            "password": creds.pass,
            "enabled": enabled,
            "soundEnabled": soundEnabled,
            "lightEnabled": lightEnabled
        ]

        guard let json = await executeBridge(action: "set_alarm", payload: payload) else { return false }
        return json["status"] as? String == "ok"
    }

    /// Update a specific detection feature (e.g. person, motion, vehicle)
    public func setDetection(
        camera: TapoCameraConfig,
        target: String,
        enabled: Bool,
        sensitivity: Int? = nil
    ) async -> Bool {
        let cleanIP = camera.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIP.isEmpty else { return false }

        let creds = getPythonCredentials(for: camera)
        var payload: [String: Any] = [
            "ip": cleanIP,
            "user": creds.user,
            "password": creds.pass,
            "target": target,
            "enabled": enabled
        ]
        if let sens = sensitivity {
            payload["sensitivity"] = sens
        }

        guard let json = await executeBridge(action: "set_detection", payload: payload) else { return false }
        return json["status"] as? String == "ok"
    }

    /// Downloads an MP4 segment from the camera stream or go2rtc recorder directly to local storage.
    public func saveClipLocally(from url: URL, suggestedName: String) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)

        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let tapoDir = moviesDir.appendingPathComponent("TapoRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: tapoDir, withIntermediateDirectories: true)

        let targetURL = tapoDir.appendingPathComponent("\(suggestedName).mp4")
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: targetURL)
        return targetURL
    }
}
