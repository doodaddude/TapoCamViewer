import SwiftUI

public enum HotkeyChoice: Int, CaseIterable, Identifiable {
    case f1 = 122
    case f2 = 120
    case f3 = 99
    case f4 = 118
    case tilde = 50
    case space = 49
    case tab = 48
    case cKey = 8

    public var id: Int { self.rawValue }

    public var title: String {
        switch self {
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .tilde: return "Tilde (~)"
        case .space: return "Space"
        case .tab: return "Tab"
        case .cKey: return "C Key"
        }
    }
}

public enum ModifierChoice: String, CaseIterable, Identifiable {
    case none = "None (Single Key)"
    case command = "Command (⌘)"
    case control = "Control (⌃)"
    case option = "Option (⌥)"
    case shift = "Shift (⇧)"

    public var id: String { self.rawValue }
}

public struct TapoSettingsView: View {
    @Binding public var cameras: [TapoCameraConfig]
    public let onSave: () -> Void

    // Settings Navigation Tabs
    @State private var selectedTab: Int = 0

    // Camera Edit States
    @State private var selectedCamID: String?
    @State private var name: String = ""
    @State private var ipAddress: String = ""
    @State private var port: Int = 554
    @State private var username: String = "admin"
    @State private var password: String = ""
    @State private var cloudPassword: String = ""
    @State private var quality: StreamQuality = .high
    @State private var isEnabled: Bool = true
    @State private var customRTSP: String = ""

    // Detection & Alarm States
    @State private var securityState: TapoSecurityState?
    @State private var isLoadingSecurity: Bool = false
    @State private var securityFeedback: String = ""
    @State private var isSavingSecurity: Bool = false

    // Tapo Cloud Account Credentials
    @AppStorage("tapo_cloud_username") private var cloudUsername: String = ""
    @AppStorage("tapo_cloud_password") private var globalCloudPassword: String = ""

    // Hotkey & Modifier Settings (UserDefaults)
    @AppStorage("tapo_hotkey_code") private var hotkeyCode: Int = 122
    @AppStorage("tapo_hotkey_modifier") private var hotkeyModifier: String = ModifierChoice.none.rawValue
    @AppStorage("tapo_hotkey_mode") private var hotkeyMode: String = "hold" // "hold" or "toggle"

    // UI & Transparency Customization (UserDefaults)
    @AppStorage("tapo_ui_glass_header") private var glassHeader: Bool = true
    @AppStorage("tapo_ui_glass_footer") private var glassFooter: Bool = true
    @AppStorage("tapo_ui_glass_menubar") private var glassMenuBar: Bool = false
    @AppStorage("tapo_ui_contrast_boost") private var contrastBoost: Double = 1.15
    @AppStorage("tapo_ui_default_ghost_alpha") private var defaultGhostAlpha: Double = 0.25

