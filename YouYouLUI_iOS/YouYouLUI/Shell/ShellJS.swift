import WebKit

extension MainShellViewController {
    /// Calls `window.__<function>?.(...arguments)` on the shared page.
    /// Arguments are JSON-encoded, so strings are always safely escaped.
    func evaluate(arguments: [Any], function: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let args = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__" + function + "?.(..." + args + ")")
    }

    /// Runs an arbitrary script; failures are ignored (the page may not be ready).
    func evaluate(_ script: String) {
        webView.evaluateJavaScript(script)
    }

    func evaluate(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        webView.evaluateJavaScript(script, completionHandler: completion)
    }

    /// Sends a command into the shared web engine.
    func callEngine(_ function: String, arguments: [Any], completion: ((Any?, Error?) -> Void)? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let args = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window." + function + "?.(..." + args + ")", completionHandler: completion)
    }
}
