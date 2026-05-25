import Foundation

public struct ReaderUser: Codable, Sendable {
    public let id: String
    public let email: String
    public let name: String?
}

public struct AuthResponse: Codable, Sendable {
    public let user: ReaderUser
    public let token: String
}

public struct ReaderLabel: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let color: String
}

public struct ArticleSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let author: String?
    public let description: String?
    public let siteName: String?
    public let image: String?
    public let favicon: String?
    public let publishedAt: Date?
    public let archived: Bool
    public let readAt: Date?
    public let ttr: Int?
    public let createdAt: Date
    public let labels: [ReaderLabel]
}

public struct Article: Codable, Identifiable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let author: String?
    public let description: String?
    public let content: String
    public let siteName: String?
    public let publishedAt: Date?
    public let ttr: Int?
    public let archived: Bool
    public let labels: [ReaderLabel]
}

public enum ReaderAPIError: Error, LocalizedError {
    case invalidResponse
    case server(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .server(_, let message):
            message
        }
    }
}

public actor ReaderAPIClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()
    private var token: String?

    public init(baseURL: URL, token: String? = nil, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.urlSession = urlSession

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        self.decoder = decoder
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    public func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await send(
            path: "/api/auth/login",
            method: "POST",
            body: ["email": email, "password": password]
        )
        token = response.token
        return response
    }

    public func register(email: String, password: String, name: String? = nil) async throws -> AuthResponse {
        var body = ["email": email, "password": password]
        if let name, !name.isEmpty {
            body["name"] = name
        }
        let response: AuthResponse = try await send(
            path: "/api/auth/register",
            method: "POST",
            body: body
        )
        token = response.token
        return response
    }

    public func articles(archived: Bool = false, search: String? = nil, labelId: String? = nil) async throws -> [ArticleSummary] {
        var items = [URLQueryItem(name: "archived", value: archived ? "true" : "false")]
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        if let labelId { items.append(URLQueryItem(name: "labelId", value: labelId)) }
        return try await send(path: "/api/articles", queryItems: items)
    }

    public func article(id: String) async throws -> Article {
        try await send(path: "/api/articles/\(id)")
    }

    public func saveArticle(url: String) async throws -> Article {
        try await send(path: "/api/articles", method: "POST", body: ["url": url])
    }

    public func setArchived(_ archived: Bool, articleId: String) async throws -> Article {
        try await send(path: "/api/articles/\(articleId)", method: "PATCH", body: ["archived": archived])
    }

    public func deleteArticle(id: String) async throws {
        let _: EmptyResponse = try await send(path: "/api/articles/\(id)", method: "DELETE")
    }

    public func labels() async throws -> [ReaderLabel] {
        try await send(path: "/api/labels")
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        try await send(path: path, method: method, queryItems: queryItems, bodyData: encoder.encode(body))
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        try await send(path: path, method: method, queryItems: queryItems, bodyData: nil)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) async throws -> Response {
        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        components?.path = "/" + ([basePath, relativePath].filter { !$0.isEmpty }.joined(separator: "/"))
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw ReaderAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderAPIError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(ServerError.self, from: data)
            throw ReaderAPIError.server(status: http.statusCode, message: error?.error ?? "Request failed.")
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct ServerError: Codable {
    let error: String
}

private struct EmptyResponse: Codable {}
