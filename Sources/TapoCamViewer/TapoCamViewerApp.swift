import SwiftUI
import AppKit

@main
struct TapoCamViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var floatingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    @AppStorage("tapo_cameras_json") private var savedCamerasJson: String = ""
    @AppStorage("tapo_hotkey_code") private var hotkeyCode: Int = 122 // Default F1
    @AppStorage("tapo_hotkey_modifier") private var hotkeyModifier: String = "None (Single Key)"
    @AppStorage("tapo_hotkey_mode") private var hotkeyMode: String = "hold"
    @AppStorage("tapo_ui_glass_menubar") private var glassMenuBar: Bool = false
    
    private var cameras: [TapoCameraConfig] = []
    
    // Quick-Peek Hold / Toggle State
    private var previousAlpha: CGFloat = 0.25
    private var isPeeking: Bool = false
    private var isToggledSolid: Bool = false
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Load AppIcon if available
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImg = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImg
        }
        
        loadCameras()

        setupStatusItem()
        setupFloatingWindow()
        setupHotkeys()

        Go2rtcServerManager.shared.start(cameras: cameras)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let lk = localKeyMonitor { NSEvent.removeMonitor(lk) }
        if let gk = globalKeyMonitor { NSEvent.removeMonitor(gk) }
        Go2rtcServerManager.shared.stop()
    }

    // MARK: - Hotkey / Modifier Configuration
    private func setupHotkeys() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func checkModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch hotkeyModifier {
        case "Command (⌘)":
            return flags.contains(.command)
        case "Control (⌃)":
            return flags.contains(.control)
        case "Option (⌥)":
            return flags.contains(.option)
        case "Shift (⇧)":
            return flags.contains(.shift)
        default:
            return true
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let targetKey = UInt16(hotkeyCode)
        guard event.keyCode == targetKey else { return }
        guard checkModifiers(event.modifierFlags) else { return }
        guard let window = floatingWindow else { return }

        if hotkeyMode == "toggle" {
            if event.type == .keyDown {
                isToggledSolid.toggle()
                if isToggledSolid {
                    previousAlpha = window.alphaValue
                    window.alphaValue = 1.0
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    window.alphaValue = previousAlpha
                }
            }
        } else {
            // Hold mode
            if event.type == .keyDown {
                if !isPeeking {
                    isPeeking = true
                    previousAlpha = window.alphaValue
                    window.alphaValue = 1.0
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else if event.type == .keyUp {
                if isPeeking {
                    isPeeking = false
                    window.alphaValue = previousAlpha
                }
            }
        }
    }

    // MARK: - Menu Bar Setup
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = createTapoMenuBarIcon()
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Tapo Cam Viewer", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Toggle Camera Window", action: #selector(toggleFloatingWindow), keyEquivalent: "t"))
            menu.addItem(NSMenuItem(title: "Preferences & Hotkeys...", action: #selector(openSettingsWindow), keyEquivalent: ","))
            menu.addItem(NSMenuItem(title: "Open Recordings Folder", action: #selector(openRecordingsFolder), keyEquivalent: "r"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit Tapo Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            DispatchQueue.main.async {
                self.statusItem?.menu = nil
            }
        } else {
            toggleFloatingWindow()
        }
    }

    // MARK: - Floating Cam Window
    private func setupFloatingWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tapo Cam Viewer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let binding = Binding<[TapoCameraConfig]>(
            get: { self.cameras },
            set: { self.cameras = $0; self.saveCameras() }
        )

        let root = MainFloatingViewer(cameras: binding, onOpenSettings: { [weak self] in
            self?.openSettingsWindow()
        })
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.floatingWindow = window
    }

    @objc private func toggleFloatingWindow() {
        guard let w = floatingWindow else {
            setupFloatingWindow()
            return
        }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettingsWindow() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 530),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tapo Camera Settings & Preferences"

        let binding = Binding<[TapoCameraConfig]>(
            get: { self.cameras },
            set: { self.cameras = $0; self.saveCameras() }
        )

        let settingsView = TapoSettingsView(cameras: binding, onSave: { [weak self] in
            guard let self = self else { return }
            self.saveCameras()
            Task { @MainActor in
                Go2rtcServerManager.shared.updateCameras(self.cameras)
            }
        })
        window.contentView = NSHostingView(rootView: settingsView)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win == settingsWindow {
            settingsWindow = nil
        }
    }

    @objc private func openRecordingsFolder() {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        let tapoDir = movies.appendingPathComponent("TapoRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: tapoDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(tapoDir)
    }

    private func loadCameras() {
        guard !savedCamerasJson.isEmpty,
              let data = savedCamerasJson.data(using: .utf8),
              let list = try? JSONDecoder().decode([TapoCameraConfig].self, from: data) else {
            cameras = []
            return
        }
        self.cameras = list
    }

    private func saveCameras() {
        if let data = try? JSONEncoder().encode(cameras),
           let str = String(data: data, encoding: .utf8) {
            savedCamerasJson = str
        }
    }

    private func createTapoMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
            NSColor.labelColor.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()

            let lens = NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8))
            NSColor.labelColor.setFill()
            lens.fill()

            let dot = NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 2.5, height: 2.5))
            NSColor.windowBackgroundColor.setFill()
            dot.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
