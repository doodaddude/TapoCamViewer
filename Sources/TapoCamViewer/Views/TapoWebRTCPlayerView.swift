import SwiftUI
import WebKit

/// High-performance WebRTC player with watchdog stall detection,
/// automatic recovery, high-contrast edge enhancement, and zero background opacity.
public struct TapoWebRTCPlayerView: NSViewRepresentable {
    public let streamURL: URL?
    public let cameraName: String
    public var reloadTrigger: UUID
    @Binding public var streamState: TapoStreamState

    public init(
        streamURL: URL?,
        cameraName: String,
        reloadTrigger: UUID = UUID(),
        streamState: Binding<TapoStreamState> = .constant(.connecting)
    ) {
        self.streamURL = streamURL
        self.cameraName = cameraName
        self.reloadTrigger = reloadTrigger
        self._streamState = streamState
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false

        // Register script message handler to receive stream health events
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "tapoStreamStatus")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.parent = self
        context.coordinator.currentReloadTrigger = reloadTrigger

        if let url = streamURL {
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
            webView.load(req)
        }

        return webView
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "tapoStreamStatus")
        nsView.stopLoading()
        nsView.navigationDelegate = nil
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TapoWebRTCPlayerView
        var currentReloadTrigger: UUID = UUID()

        init(_ parent: TapoWebRTCPlayerView) {
            self.parent = parent
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "tapoStreamStatus",
                  let dict = message.body as? [String: Any],
                  let state = dict["state"] as? String else { return }

            let reason = (dict["reason"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch state {
                case "playing":
                    self.parent.streamState = .playing
                case "stalled":
                    self.parent.streamState = .stalled(reason: reason)
                case "disconnected":
                    self.parent.streamState = .disconnected(reason: reason)
                default:
                    break
                }
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 1. Inject CSS for liquid sharp edge enhancement, transparent backgrounds, and smooth containment
            // 2. Inject JS Watchdog to monitor video element play/stall/pause events and report status
            let js = """
            (function() {
                if (!document.getElementById('tapo-custom-styles')) {
                    var style = document.createElement('style');
                    style.id = 'tapo-custom-styles';
                    style.innerHTML = `
                        html, body {
                            background: transparent !important;
                            margin: 0 !important;
                            padding: 0 !important;
                            overflow: hidden !important;
                        }
                        video {
                            background: transparent !important;
                            object-fit: contain !important;
                            filter: contrast(1.15) saturate(1.2) brightness(1.05) drop-shadow(0 0 1px rgba(0,0,0,0.8));
                        }
                    `;
                    document.head.appendChild(style);
                }

                // Setup Stream Health Watchdog
                if (!window._tapoWatchdogInstalled) {
                    window._tapoWatchdogInstalled = true;

                    function notify(state, reason) {
                        try {
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tapoStreamStatus) {
                                window.webkit.messageHandlers.tapoStreamStatus.postMessage({ state: state, reason: reason || '' });
                            }
                        } catch(e) {}
                    }

                    var lastTime = -1;
                    var frozenTicks = 0;
                    var initialTicks = 0;
                    var hasPlayed = false;

                    function hookVideo(video) {
                        if (video._tapoHooked) return;
                        video._tapoHooked = true;

                        video.addEventListener('playing', function() {
                            hasPlayed = true;
                            frozenTicks = 0;
                            notify('playing', 'video playing');
                        });

                        video.addEventListener('pause', function() {
                            if (!video.seeking && !video.ended) {
                                notify('stalled', 'video paused');
                            }
                        });

                        video.addEventListener('ended', function() {
                            notify('stalled', 'stream ended');
                        });

                        video.addEventListener('error', function(e) {
                            notify('disconnected', 'video error');
                        });
                    }

                    setInterval(function() {
                        var video = document.querySelector('video');
                        if (!video) {
                            var streamEl = document.querySelector('video-stream');
                            if (streamEl && streamEl.video) {
                                video = streamEl.video;
                            }
                        }

                        if (!video) {
                            initialTicks++;
                            if (initialTicks > 8) {
                                notify('disconnected', 'player initialization timeout');
                            }
                            return;
                        }

                        hookVideo(video);

                        if (video.ended) {
                            notify('stalled', 'video ended');
                            return;
                        }

                        if (video.paused && !video.seeking) {
                            frozenTicks++;
                            if (frozenTicks >= 2) {
                                notify('stalled', 'stream paused');
                            }
                            return;
                        }

                        if (video.readyState >= 2 && video.currentTime > 0) {
                            if (video.currentTime === lastTime) {
                                frozenTicks++;
                                if (frozenTicks >= 4) {
                                    notify('stalled', 'frame frozen');
                                }
                            } else {
                                lastTime = video.currentTime;
                                frozenTicks = 0;
                                if (!hasPlayed) {
                                    hasPlayed = true;
                                }
                                notify('playing', 'active playback');
                            }
                        } else if (!hasPlayed) {
                            initialTicks++;
                            if (initialTicks > 12) {
                                notify('disconnected', 'waiting for video stream timeout');
                            }
                        } else {
                            frozenTicks++;
                            if (frozenTicks >= 4) {
                                notify('stalled', 'insufficient video data');
                            }
                        }
                    }, 1000);
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.streamState = .disconnected(reason: error.localizedDescription)
            }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.streamState = .disconnected(reason: error.localizedDescription)
            }
        }
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        guard let url = streamURL else {
            let html = """
            <html>
            <body style="background:transparent; color:#607282; font-family:-apple-system; display:flex; align-items:center; justify-content:center; height:100vh; margin:0; flex-direction:column;">
                <div style="font-size:32px; margin-bottom:8px;">📹</div>
                <div style="font-size:13px; font-weight:600; color:white;">No Stream Active</div>
                <div style="font-size:10px; margin-top:4px; color:#888;">Configure Camera in Settings</div>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        // Check if a manual or automatic reload was triggered
        let needsTriggerReload = context.coordinator.currentReloadTrigger != reloadTrigger
        let urlChanged = webView.url?.path != url.path || (webView.url?.query?.components(separatedBy: "&_ts=").first != url.query?.components(separatedBy: "&_ts=").first)

        if needsTriggerReload || urlChanged {
            context.coordinator.currentReloadTrigger = reloadTrigger
            DispatchQueue.main.async {
                self.streamState = .connecting
            }

            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            queryItems.removeAll(where: { $0.name == "_ts" })
            queryItems.append(URLQueryItem(name: "_ts", value: "\(Int(Date().timeIntervalSince1970))"))
            components?.queryItems = queryItems

            let targetURL = components?.url ?? url
            let req = URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
            webView.load(req)
        }
    }
}
