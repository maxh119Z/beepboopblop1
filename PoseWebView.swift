import SwiftUI
import WebKit

struct PoseWebView: UIViewRepresentable {
    let url: URL
    var onLandmarks: ([PosePoint]) -> Void
    var onCnnProb: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Let the web page use camera/mic without popping extra restrictions
        config.mediaTypesRequiringUserActionForPlayback = []

        // JS -> native messaging
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "poseBridge")
        config.userContentController = contentController

        // Inject a tiny script so the webpage can call window.webkit.messageHandlers.poseBridge.postMessage(...)
        // If your existing site already posts messages to React Native WebView,
        // you can also adapt the site to post to this handler.
        // But most likely your site uses window.ReactNativeWebView.postMessage(...)
        // so we can also shim that:
        let shim = """
        (function() {
          window.ReactNativeWebView = {
            postMessage: function(data) {
              window.webkit.messageHandlers.poseBridge.postMessage(data);
            }
          };
        })();
        """
        contentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let parent: PoseWebView

        init(_ parent: PoseWebView) { self.parent = parent }

        // Allow camera prompt inside WKWebView
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "poseBridge" else { return }

            // message.body may be a String (JSON) or an object
            if let str = message.body as? String {
                handle(jsonString: str)
            } else if let dict = message.body as? [String: Any] {
                // Sometimes it comes as object — convert to JSON string
                if let data = try? JSONSerialization.data(withJSONObject: dict),
                   let str = String(data: data, encoding: .utf8) {
                    handle(jsonString: str)
                }
            }
        }

        private func handle(jsonString: String) {
            guard let data = jsonString.data(using: .utf8) else { return }

            // Your RN message format:
            // { type: "cnn", armProb: ... }
            // { type: "landmarks", poseLandmarks: [...] }
            struct AnyMsg: Decodable {
                let type: String
                let armProb: Double?
                let poseLandmarks: [PosePoint]?
            }

            do {
                let msg = try JSONDecoder().decode(AnyMsg.self, from: data)
                if msg.type == "cnn", let p = msg.armProb {
                    parent.onCnnProb(p)
                } else if msg.type == "landmarks", let pts = msg.poseLandmarks {
                    parent.onLandmarks(pts)
                }
            } catch {
                // ignore parse errors; you can print if debugging
                // print("Parse error:", error)
            }
        }
    }
}
