# TapoCamViewer for macOS

A sleek, ultra-low-latency floating and menu bar camera viewer designed natively for macOS to stream and manage TP-Link Tapo smart security cameras.

Featuring an ultra-thin **Liquid Glass** aesthetic, zero-latency WebRTC live playback powered by an embedded `go2rtc` streaming engine, customizable **Ghost Mode** transparency (down to 10%), global quick-peek hotkeys, and hardware controls directly synced with your Tapo account.

---

## ✨ Features

- **Ultra-Low Latency Live Streaming**: Sub-second WebRTC feed for your Tapo cameras (supports 1-cam, 2-cam, and 4-cam quad layouts).
- **Ghost Mode Transparency**: Float your camera feeds over IDEs, browsers, or games with custom transparency (10% to 100%) and contrast boosting.
- **Global Quick-Peek Hotkeys**: Configurable global hotkey (e.g. F1, Tilde) with Hold-to-Solid or Toggle modes to peek at your cameras from any workspace.
- **Tapo Account Alarm Control**:
  - One-click **ALARM / ARMED** toggle directly in the floating header.
  - Granular siren and spotlight strobe toggles synced live to your camera hardware.
- **AI Detection Toggles**:
  - Live query and toggle for hardware-supported detections: **Person**, **Motion**, **Vehicle**, **Tamper**, and sound detections (**Baby Crying**, **Bark**, **Glass Break**).
- **Zero Local Credential Leakage**:
  - All camera credentials and passwords are stored exclusively on your Mac in sandboxed `UserDefaults` and passed dynamically via encrypted standard input. No credentials or personal IPs are ever bundled or published.

---

## ⚠️ Disclaimer: SD Card Recordings & Playback

> [!WARNING]
> **Playback from SD Card is Experimental & In Development**
>
> While the SD card recordings timeline allows browsing recorded timestamps and motion events, **playback and downloading directly from camera SD storage is currently inconsistent and not guaranteed to work reliably on all firmware versions**.
>
> Tapo cameras utilize proprietary encrypted TLS transport sessions (`sdvod` / `mediaSession`) for SD card recordings playback that TP-Link frequently changes between firmware updates.
> 
> We are actively working to make playback fully reliable. In the meantime, please rely on the official Tapo mobile app for mission-critical video review of past recordings.

---

## 🛠 Prerequisites

- macOS 13.0 (Ventura) or later
- Python 3 with `pytapo`:
  ```bash
  pip3 install pytapo
  ```
- Tapo Camera configured on your local network:
  - Local Camera Account enabled in the Tapo App under *Camera Settings -> Advanced Settings -> Camera Account* (used for RTSP/WebRTC streaming).
  - Tapo Cloud account email and password (used for remote Alarm & AI Detection synchronization).

---

## 🚀 Building & Installing

Clone the repository and build the macOS release bundle:

```bash
git clone https://github.com/doodaddude/TapoCamViewer.git
cd TapoCamViewer

# Build and assemble TapoCamViewer.app
./scripts/build_app.sh
```

The completed app bundle will be generated at `build/TapoCamViewer.app`. Move it to `/Applications`:

```bash
cp -R build/TapoCamViewer.app /Applications/
```

---

## 🔒 Security & Privacy

TapoCamViewer runs completely locally on your machine.
- Direct local RTSP / WebRTC connections between your Mac and the camera.
- No third-party servers, telemetry, or analytics.
- Your credentials remain strictly inside your private macOS user account.

---

## 📄 License

MIT License. Designed and maintained by Dakota Hilchey.
