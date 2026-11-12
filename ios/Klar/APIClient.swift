import Foundation

struct APIError: LocalizedError {
    let statusCode: Int
    let description: String
    var errorDescription: String? { description }
}

struct APIClient {
    var baseURL: String {
        let input = UserDefaults.standard.string(forKey: "api_base_url") ?? "https://api.152.53.206.242.sslip.io"
        return input.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func request<Response: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
                                      accessToken: String? = nil, response: Response.Type = Response.self) async throws -> Response {
        guard baseURL.hasPrefix("https://"), let url = URL(string: baseURL + path) else {
            throw APIError(statusCode: 0, description: "Bitte eine gültige HTTPS-Serveradresse einstellen.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, result) = try await URLSession.shared.data(for: request)
        guard let http = result as? HTTPURLResponse else { throw APIError(statusCode: 0, description: "Ungültige Serverantwort") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"]
            throw APIError(statusCode: http.statusCode, description: "Serverfehler \(http.statusCode): \(message.map { String(describing: $0) } ?? "Unbekannt")")
        }
        if http.statusCode == 204, let empty = "{}".data(using: .utf8) {
            return try JSONDecoder.klar.decode(Response.self, from: empty)
        }
        return try JSONDecoder.klar.decode(Response.self, from: data)
    }
}

extension JSONEncoder {
    static var klar: JSONEncoder {
        let coder = JSONEncoder()
        coder.dateEncodingStrategy = .iso8601
        return coder
    }
}
extension JSONDecoder {
    static var klar: JSONDecoder {
        let coder = JSONDecoder()
        coder.dateDecodingStrategy = .iso8601
        return coder
    }
}
