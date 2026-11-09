import SwiftUI

public enum GridMode: Int, CaseIterable {
    case single = 1
    case dual = 2
    case quad = 4

    public var title: String {
        switch self {
        case .single: return "1 Cam"
        case .dual: return "2 Cams"
        case .quad: return "4 Cams"
        }
    }
}

public struct MainFloatingViewer: View {
    @Binding public var cameras: [TapoCameraConfig]
    public let onOpenSettings: () -> Void

    @State private var gridMode: GridMode = .single
    @State private var selectedCameraForRecordings: TapoCameraConfig?
    @State private var isRecordingsPresented: Bool = false
    @State private var windowOpacity: Double = 1.0
    @State private var isPinned: Bool = true
    @State private var activeCameraIndex: Int = 0
    @State private var isAlarmActive: Bool = false
    @State private var isAlarmUpdating: Bool = false

    private var activeCameras: [TapoCameraConfig] {
        cameras.filter { $0.isEnabled }.sorted { $0.cameraNumber < $1.cameraNumber }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Liquid Glass Header Bar
            HStack(spacing: 8) {
                // Tapo Brand Capsule
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.85, blue: 0.95))
                        .frame(width: 7, height: 7)
                        .shadow(color: Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.8), radius: 3)
                    Text("TAPO")
                        .font(.system(size: 10.5, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                )

                // Grid Switcher Liquid Glass Pill
                Picker("", selection: $gridMode) {
                    ForEach(GridMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 175)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )

                // Quick Camera Number Switcher for Single View
                if gridMode == .single && activeCameras.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(Array(activeCameras.enumerated()), id: \.element.id) { index, cam in
                            Button {
                                activeCameraIndex = index
                            } label: {
                                Text("Cam \(cam.cameraNumber)")
                                    .font(.system(size: 10, weight: activeCameraIndex == index ? .heavy : .semibold))
                                    .foregroundStyle(activeCameraIndex == index ? Color(red: 0.0, green: 0.85, blue: 0.95) : Color.white.opacity(0.7))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(
                                        Capsule()
                                            .fill(activeCameraIndex == index ? Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.25) : Color.white.opacity(0.06))
                                            .overlay(
                                                Capsule()
                                                    .stroke(activeCameraIndex == index ? Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.5) : Color.white.opacity(0.1), lineWidth: 0.8)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Capsule().fill(.ultraThinMaterial))
                }

                Spacer()

                // Timeline / SD Card Recordings Glass Button
                Button {
                    if let cam = activeCameras.indices.contains(activeCameraIndex) ? activeCameras[activeCameraIndex] : activeCameras.first {
                        selectedCameraForRecordings = cam
                        isRecordingsPresented = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 10))
                        Text("Recordings")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                .disabled(activeCameras.isEmpty)
                .help("Browse & scrub SD card recordings timeline")

                // Quick Alarm Arm/Disarm Toggle Button
                Button {
                    toggleQuickAlarm()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isAlarmActive ? "alarm.fill" : "alarm")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isAlarmActive ? Color.red : Color.white.opacity(0.8))
                        Text(isAlarmActive ? "ARMED" : "ALARM")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(isAlarmActive ? Color.red : Color.white.opacity(0.8))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isAlarmActive ? Color.red.opacity(0.25) : Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(isAlarmActive ? Color.red.opacity(0.6) : Color.white.opacity(0.18), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                .disabled(activeCameras.isEmpty || isAlarmUpdating)
                .help("Arm or Disarm camera siren alarm in Tapo account")

                // Ghost Mode Transparency Menu (Down to 10% ultra-ghost)
                Menu {
                    Text("Ghost Mode Transparency")
                    Slider(value: $windowOpacity, in: 0.10...1.0)
                        .onChange(of: windowOpacity) { val in
                            applyWindowAlpha(val)
                        }
                    Divider()
                    Button("10% Ultra Ghost") { applyWindowAlpha(0.10) }
                    Button("25% Ghost") { applyWindowAlpha(0.25) }
                    Button("50% Semi-Transparent") { applyWindowAlpha(0.50) }
                    Button("75% Soft") { applyWindowAlpha(0.75) }
                    Button("100% Solid") { applyWindowAlpha(1.0) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 0.95))
                        Text("\(Int(windowOpacity * 100))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ghost Mode: Make camera feed ultra transparent to see through your windows")

                // Pin Always on Top Toggle
                Button {
                    isPinned.toggle()
                    if let win = NSApp.keyWindow {
                        win.level = isPinned ? .floating : .normal
                    }
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isPinned ? Color(red: 0.0, green: 0.85, blue: 0.95) : Color.white.opacity(0.6))
                        .padding(5)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle Always On Top")

                // Settings
                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(5)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                        )
                }
                .buttonStyle(.plain)
                .help("Camera & Network Settings")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Color.white.opacity(0.12)),
                        alignment: .bottom
                    )
            )

            // Camera Viewport Grid
            ZStack {
                Color.black.opacity(0.92)

                if activeCameras.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Active Tapo Cameras")
                            .font(.headline)
                        Text("Click Settings (⚙) to configure camera IP and credentials.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Camera Setup") {
                            onOpenSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else {
                    cameraGridLayout
                }
            }

            // Liquid Glass Footer Bar
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.green.opacity(0.8), radius: 3)
                    Text("LIVE FEED")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.ultraThinMaterial))

                Spacer()

                if let cam = activeCameras.indices.contains(activeCameraIndex) ? activeCameras[activeCameraIndex] : activeCameras.first {
                    Text("Cam \(cam.cameraNumber) • \(cam.name) (\(cam.ipAddress))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Color.white.opacity(0.12)),
                        alignment: .top
                    )
            )
        }
        .frame(minWidth: 460, minHeight: 330)
        .opacity(windowOpacity)
        .sheet(isPresented: $isRecordingsPresented) {
            if let cam = selectedCameraForRecordings {
                VStack(spacing: 0) {
                    HStack {
                        Text("Recordings Timeline: Cam \(cam.cameraNumber) (\(cam.name))")
                            .font(.headline)
                        Spacer()
                        Button("Done") {
                            isRecordingsPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)

                    Divider()

                    TapoRecordingsTimelineView(camera: cam)
                }
                .frame(width: 580, height: 560)
            }
        }
        .onAppear {
            checkCurrentAlarmStatus()
        }
    }

    private func checkCurrentAlarmStatus() {
        guard let cam = activeCameras.indices.contains(activeCameraIndex) ? activeCameras[activeCameraIndex] : activeCameras.first else { return }
        Task {
            if let state = await TapoCameraService.shared.fetchSecurityState(camera: cam) {
                await MainActor.run {
                    self.isAlarmActive = state.alarm.isEnabled
                }
            }
        }
    }

    private func toggleQuickAlarm() {
        guard let cam = activeCameras.indices.contains(activeCameraIndex) ? activeCameras[activeCameraIndex] : activeCameras.first else { return }
        isAlarmUpdating = true
        let targetState = !isAlarmActive
        isAlarmActive = targetState

        Task {
            let ok = await TapoCameraService.shared.setAlarm(
                camera: cam,
                enabled: targetState,
                soundEnabled: true,
                lightEnabled: true
            )
            await MainActor.run {
                self.isAlarmUpdating = false
                if !ok {
                    self.isAlarmActive = !targetState
                }
            }
        }
    }

    @ViewBuilder
    private var cameraGridLayout: some View {
        switch gridMode {
        case .single:
            let cam = activeCameras.indices.contains(activeCameraIndex) ? activeCameras[activeCameraIndex] : activeCameras[0]
            CameraViewportCell(camera: cam, isSelected: true) {
                // already selected
            }

        case .dual:
            VStack(spacing: 2) {
                ForEach(0..<min(2, activeCameras.count), id: \.self) { i in
                    CameraViewportCell(camera: activeCameras[i], isSelected: activeCameraIndex == i) {
                        activeCameraIndex = i
                    }
                }
            }

        case .quad:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    if activeCameras.indices.contains(0) {
                        CameraViewportCell(camera: activeCameras[0], isSelected: activeCameraIndex == 0) { activeCameraIndex = 0 }
                    }
                    if activeCameras.indices.contains(1) {
                        CameraViewportCell(camera: activeCameras[1], isSelected: activeCameraIndex == 1) { activeCameraIndex = 1 }
                    } else { emptyCell }
                }
                HStack(spacing: 2) {
                    if activeCameras.indices.contains(2) {
                        CameraViewportCell(camera: activeCameras[2], isSelected: activeCameraIndex == 2) { activeCameraIndex = 2 }
                    } else { emptyCell }
                    if activeCameras.indices.contains(3) {
                        CameraViewportCell(camera: activeCameras[3], isSelected: activeCameraIndex == 3) { activeCameraIndex = 3 }
                    } else { emptyCell }
                }
            }
        }
    }

    private func applyWindowAlpha(_ val: Double) {
        windowOpacity = val
        if let win = NSApp.windows.first(where: { $0.title == "Tapo Cam Viewer" || $0.level == .floating }) {
            win.alphaValue = CGFloat(val)
        }
    }

    private var emptyCell: some View {
        ZStack {
            Color.black.opacity(0.5)
            Text("Empty Slot")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A resilient, self-healing camera cell with watchdog stall detection and a large Resume button
public struct CameraViewportCell: View {
    public let camera: TapoCameraConfig
    public let isSelected: Bool
    public let onSelect: () -> Void

    @State private var streamState: TapoStreamState = .connecting
    @State private var reloadTrigger: UUID = UUID()
    @State private var isHovering: Bool = false

    public init(
        camera: TapoCameraConfig,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {}
    ) {
        self.camera = camera
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack(alignment: .center) {
            // Live WebRTC Video Player
            TapoWebRTCPlayerView(
                streamURL: Go2rtcServerManager.shared.webRTCStreamURL(for: camera.id),
                cameraName: camera.name,
                reloadTrigger: reloadTrigger,
                streamState: $streamState
            )

            // When stream is stalled or disconnected, show the Large Resume Button
            if streamState.isStalledOrDisconnected {
                Color.black.opacity(0.80)
                    .transition(.opacity)

                Button {
                    reloadStream()
                } label: {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.18))
                                .frame(width: 68, height: 68)
                            Circle()
                                .stroke(Color(red: 0.0, green: 0.85, blue: 0.95).opacity(0.85), lineWidth: 2)
                                .frame(width: 68, height: 68)
                            Image(systemName: "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 0.95))
                                .offset(x: 2.5)
                        }

                        VStack(spacing: 4) {
                            Text("Live Stream Paused")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Click to Resume Cam \(camera.cameraNumber)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.65), radius: 14, y: 5)
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Connecting Spinner
            if streamState == .connecting {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Connecting live feed...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
                .transition(.opacity)
            }

            // Top-left Camera HUD Pill (Camera Number, Name, Live Dot & Quick Refresh)
            VStack {
                HStack(alignment: .top) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6.5, height: 6.5)
                            .shadow(color: statusColor.opacity(0.8), radius: 3)

                        // Camera Number Badge
                        Text("Cam \(camera.cameraNumber)")
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 0.95))

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))

                        // Camera Name
                        Text(camera.name.isEmpty ? "Unnamed" : camera.name)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)

                        // Quick Refresh Button
                        Button {
                            reloadStream()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Refresh live stream")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    )

                    Spacer()
                }
                .padding(8)

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            onSelect()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapoStreamsNeedReload)) { _ in
            reloadStream()
        }
    }

    private var statusColor: Color {
        switch streamState {
        case .playing: return .green
        case .connecting: return .yellow
        case .stalled, .disconnected: return .red
        }
    }

    private func reloadStream() {
        withAnimation(.easeInOut(duration: 0.2)) {
            streamState = .connecting
            reloadTrigger = UUID()
        }
        Task { @MainActor in
            if !Go2rtcServerManager.shared.isRunning {
                Go2rtcServerManager.shared.start(cameras: [camera])
            }
        }
    }
}