    private var currentCamera: TapoCameraConfig? {
        cameras.first(where: { $0.id == selectedCamID })
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Modern macOS Segmented Navigation Bar
            HStack {
                Picker("", selection: $selectedTab) {
                    Label("Cameras", systemImage: "video").tag(0)
                    Label("Alarm & AI Detections", systemImage: "shield.lefthalf.filled").tag(1)
                    Label("Hotkeys", systemImage: "keyboard").tag(2)
                    Label("Appearance", systemImage: "paintpalette").tag(3)
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Active Tab Content
            Group {
                switch selectedTab {
                case 0:
                    cameraManagementView
                case 1:
                    securityControlsView
                case 2:
                    hotkeySettingsView
                case 3:
                    uiCustomizationView
                default:
                    cameraManagementView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 560)
    }

    // MARK: - Cameras Tab
    private var cameraManagementView: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Cameras (\(cameras.count)/4)")
                        .font(.headline)
                    Spacer()
                    Button {
                        addNewCamera()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(cameras.count >= 4)
                }
                .padding(12)

                Divider()

                List(selection: $selectedCamID) {
                    ForEach(cameras) { cam in
                        HStack {
                            Circle()
                                .fill(cam.isEnabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(cam.name.isEmpty ? "Unnamed Cam" : cam.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(cam.ipAddress.isEmpty ? "No IP Set" : cam.ipAddress)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(cam.id)
                    }
                    .onDelete(perform: deleteCamera)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 180)
        } detail: {
            if let id = selectedCamID, let _ = cameras.first(where: { $0.id == id }) {
                Form {
                    Section("Camera Identification") {
                        TextField("Camera Name", text: $name)
                        Toggle("Enable Camera", isOn: $isEnabled)
                    }

                    Section("Network Connection") {
                        TextField("IP Address (e.g. 192.168.1.100)", text: $ipAddress)
                        TextField("RTSP Port", value: $port, format: .number)
                        Picker("Stream Quality", selection: $quality) {
                            ForEach(StreamQuality.allCases, id: \.self) { q in
                                Text(q.rawValue).tag(q)
                            }
                        }
                    }

                    Section("Local Camera Account (For RTSP Live Streaming)") {
                        TextField("Camera Account Username", text: $username)
                        SecureField("Camera Account Password", text: $password)
                    }

                    Section("Tapo Cloud Account (For Alarm, AI Detections & SD Clips)") {
                        TextField("Tapo Cloud Email", text: $cloudUsername)
                        SecureField("Tapo Cloud Password", text: $globalCloudPassword)
                    }

                    Section("Advanced Override") {
                        TextField("Custom RTSP URL (Optional)", text: $customRTSP)
                    }

                    Section {
                        Button("Apply & Save Settings") {
                            applyChanges()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .formStyle(.grouped)
                .padding()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Select or Add a Camera")
                        .font(.headline)
                    Text("Support for up to 4 simultaneous live views on screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: selectedCamID) { newID in
            loadSelectedCam(newID)
        }
        .onAppear {
            if selectedCamID == nil {
                selectedCamID = cameras.first?.id
                loadSelectedCam(selectedCamID)
            }
        }
    }

    // MARK: - Security & AI Detection Tab
    private var securityControlsView: some View {
        VStack(spacing: 0) {
            // Camera Selector Header
            HStack {
                Text("Select Camera:")
                    .font(.system(size: 12, weight: .semibold))

                Picker("", selection: $selectedCamID) {
                    ForEach(cameras) { cam in
                        Text(cam.name.isEmpty ? cam.ipAddress : cam.name).tag(cam.id as String?)
                    }
                }
                .frame(width: 200)

                Spacer()

                if isLoadingSecurity {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    refreshSecurity()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Status")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingSecurity || currentCamera == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04))

            Divider()

            if let cam = currentCamera {
                if let state = securityState {
                    Form {
                        // Section: Siren & Alarm Controls
                        Section {
                            Toggle(isOn: Binding(
                                get: { state.alarm.isEnabled },
                                set: { newVal in
                                    toggleAlarm(enabled: newVal)
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: "alarm.fill")
                                        .foregroundStyle(state.alarm.isEnabled ? Color.red : Color.gray)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Camera Alarm System")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(state.alarm.isEnabled ? "Alarm is ACTIVE (Triggers when detection occurs)" : "Alarm is OFF")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isSavingSecurity)

                            if state.alarm.isEnabled {
                                HStack(spacing: 24) {
                                    Toggle("Sound Siren", isOn: Binding(
                                        get: { state.alarm.soundEnabled },
                                        set: { toggleAlarmMode(sound: $0, light: state.alarm.lightEnabled) }
                                    ))

                                    Toggle("Light Strobe", isOn: Binding(
                                        get: { state.alarm.lightEnabled },
                                        set: { toggleAlarmMode(sound: state.alarm.soundEnabled, light: $0) }
                                    ))
                                }
                                .padding(.leading, 26)
                                .disabled(isSavingSecurity)
                            }
                        } header: {
                            Text("Tapo Camera Alarm")
                        } footer: {
                            Text("When triggered by person, motion or events, the camera sounds its siren and/or flashes spotlights.")
                                .font(.caption)
                        }

                        // Section: People & AI Detection Controls
                        Section {
                            ForEach(state.detections) { item in
                                if item.isSupported {
                                    HStack {
                                        Image(systemName: item.iconName)
                                            .frame(width: 20)
                                            .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 12, weight: .medium))
                                            if let sens = item.sensitivity {
                                                Text("Sensitivity: \(sens)")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Toggle("", isOn: Binding(
                                            get: { item.isEnabled },
                                            set: { newVal in
                                                toggleDetection(target: item.key, enabled: newVal)
                                            }
                                        ))
                                        .labelsHidden()
                                        .disabled(isSavingSecurity)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            Text("AI Detection Types")
                        } footer: {
                            Text("Features supported by your \(cam.name) hardware (Person, Motion, Vehicle, Tamper, Baby Crying, etc.). Changes apply directly to your Tapo account.")
                                .font(.caption)
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                } else if isLoadingSecurity {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading alarm & AI detection settings from camera...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Unable to read security settings")
                            .font(.headline)
                        Text("Ensure Tapo Cloud credentials in Camera Settings are correct and the camera is reachable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Retry Fetching") {
                            refreshSecurity()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Select a camera above to manage alarm and detection settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !securityFeedback.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(securityFeedback)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
            }
        }
        .onChange(of: selectedCamID) { _ in
            refreshSecurity()
        }
        .onAppear {
            if securityState == nil {
                refreshSecurity()
            }
        }
    }

    private func refreshSecurity() {
        guard let cam = currentCamera else { return }
        isLoadingSecurity = true
        securityFeedback = ""

        Task {
            let state = await TapoCameraService.shared.fetchSecurityState(camera: cam)
            await MainActor.run {
                self.securityState = state
                self.isLoadingSecurity = false
            }
        }
    }

    private func toggleAlarm(enabled: Bool) {
        guard let cam = currentCamera, var state = securityState else { return }
        isSavingSecurity = true
        state.alarm.isEnabled = enabled
        self.securityState = state

        Task {
            let ok = await TapoCameraService.shared.setAlarm(
                camera: cam,
                enabled: enabled,
                soundEnabled: state.alarm.soundEnabled,
                lightEnabled: state.alarm.lightEnabled
            )
            await MainActor.run {
                self.isSavingSecurity = false
                if ok {
                    self.securityFeedback = "Alarm updated: \(enabled ? "ON" : "OFF")"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.securityFeedback = "" }
                } else {
                    refreshSecurity()
                }
            }
        }
    }

    private func toggleAlarmMode(sound: Bool, light: Bool) {
        guard let cam = currentCamera, var state = securityState else { return }
        isSavingSecurity = true
        state.alarm.soundEnabled = sound
        state.alarm.lightEnabled = light
        self.securityState = state

        Task {
            let ok = await TapoCameraService.shared.setAlarm(
                camera: cam,
                enabled: state.alarm.isEnabled,
                soundEnabled: sound,
                lightEnabled: light
            )
            await MainActor.run {
                self.isSavingSecurity = false
                if ok {
                    self.securityFeedback = "Alarm mode updated"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.securityFeedback = "" }
                } else {
                    refreshSecurity()
                }
            }
        }
    }

    private func toggleDetection(target: String, enabled: Bool) {
        guard let cam = currentCamera, var state = securityState else { return }
        isSavingSecurity = true
        if let idx = state.detections.firstIndex(where: { $0.key == target }) {
            state.detections[idx].isEnabled = enabled
            self.securityState = state
        }

        Task {
            let ok = await TapoCameraService.shared.setDetection(
                camera: cam,
                target: target,
                enabled: enabled
            )
            await MainActor.run {
                self.isSavingSecurity = false
                if ok {
                    self.securityFeedback = "\(target.capitalized) detection updated: \(enabled ? "ON" : "OFF")"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.securityFeedback = "" }
                } else {
                    refreshSecurity()
                }
            }
        }
    }

    // MARK: - Hotkeys Tab
    private var hotkeySettingsView: some View {
        Form {
            Section("Quick-Peek Trigger Key") {
                Picker("Trigger Key", selection: $hotkeyCode) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }

                Picker("Modifier Key Requirement", selection: $hotkeyModifier) {
                    ForEach(ModifierChoice.allCases) { mod in
                        Text(mod.rawValue).tag(mod.rawValue)
                    }
                }

                Picker("Trigger Behavior", selection: $hotkeyMode) {
                    Text("Hold-to-Solid (peek while held, transparent on release)").tag("hold")
                    Text("Toggle (press once for solid, press again for ghost)").tag("toggle")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Global System Access") {
                Text("Hotkeys are registered globally across macOS so you can peek or bring your camera to the top from inside games, code editors, full-screen apps, or browsers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - UI & Transparency Tab
    private var uiCustomizationView: some View {
        Form {
            Section("Liquid Glass Styling") {
                Toggle("Liquid Glass Floating Header", isOn: $glassHeader)
                Toggle("Liquid Glass Floating Footer", isOn: $glassFooter)
                Toggle("Glass Menu Bar Transparency Effect", isOn: $glassMenuBar)
            }

            Section("Ghost Mode Defaults") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default Ghost Opacity")
                        Spacer()
                        Text("\(Int(defaultGhostAlpha * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $defaultGhostAlpha, in: 0.10...0.90, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Video Contrast & Edge Clarity Boost")
                        Spacer()
                        Text(String(format: "%.2fx", contrastBoost))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $contrastBoost, in: 1.0...1.6, step: 0.05)
                    Text("Enhances visual clarity so text under the window remains legible while the camera outlines stay sharp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addNewCamera() {
        let newCam = TapoCameraConfig(
            name: "Tapo Cam \(cameras.count + 1)",
            ipAddress: ""
        )
        cameras.append(newCam)
        selectedCamID = newCam.id
        loadSelectedCam(newCam.id)
        onSave()
    }

    private func deleteCamera(at offsets: IndexSet) {
        cameras.remove(atOffsets: offsets)
        selectedCamID = cameras.first?.id
        loadSelectedCam(selectedCamID)
        onSave()
    }

    private func loadSelectedCam(_ id: String?) {
        guard let id = id, let cam = cameras.first(where: { $0.id == id }) else { return }
        name = cam.name
        ipAddress = cam.ipAddress
        port = cam.port
        username = cam.username
        password = cam.password
        cloudPassword = cam.cloudPassword
        quality = cam.quality
        isEnabled = cam.isEnabled
        customRTSP = cam.customRTSPUrl ?? ""
    }

    private func applyChanges() {
        guard let id = selectedCamID, let idx = cameras.firstIndex(where: { $0.id == id }) else { return }
        cameras[idx].name = name
        cameras[idx].ipAddress = ipAddress
        cameras[idx].port = port
        cameras[idx].username = username
        cameras[idx].password = password
        cameras[idx].cloudPassword = cloudPassword
        cameras[idx].quality = quality
        cameras[idx].isEnabled = isEnabled
        cameras[idx].customRTSPUrl = customRTSP.isEmpty ? nil : customRTSP
        onSave()
        refreshSecurity()
    }
}
