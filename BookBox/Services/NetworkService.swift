import Foundation

/// 网络请求错误
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String?)
    case decodingError(Error)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的请求地址"
        case .invalidResponse:
            return "服务器响应格式错误"
        case .httpError(let code, let message):
            return "请求失败(\(code)): \(message ?? "未知错误")"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接"
        }
    }
}

/// API 响应包装
struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
}

/// 分页响应
struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let page: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }
}

/// 网络服务 — 统一管理所有后端 API 请求
@MainActor
final class NetworkService: ObservableObject {
    static let shared = NetworkService()

    @Published var isLoading = false

    /// 服务器地址，从 UserDefaults 读取，可在设置中修改
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "server_base_url") ?? "http://localhost:3000" }
        set { UserDefaults.standard.set(newValue, forKey: "server_base_url") }
    }

    /// 认证 token
    var apiToken: String {
        get { UserDefaults.standard.string(forKey: "api_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "api_token") }
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - 通用请求方法

    private func request<T: Codable>(
        _ method: String,
        path: String,
        body: (any Codable)? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw NetworkError.invalidURL
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiToken.isEmpty {
            urlRequest.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw NetworkError.httpError(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    // MARK: - 箱子 API

    func fetchBoxes() async throws -> [Box] {
        try await request("GET", path: "/api/boxes")
    }

    func createBox(_ box: BoxRequest) async throws -> Box {
        try await request("POST", path: "/api/boxes", body: box)
    }

    func fetchBox(id: Int) async throws -> Box {
        try await request("GET", path: "/api/boxes/\(id)")
    }

    func updateBox(id: Int, _ box: BoxRequest) async throws -> Box {
        try await request("PUT", path: "/api/boxes/\(id)", body: box)
    }

    func deleteBox(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/api/boxes/\(id)")
    }

    // MARK: - 书籍 API

    func fetchBooks(page: Int = 1, pageSize: Int = 20, search: String? = nil, categoryId: Int? = nil) async throws -> PaginatedResponse<Book> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let categoryId {
            queryItems.append(URLQueryItem(name: "category_id", value: "\(categoryId)"))
        }
        return try await request("GET", path: "/api/books", queryItems: queryItems)
    }

    func createBook(_ book: NewBookRequest) async throws -> Book {
        try await request("POST", path: "/api/books", body: book)
    }

    func createBooks(batch: BatchBooksRequest) async throws -> [Book] {
        try await request("POST", path: "/api/books/batch", body: batch)
    }

    func fetchBook(id: Int) async throws -> Book {
        try await request("GET", path: "/api/books/\(id)")
    }

    func updateBook(id: Int, _ book: NewBookRequest) async throws -> Book {
        try await request("PUT", path: "/api/books/\(id)", body: book)
    }

    func deleteBook(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/api/books/\(id)")
    }

    // MARK: - 书籍校验

    func verifyBook(title: String, region: RegionMode) async throws -> VerifyResult {
        struct VerifyRequest: Codable {
            let title: String
            let region: String
        }
        let body = VerifyRequest(title: title, region: region.rawValue)
        return try await request("POST", path: "/api/books/verify", body: body)
    }

    // MARK: - 分类 API

    func fetchCategories() async throws -> [Category] {
        try await request("GET", path: "/api/categories")
    }

    func createCategory(name: String, parentId: Int? = nil) async throws -> Category {
        struct CreateRequest: Codable {
            let name: String
            let parentId: Int?
            enum CodingKeys: String, CodingKey {
                case name
                case parentId = "parent_id"
            }
        }
        return try await request("POST", path: "/api/categories", body: CreateRequest(name: name, parentId: parentId))
    }

    // MARK: - 设置 API

    func fetchSettings() async throws -> UserSettings {
        try await request("GET", path: "/api/settings")
    }

    func updateSettings(_ settings: UserSettings) async throws -> UserSettings {
        try await request("PUT", path: "/api/settings", body: settings)
    }

    // MARK: - 大模型 API

    func llmExtractTitles(ocrText: String) async throws -> [String] {
        struct ExtractRequest: Codable {
            let text: String
        }
        struct ExtractResponse: Codable {
            let titles: [String]
        }
        let response: ExtractResponse = try await request("POST", path: "/api/llm/extract", body: ExtractRequest(text: ocrText))
        return response.titles
    }

    func llmClassify(title: String) async throws -> String {
        struct ClassifyRequest: Codable {
            let title: String
        }
        struct ClassifyResponse: Codable {
            let category: String
        }
        let response: ClassifyResponse = try await request("POST", path: "/api/llm/classify", body: ClassifyRequest(title: title))
        return response.category
    }
}

/// 空响应体，用于 DELETE 等不返回数据的接口
struct EmptyResponse: Codable {}
