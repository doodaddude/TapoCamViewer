# 📹 TapoCamViewer for macOS

<p align="center">
  <img src="Resources/AppIcon.icns" alt="TapoCamViewer Icon" width="128" height="128" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.3);" />
</p>

<p align="center">
  <strong>A high-performance, ultra-low-latency floating and menu bar camera viewer engineered natively for macOS.</strong><br>
  Stream, monitor, and configure TP-Link Tapo smart cameras with an ultra-thin <em>Liquid Glass</em> HUD, sub-second WebRTC playback, global quick-peek hotkeys, and hardware controls synced to your Tapo account.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?style=flat-square&logo=apple" alt="macOS 13.0+" />
  <img src="https://img.shields.io/badge/Swift-5.9%20%2F%206.0-F05138?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Signed-Developer%20ID-green?style=flat-square&logo=apple" alt="Developer ID Signed" />
  <img src="https://img.shields.io/badge/Engine-go2rtc%20WebRTC-00ADD8?style=flat-square" alt="go2rtc Engine" />
  <img src="https://img.shields.io/badge/License-MIT-purple?style=flat-square" alt="License MIT" />
</p>

---

## ✨ Highlights & Features

### 1. ⚡ Ultra-Low-Latency WebRTC Streaming
- **Sub-Second Real-Time Feeds**: Powered by an embedded, self-managed `go2rtc` daemon that seamlessly transcodes camera RTSP streams into ultra-low-latency WebRTC.
- **Adaptive Multi-Cam Layouts**: View single streams or multi-camera grids (1-cam, 2-cam, and 4-cam quad layouts) with independent stream quality selection (`stream1` 2K/1080p vs. `stream2` 360p Fluid).
- **Embedded WebRTC Player**: Hardware-accelerated video rendering with automatic reconnection and zero configuration overhead.

### 2. 💎 "Liquid Glass" macOS Aesthetic & Ghost Mode
- **macOS Sequoia & Sonoma Glass**: Designed with native `Material.ultraThinMaterial`, vibrant translucency, specular border reflections, and soft dynamic shadows.
- **Ghost Mode Transparency**: Float camera feeds directly over your IDE, browser, or creative workspace with customizable opacity ranging from **10% to 100%**.
- **Contrast Boosting**: Enhances stream readability even when hovering transparently over bright wallpapers or code editors.

### 3. ⌨️ Global Quick-Peek Hotkeys
- **Instant Workspace Access**: Summon or inspect your camera feeds from any active display or full-screen space with customizable system-wide hotkeys (e.g. `F1`, `Tilde`, `Option+Space`).
- **Dual Activation Modes**:
  - **Hold-to-Solid**: Keep feeds transparent in the background, instantly snap to 100% solid opacity on keypress, and return on release.
  - **Toggle Peek**: Tap to reveal the viewer; tap again to dismiss.

### 4. 🚨 Tapo Account Alarm & Siren Orchestration
- **Quick-Arm Pill**: One-click **ALARM / ARMED** toggle directly in the floating viewer header bar.
- **Hardware Siren & Strobe Controls**: Live bi-directional sync with the camera's internal alarm hardware, controlling siren audio, sound mode, and spotlight flashes via the official Tapo Cloud session protocol.

### 5. 🧠 Smart AI Detections & Sensitivity Configuration
- Live query and toggle for hardware-supported AI features:
  - 🚶 **Person Detection**
  - 🏃 **Motion Detection**
  - 🚗 **Vehicle Detection**
  - 🐾 **Pet Detection**
  - 🛡️ **Camera Tampering Alert**
  - 👶 **Baby Crying Detection**
  - 🔊 **Audio Detections** (*Bark, Meow, Glass Break*)
- Adjust digital sensitivity sliders synced directly to the camera firmware.

### 6. 🎞️ SD Card Recordings Timeline & Event Classification
- **AI Event Tagging**: Unlike traditional players that mark every recording as generic "motion", TapoCamViewer correlates recordings with camera AI telemetry to categorize clips:
  - 🚶 **Person** (Purple)
  - 🚨 **Area Intrusion** (Red)
  - ↔️ **Line Crossing** (Cyan)
  - 📡 **Motion** (Orange)
  - 🎞️ **Continuous** (Gray)
- **Interactive Scrubber**: Timeline seek bar, duration indicators, and one-click export to `~/Movies/TapoRecordings/`.
- **Event Filter Chips**: Instantly filter clips by event type with live count pills (e.g., `Person (24)`, `Area Intrusion (89)`).

---

## ⚠️ Important Disclaimer: SD Card Recording Playback

> [!WARNING]
> **SD Card Recording Playback is Experimental**
>
> While the SD card timeline reliably browses recorded timestamps, metadata, and AI detection classifications, **direct playback and downloading of past clips from the onboard SD card is currently experimental and may not be consistent across all TP-Link firmware revisions**.
>
> Tapo cameras utilize an encrypted proprietary session protocol (`sdvod` / `mediaSession` over port 8800) with digest authentication that TP-Link alters between firmware updates and camera hardware versions.
>
> We are actively improving SD card playback consistency. For mission-critical security reviews of historical footage, please utilize the official TP-Link Tapo mobile application.

