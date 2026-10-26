import SwiftUI
import WebKit

/// High-performance WebRTC player with high-contrast edge enhancement and zero background opacity
public struct TapoWebRTCPlayerView: NSViewRepresentable {
    public let streamURL: URL?
    public let cameraName: String

    public init(streamURL: URL?, cameraName: String) {
        self.streamURL = streamURL
        self.cameraName = cameraName
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, WKNavigationDelegate {
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject CSS to sharpen video, boost contrast & color saturation, and strip black background bars
            let js = """
            (function() {
                var style = document.createElement('style');
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
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
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

        if webView.url != url {
            let req = URLRequest(url: url)
            webView.load(req)
        }
    }
}
