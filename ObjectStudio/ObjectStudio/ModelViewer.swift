import SwiftUI
import WebKit

struct ModelViewer: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ObjectStudioViewer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let modelName = "model.\(fileURL.pathExtension.isEmpty ? "glb" : fileURL.pathExtension)"
        let localModel = folder.appending(path: modelName)
        try? FileManager.default.removeItem(at: localModel)
        try? FileManager.default.copyItem(at: fileURL, to: localModel)
        let html = """
        <!doctype html><html><head>
        <meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'>
        <script type='module' src='https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js'></script>
        <style>html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden}model-viewer{width:100%;height:100%;background:transparent;--poster-color:transparent}</style>
        </head><body>
        <model-viewer src='\(modelName)' camera-controls auto-rotate shadow-intensity='1' exposure='1.0' interaction-prompt='none'></model-viewer>
        </body></html>
        """
        let htmlURL = folder.appending(path: "viewer.html")
        try? html.data(using: .utf8)?.write(to: htmlURL)
        web.loadFileURL(htmlURL, allowingReadAccessTo: folder)
    }
}