---

## 🔒 Security & Privacy Architecture

TapoCamViewer is engineered with a strict **Local-First, Zero-Leakage** philosophy:

```
┌─────────────────────────────────────────────────────────────┐
│                       macOS Sandbox                         │
│                                                             │
│   ┌─────────────────────┐       ┌───────────────────────┐   │
│   │ TapoCamViewer (App) │       │ go2rtc Engine (Local) │   │
│   │ - Floating HUD      │       │ - RTSP to WebRTC      │   │
│   │ - Glass Controls    │◄─────►│ - Port 1984 / 8555    │   │
│   │ - Local Config DB   │       │ - Loopback only       │   │
│   └──────────┬──────────┘       └───────────▲───────────┘   │
│              │ (Encrypted stdin)            │               │
│              ▼                              │               │
│   ┌─────────────────────┐                   │               │
│   │ Python Bridge       │                   │               │
│   │ - pytapo transport  │                   │               │
│   └──────────┬──────────┘                   │               │
└──────────────┼──────────────────────────────┼───────────────┘
               │ Local LAN                    │ Local RTSP (554)
               ▼                              ▼
      ┌────────────────────────────────────────────────┐
      │             Tapo Camera Hardware               │
      │  - RTSP Live Stream (Stream1 / Stream2)        │
      │  - Onvif / KLAP / HTTP Control API             │
      │  - MicroSD Card Storage                        │
      └────────────────────────────────────────────────┘
```

- **Zero Cloud Exposure**: Video streaming happens strictly across your local home network (LAN). No video data is ever routed through external third-party servers.
- **Secure Credential Handling**: Local credentials and cloud tokens are stored solely in your macOS user profile (`UserDefaults`) and passed dynamically through encrypted standard input (`stdin`) to worker scripts. Credentials are never written to disk, passed via shell arguments, or committed to version control.
- **Developer ID Signed**: Signed with an Apple Developer ID certificate and configured with strict macOS entitlements.

---

## 🏗️ Project Structure

```
TapoCamViewer/
├── Package.swift                     # Swift Package Manager configuration
├── entitlements.plist                # App sandbox & network security entitlements
├── scripts/
│   └── build_app.sh                  # Release compilation & Developer ID signing
├── bin/
│   └── go2rtc                        # Embedded streaming gateway binary
├── Resources/
│   └── AppIcon.icns                  # macOS Squircle application icon
└── Sources/
    └── TapoCamViewer/
        ├── TapoCamViewerApp.swift    # App entry point, AppDelegate & status bar item
        ├── Models/
        │   └── TapoModels.swift      # Camera config, alarm, detection & clip models
        ├── Controllers/
        ├── Services/
        │   ├── Go2rtcServerManager.swift    # Lifecycle management for go2rtc engine
        │   ├── TapoCameraService.swift      # Native Swift bridge for camera controls
        │   └── TapoRecordingBridge.py       # Python driver for Tapo API & event decoding
        └── Views/
            ├── MainFloatingViewer.swift     # Glass HUD, multi-cam grid, alarm toggle
            ├── TapoWebRTCPlayerView.swift   # WebRTC hardware-accelerated video view
            ├── TapoRecordingsTimelineView.swift # SD recordings timeline & event filter
            └── TapoSettingsView.swift       # Camera config & AI detection controls
```

---

## 🚀 Installation & Setup

### Prerequisites

1. **macOS 13.0 (Ventura)** or later.
2. **Python 3** with the `pytapo` library installed:
   ```bash
   pip3 install pytapo
   ```
3. **Camera Account**:
   - In the TP-Link Tapo mobile app, go to:
     **Camera Settings ➔ Advanced Settings ➔ Camera Account**
   - Create a local username and password (used for RTSP/WebRTC streams).
4. **Cloud Account**:
   - Your primary TP-Link Tapo email and password (used for remote Alarm & AI Detection toggles).

---

### Building from Source

```bash
# 1. Clone the repository
git clone https://github.com/doodaddude/TapoCamViewer.git
cd TapoCamViewer

# 2. Build and sign the application bundle
./scripts/build_app.sh

# 3. Deploy to Applications folder
cp -R build/TapoCamViewer.app /Applications/

# 4. Launch TapoCamViewer
open /Applications/TapoCamViewer.app
```

---

## 🎮 Usage Guide

| Feature | How to Use |
| :--- | :--- |
| **Open HUD** | Click the camera icon in your macOS menu bar. |
| **Ghost Mode** | Adjust the transparency slider in the viewer header (down to 10%). |
| **Alarm Toggle** | Click the **ALARM / ARMED** pill in the floating header to arm or silence your camera. |
| **Browse SD Clips** | Click the SD card icon on any camera card to view the recordings timeline. |
| **Filter Events** | Click event chips (`Person`, `Area Intrusion`, etc.) to filter clips by detection type. |
| **Camera Settings** | Click the gear icon to configure cameras, set RTSP ports, or toggle AI detection rules. |

---

## 📄 License

This project is licensed under the **MIT License**. Created and maintained by **Dakota Hilchey**.
