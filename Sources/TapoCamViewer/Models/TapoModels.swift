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
    public var cameraNumber: Int
    public var iconName: String
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
        cameraNumber: Int = 1,
        iconName: String = "video.fill",
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
        self.cameraNumber = cameraNumber
        self.iconName = iconName
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

    enum CodingKeys: String, CodingKey {
        case id, cameraNumber, iconName, name, ipAddress, port, username, password, cloudPassword, quality, isEnabled, customRTSPUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.cameraNumber = try container.decodeIfPresent(Int.self, forKey: .cameraNumber) ?? 1
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "video.fill"
        self.name = try container.decode(String.self, forKey: .name)
        self.ipAddress = try container.decode(String.self, forKey: .ipAddress)
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 554
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? "admin"
        self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        self.cloudPassword = try container.decodeIfPresent(String.self, forKey: .cloudPassword) ?? ""
        self.quality = try container.decodeIfPresent(StreamQuality.self, forKey: .quality) ?? .high
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.customRTSPUrl = try container.decodeIfPresent(String.self, forKey: .customRTSPUrl)
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

public struct CameraIconOption: Identifiable, Hashable {
    public var id: String { symbol }
    public let symbol: String
    public let label: String
    public let category: String

    public init(_ symbol: String, label: String, category: String) {
        self.symbol = symbol
        self.label = label
        self.category = category
    }
}

public struct CameraIconLibrary {
    public static let options: [CameraIconOption] = [
        // Camera & Security
        CameraIconOption("video.fill", label: "Video", category: "Cameras"),
        CameraIconOption("camera.fill", label: "Camera", category: "Cameras"),
        CameraIconOption("web.camera.fill", label: "Webcam", category: "Cameras"),
        CameraIconOption("video.doorbell.fill", label: "Doorbell", category: "Cameras"),
        CameraIconOption("eye.fill", label: "Surveillance", category: "Cameras"),
        CameraIconOption("shield.fill", label: "Shield", category: "Cameras"),
        CameraIconOption("sensor.fill", label: "Sensor", category: "Cameras"),

        // Entrances & Doors
        CameraIconOption("door.front.left", label: "Front Door", category: "Entrances"),
        CameraIconOption("door.left.hand.open", label: "Open Door", category: "Entrances"),
        CameraIconOption("bell.fill", label: "Chime", category: "Entrances"),
        CameraIconOption("key.fill", label: "Key Entry", category: "Entrances"),
        CameraIconOption("lock.fill", label: "Lock", category: "Entrances"),

        // Rooms & Spaces
        CameraIconOption("sofa.fill", label: "Living Room", category: "Rooms"),
        CameraIconOption("tv.fill", label: "TV / Den", category: "Rooms"),
        CameraIconOption("bed.double.fill", label: "Bedroom", category: "Rooms"),
        CameraIconOption("bed.single.fill", label: "Guest Room", category: "Rooms"),
        CameraIconOption("fork.knife", label: "Kitchen", category: "Rooms"),
        CameraIconOption("cup.and.saucer.fill", label: "Dining", category: "Rooms"),
        CameraIconOption("lamp.desk.fill", label: "Office", category: "Rooms"),
        CameraIconOption("desktopcomputer", label: "Desk", category: "Rooms"),
        CameraIconOption("stairs", label: "Stairs / Hall", category: "Rooms"),

        // Family & Pets
        CameraIconOption("figure.child", label: "Kids Room", category: "Family"),
        CameraIconOption("figure.and.child.holdinghands", label: "Nursery", category: "Family"),
        CameraIconOption("teddybear.fill", label: "Playroom", category: "Family"),
        CameraIconOption("pawprint.fill", label: "Pet Area", category: "Family"),

        // Outdoors & Vehicles
        CameraIconOption("car.fill", label: "Driveway", category: "Outdoors"),
        CameraIconOption("car.side.fill", label: "Garage", category: "Outdoors"),
        CameraIconOption("tree.fill", label: "Backyard", category: "Outdoors"),
        CameraIconOption("leaf.fill", label: "Garden", category: "Outdoors"),
        CameraIconOption("sun.max.fill", label: "Patio / Deck", category: "Outdoors"),
        CameraIconOption("house.fill", label: "House Front", category: "Outdoors")
    ]
}

public enum TapoStreamState: Equatable {
    case connecting
    case playing
    case stalled(reason: String)
    case disconnected(reason: String)

    public var isStalledOrDisconnected: Bool {
        switch self {
        case .stalled, .disconnected:
            return true
        case .connecting, .playing:
            return false
        }
    }
}

extension Notification.Name {
    public static let tapoStreamsNeedReload = Notification.Name("tapoStreamsNeedReload")
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
