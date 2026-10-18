import Foundation

/// Backend calls the activation flow needs.
enum ActivationAction: String {
    case register
    case heartbeat
    case activate
    case check
    case manualClaim = "manual-claim"
}

struct ActivationResponse {
    let status: Int
    /// Flat string dictionary; the backend only ever returns scalars.
    let body: [String: String]?
    /// Human readable transport detail. Never contains a token.
    let diagnostic: String

    var error: String? { body?["error"] }
}

/// Transport layer for the PHP authorization endpoint.
/// Knows nothing about UI or persistence.
final class ActivationClient {
    private let endpoint: URL
    private let session: URLSession

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    private func url(action: ActivationAction) -> URL? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
        return components?.url
    }

    func send(_ action: ActivationAction,
              payload: [String: String]? = nil,
              token: String? = nil,
              completion: @escaping (ActivationResponse) -> Void) {
        guard let url = url(action: action) else {
            completion(ActivationResponse(status: 0, body: nil, diagnostic: "授权地址无效"))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let payload { request.httpBody = try? JSONSerialization.data(withJSONObject: payload) }

        session.dataTask(with: request) { data, response, error in
            let http = response as? HTTPURLResponse
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let object = json?.compactMapValues { $0 as? String }
            let status = http?.statusCode ?? 0
            // Show only response type/shape; never expose an authorization token.
            let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "missing"
            let diagnostic: String
            if let error {
                diagnostic = "网络错误：" + error.localizedDescription
            } else if object == nil {
                diagnostic = "HTTP " + String(status) + "，服务器未返回 JSON（" + contentType + "）"
            } else {
                diagnostic = "HTTP " + String(status) + "，返回字段："
                    + (json?.keys.sorted().joined(separator: ",") ?? "none")
            }
            DispatchQueue.main.async { completion(ActivationResponse(status: status, body: object, diagnostic: diagnostic)) }
        }.resume()
    }
}
