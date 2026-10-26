import Foundation

public enum StreamQuality: String, Codable, CaseIterable {
    case high = "High (stream1 - 1080p/2K/4K)"
    case low = "Low (stream2 - 360p/Fluid)"

    public var streamPath: String {
        switch self {
        case .high: return "stream1"
        case .low: return "stream2"
        }
    }
}

public struct TapoCameraConfig: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var ipAddress: String
    public var port: Int
    public var username: String
    public var password: String
    public var cloudPassword: String
    public var quality: StreamQuality
    public var isEnabled: Bool
    public var customRTSPUrl: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        ipAddress: String,
        port: Int = 554,
        username: String = "admin",
        password: String = "",
        cloudPassword: String = "",
        quality: StreamQuality = .high,
        isEnabled: Bool = true,
        customRTSPUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.port = port
        self.username = username
        self.password = password
        self.cloudPassword = cloudPassword
        self.quality = quality
        self.isEnabled = isEnabled
        self.customRTSPUrl = customRTSPUrl
    }

    public var rtspURL: String {
        if let custom = customRTSPUrl, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        let cleanIP = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanUser.isEmpty && cleanPass.isEmpty {
            return "rtsp://\(cleanIP):\(port)/\(quality.streamPath)#transport=tcp"
        }
        return "rtsp://\(cleanUser):\(cleanPass)@\(cleanIP):\(port)/\(quality.streamPath)#transport=tcp"
    }
}

public struct TapoRecordingClip: Identifiable, Codable, Equatable {
    public var id: String { "\(startTime)_\(endTime)" }
    public var startTime: Int    // Unix timestamp
    public var endTime: Int      // Unix timestamp
    public var duration: Int { max(0, endTime - startTime) }

    // Raw SD card video_type (1 = continuous, 2 = motion-triggered recording)
    public var rawType: Int

    // Enriched event classification from getEvents() detection overlay
    public var eventCode: Int       // e.g. 6 = Person, 5 = Area Intrusion, 2 = Motion, 1 = Continuous
    public var eventType: String    // e.g. "Person", "Area Intrusion", "Line Crossing"
    public var iconName: String     // SF Symbol name
    public var eventColor: String   // semantic color name from bridge

    // Derived helpers
    public var isMotion: Bool { rawType == 2 || eventCode > 1 }

    public var badgeColor: EventBadgeColor {
        switch eventCode {
        case 6:        return .purple   // Person
        case 9:        return .green    // Pet
        case 8:        return .blue     // Vehicle
        case 5, 3, 13: return .red      // Area Intrusion, Tamper, Glass Break
        case 4:        return .cyan     // Line Crossing
        case 7, 11, 12: return .pink   // Baby Cry, Bark, Meow
        case 10:       return .yellow   // Ring Alarm
        case 2:        return .orange   // Motion
        default:       return .secondary // Continuous
        }
    }

    public var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(startTime))
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .medium
        return df.string(from: date)
    }

    public var timeRangeString: String {
        let d1 = Date(timeIntervalSince1970: TimeInterval(startTime))
        let d2 = Date(timeIntervalSince1970: TimeInterval(endTime))
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        return "\(tf.string(from: d1)) - \(tf.string(from: d2))"
    }

    public init(
        startTime: Int,
        endTime: Int,
        rawType: Int = 1,
        eventCode: Int = 1,
        eventType: String = "Continuous",
        iconName: String = "film",
        eventColor: String = "gray"
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.rawType = rawType
        self.eventCode = eventCode
        self.eventType = eventType
        self.iconName = iconName
        self.eventColor = eventColor
    }
}

/// Semantic badge colours for recording event types
public enum EventBadgeColor {
    case purple, green, blue, red, cyan, pink, yellow, orange, secondary
}

// MARK: - Detection Feature & Alarm Settings Models

public struct TapoDetectionItem: Identifiable, Codable, Equatable {
    public var id: String { key }
    public var key: String         // e.g. "person", "motion", "vehicle", "pet", "tamper", "baby_cry"
    public var title: String       // e.g. "Person Detection"
    public var iconName: String    // e.g. "figure.walk", "car", "pawprint"
    public var isSupported: Bool
    public var isEnabled: Bool
    public var sensitivity: Int?   // e.g. 20, 40, 60, 80
}

public struct TapoAlarmSettings: Codable, Equatable {
    public var isSupported: Bool
    public var isEnabled: Bool
    public var soundEnabled: Bool
    public var lightEnabled: Bool
    public var alarmDuration: String?
    public var alarmVolume: String?

    public init(
        isSupported: Bool = true,
        isEnabled: Bool = false,
        soundEnabled: Bool = true,
        lightEnabled: Bool = true,
        alarmDuration: String? = nil,
        alarmVolume: String? = nil
    ) {
        self.isSupported = isSupported
        self.isEnabled = isEnabled
        self.soundEnabled = soundEnabled
        self.lightEnabled = lightEnabled
        self.alarmDuration = alarmDuration
        self.alarmVolume = alarmVolume
    }
}

public struct TapoSecurityState: Equatable {
    public var alarm: TapoAlarmSettings
    public var detections: [TapoDetectionItem]

    public init(alarm: TapoAlarmSettings = TapoAlarmSettings(), detections: [TapoDetectionItem] = []) {
        self.alarm = alarm
        self.detections = detections
    }
}
