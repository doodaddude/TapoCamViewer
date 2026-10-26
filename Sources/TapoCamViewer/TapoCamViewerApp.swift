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

/// Custom NSPanel for the floating camera HUD.
/// We override close/performClose to hide (orderOut) instead of actually closing,
/// preventing the window from being released while we hold a strong ref in the controller.
final class TapoFloatingWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        // Never release on close — we manage lifetime via NSWindowController
        self.isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performClose(_ sender: Any?) {
        // Hide, don't close/release
        self.orderOut(nil)
    }

    override func close() {
        // Hide, don't close/release
        self.orderOut(nil)
    }

    deinit {
        NSLog("⚠️ TapoFloatingWindow deinit — window was deallocated!")
    }
}

/// NSWindowController subclass that owns the floating camera HUD window.
/// AppKit keeps the window alive as long as the controller is alive — this is the
/// canonical way to keep programmatically-created windows from being deallocated.
final class FloatingWindowController: NSWindowController {
    deinit {
        NSLog("ℹ️ FloatingWindowController deinit")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    /// Strong reference to the window controller keeps the panel alive indefinitely.
    private var floatingWindowController: FloatingWindowController?
    /// Convenience accessor — non-nil whenever the controller exists.
    private var floatingWindow: TapoFloatingWindow? { floatingWindowController?.window as? TapoFloatingWindow }
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
        let panel = TapoFloatingWindow(
            contentRect: NSRect(x: 100, y: 100, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tapo Cam Viewer"
        panel.delegate = self

        let binding = Binding<[TapoCameraConfig]>(
            get: { self.cameras },
            set: { self.cameras = $0; self.saveCameras() }
        )

        let root = MainFloatingViewer(cameras: binding, onOpenSettings: { [weak self] in
            self?.openSettingsWindow()
        })
        panel.contentView = NSHostingView(rootView: root)
        panel.center()

        // Create the controller — it retains the panel strongly.
        let wc = FloatingWindowController(window: panel)
        self.floatingWindowController = wc

        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleFloatingWindow() {
        guard let wc = floatingWindowController, let w = wc.window else {
            // No controller yet (first launch) — create everything.
            setupFloatingWindow()
            return
        }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            wc.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettingsWindow() {
        if let existing = settingsWindow {
            positionSettingsWindow(existing)
            existing.level = .floating
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
        window.level = .floating // Float on top of the camera HUD!
        window.isReleasedWhenClosed = false
        window.delegate = self

        positionSettingsWindow(window)

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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    private func positionSettingsWindow(_ window: NSWindow) {
        if let camWin = floatingWindow, camWin.isVisible {
            let camFrame = camWin.frame
            let screen = camWin.screen ?? NSScreen.main
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let winWidth: CGFloat = 640
            let winHeight: CGFloat = 530

            // Position beside camera window (to the right if space permits, else to the left)
            var targetX = camFrame.maxX + 14
            var targetY = camFrame.maxY - winHeight

            if targetX + winWidth > screenFrame.maxX {
                targetX = camFrame.minX - winWidth - 14
            }
            if targetX < screenFrame.minX {
                targetX = screenFrame.midX - (winWidth / 2)
                targetY = screenFrame.midY - (winHeight / 2)
            }
            window.setFrameOrigin(NSPoint(x: targetX, y: max(screenFrame.minY, min(targetY, screenFrame.maxY - winHeight))))
        } else {
            window.center()
        }
    }

    // MARK: - NSWindowDelegate

    /// Called by AppKit before a window closes. Returning false prevents the close.
    /// NOTE: NSWindowDelegate declares this as `(_ sender: NSWindow) -> Bool` — do NOT
    /// change the type to `Any`; that creates a different method that Swift never bridges
    /// to the delegate protocol.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === floatingWindow {
            // Intercept: hide instead of close so the window is never released.
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Only nil out settingsWindow when it actually closes (we allow that).
        if let win = notification.object as? NSWindow, win === settingsWindow {
            settingsWindow = nil
        }
        // Do NOT nil floatingWindowController here — the floating window should never
        // reach windowWillClose because windowShouldClose intercepts it above.
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
