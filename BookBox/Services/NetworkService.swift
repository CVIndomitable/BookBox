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
        case .decodingError:
            return "数据解析失败"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接"
        }
    }
}

/// 分页响应
struct PaginatedResponse<T: Codable>: Codable {
    let data: [T]
    let pagination: Pagination
}

struct Pagination: Codable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
}

/// 批量创建响应
struct BatchCreateResponse: Codable {
    let created: Int
    let skipped: Int?
    let books: [Book]
}

/// 网络服务 — 统一管理所有后端 API 请求
@MainActor
final class NetworkService: ObservableObject {
    static let shared = NetworkService()

    @Published var isLoading = false

    /// 服务器地址（硬编码）
    let baseURL = AppConfig.serverBaseURL

    /// 认证 token（硬编码）
    let apiToken = AppConfig.apiToken

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
        queryItems: [URLQueryItem]? = nil,
        timeout: TimeInterval? = nil
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
        urlRequest.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        if let timeout {
            urlRequest.timeoutInterval = timeout
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        #if DEBUG
        print("[NET] \(method) \(url.absoluteString)")
        #endif

        isLoading = true
        defer { isLoading = false }

        // GET 请求自动重试（最多 3 次，指数退避）
        let maxRetries = method == "GET" ? 3 : 1
        var lastError: Error?
        var data: Data = Data()
        var response: URLResponse = URLResponse()
        for attempt in 1...maxRetries {
            do {
                (data, response) = try await session.data(for: urlRequest)
                lastError = nil
                break
            } catch {
                lastError = error
                #if DEBUG
                print("[NET] 请求失败 (第\(attempt)次): \(error)")
                #endif
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        if let lastError {
            throw lastError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("[NET] 响应格式错误")
            #endif
            throw NetworkError.invalidResponse
        }

        #if DEBUG
        print("[NET] 状态码: \(httpResponse.statusCode)")
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            #if DEBUG
            print("[NET] HTTP 错误: \(httpResponse.statusCode) - \(message ?? "无内容")")
            #endif
            throw NetworkError.httpError(httpResponse.statusCode, message)
        }

        do {
            let result = try decoder.decode(T.self, from: data)
            #if DEBUG
            print("[NET] 解码成功: \(T.self)")
            #endif
            return result
        } catch {
            #if DEBUG
            print("[NET] 解码失败: \(error)")
            print("[NET] 原始数据: \(String(data: data, encoding: .utf8) ?? "无")")
            #endif
            throw NetworkError.decodingError(error)
        }
    }

    // MARK: - 健康检查

    /// 详细连通性检测（服务器、数据库、AI）
    func checkHealth() async throws -> HealthCheckResult {
        try await request("GET", path: "/health/detailed", timeout: 15)
    }

    // MARK: - 书库 API

    func fetchLibraries() async throws -> [Library] {
        try await request("GET", path: "/libraries")
    }

    func createLibrary(_ library: LibraryRequest) async throws -> Library {
        try await request("POST", path: "/libraries", body: library)
    }

    func fetchLibraryDetail(id: Int) async throws -> LibraryDetail {
        try await request("GET", path: "/libraries/\(id)")
    }

    func updateLibrary(id: Int, _ library: LibraryRequest) async throws -> Library {
        try await request("PUT", path: "/libraries/\(id)", body: library)
    }

    func deleteLibrary(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/libraries/\(id)")
    }

    // MARK: - 箱子 API

    func fetchBoxes(libraryId: Int? = nil) async throws -> [Box] {
        var queryItems: [URLQueryItem]?
        if let libraryId {
            queryItems = [URLQueryItem(name: "libraryId", value: "\(libraryId)")]
        }
        return try await request("GET", path: "/boxes", queryItems: queryItems)
    }

    func createBox(_ box: BoxRequest) async throws -> Box {
        try await request("POST", path: "/boxes", body: box)
    }

    func fetchBox(id: Int) async throws -> Box {
        try await request("GET", path: "/boxes/\(id)")
    }

    func updateBox(id: Int, _ box: BoxRequest) async throws -> Box {
        try await request("PUT", path: "/boxes/\(id)", body: box)
    }

    func deleteBox(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/boxes/\(id)")
    }

    func addBooksToBox(boxId: Int, bookIds: [Int]) async throws -> EmptyResponse {
        struct Req: Codable { let bookIds: [Int] }
        return try await request("POST", path: "/boxes/\(boxId)/books", body: Req(bookIds: bookIds))
    }

    func removeBookFromBox(boxId: Int, bookId: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/boxes/\(boxId)/books/\(bookId)")
    }

    // MARK: - 书架 API

    func fetchShelves(libraryId: Int? = nil) async throws -> [Shelf] {
        var queryItems: [URLQueryItem]?
        if let libraryId {
            queryItems = [URLQueryItem(name: "libraryId", value: "\(libraryId)")]
        }
        return try await request("GET", path: "/shelves", queryItems: queryItems)
    }

    func createShelf(_ shelf: ShelfRequest) async throws -> Shelf {
        try await request("POST", path: "/shelves", body: shelf)
    }

    func fetchShelf(id: Int) async throws -> Shelf {
        try await request("GET", path: "/shelves/\(id)")
    }

    func updateShelf(id: Int, _ shelf: ShelfRequest) async throws -> Shelf {
        try await request("PUT", path: "/shelves/\(id)", body: shelf)
    }

    func deleteShelf(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/shelves/\(id)")
    }

    func addBooksToShelf(shelfId: Int, bookIds: [Int]) async throws -> EmptyResponse {
        struct Req: Codable { let bookIds: [Int] }
        return try await request("POST", path: "/shelves/\(shelfId)/books", body: Req(bookIds: bookIds))
    }

    func removeBookFromShelf(shelfId: Int, bookId: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/shelves/\(shelfId)/books/\(bookId)")
    }

    // MARK: - 书籍 API

    func fetchBooks(
        page: Int = 1,
        pageSize: Int = 20,
        search: String? = nil,
        categoryId: Int? = nil,
        locationType: LocationType? = nil,
        locationId: Int? = nil,
        shelfId: Int? = nil,
        boxId: Int? = nil,
        libraryId: Int? = nil
    ) async throws -> PaginatedResponse<Book> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let categoryId {
            queryItems.append(URLQueryItem(name: "categoryId", value: "\(categoryId)"))
        }
        if let locationType {
            queryItems.append(URLQueryItem(name: "locationType", value: locationType.rawValue))
        }
        if let locationId {
            queryItems.append(URLQueryItem(name: "locationId", value: "\(locationId)"))
        }
        if let shelfId {
            queryItems.append(URLQueryItem(name: "shelfId", value: "\(shelfId)"))
        }
        if let boxId {
            queryItems.append(URLQueryItem(name: "boxId", value: "\(boxId)"))
        }
        if let libraryId {
            queryItems.append(URLQueryItem(name: "libraryId", value: "\(libraryId)"))
        }
        return try await request("GET", path: "/books", queryItems: queryItems)
    }

    func createBook(_ book: NewBookRequest) async throws -> Book {
        try await request("POST", path: "/books", body: book)
    }

    func createBooks(batch: BatchBooksRequest) async throws -> BatchCreateResponse {
        try await request("POST", path: "/books/batch", body: batch)
    }

    func fetchBook(id: Int) async throws -> Book {
        try await request("GET", path: "/books/\(id)")
    }

    func updateBook(id: Int, _ book: NewBookRequest) async throws -> Book {
        try await request("PUT", path: "/books/\(id)", body: book)
    }

    func deleteBook(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/books/\(id)")
    }

    // MARK: - 移动书籍

    func moveBook(id: Int, request: MoveBookRequest) async throws -> EmptyResponse {
        try await self.request("POST", path: "/books/\(id)/move", body: request)
    }

    // MARK: - 操作日志

    func fetchBookLogs(bookId: Int, page: Int = 1, pageSize: Int = 20) async throws -> PaginatedResponse<BookLog> {
        let queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        return try await request("GET", path: "/books/\(bookId)/logs", queryItems: queryItems)
    }

    func fetchAllLogs(page: Int = 1, pageSize: Int = 20, action: String? = nil, method: String? = nil) async throws -> PaginatedResponse<BookLog> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        if let action { queryItems.append(URLQueryItem(name: "action", value: action)) }
        if let method { queryItems.append(URLQueryItem(name: "method", value: method)) }
        return try await request("GET", path: "/logs", queryItems: queryItems)
    }

    // MARK: - 书库总览

    func fetchLibraryOverview(libraryId: Int? = nil) async throws -> LibraryOverview {
        var queryItems: [URLQueryItem]?
        if let libraryId {
            queryItems = [URLQueryItem(name: "libraryId", value: "\(libraryId)")]
        }
        return try await request("GET", path: "/library/overview", queryItems: queryItems)
    }

    // MARK: - 书籍校验

    func verifyBook(title: String, region: RegionMode) async throws -> VerifyResult {
        struct VerifyRequest: Codable {
            let title: String
            let region: String
        }
        let body = VerifyRequest(title: title, region: region.rawValue)
        return try await request("POST", path: "/books/verify", body: body)
    }

    // MARK: - 分类 API

    func fetchCategories() async throws -> [Category] {
        try await request("GET", path: "/categories")
    }

    func createCategory(name: String, parentId: Int? = nil) async throws -> Category {
        struct CreateRequest: Codable {
            let name: String
            let parentId: Int?
        }
        return try await request("POST", path: "/categories", body: CreateRequest(name: name, parentId: parentId))
    }

    func updateCategory(id: Int, name: String? = nil, parentId: Int? = nil) async throws -> Category {
        struct Req: Codable { let name: String?; let parentId: Int? }
        return try await request("PUT", path: "/categories/\(id)", body: Req(name: name, parentId: parentId))
    }

    func deleteCategory(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/categories/\(id)")
    }

    // MARK: - 设置 API

    func fetchSettings() async throws -> UserSettings {
        try await request("GET", path: "/settings")
    }

    func updateSettings(_ settings: UserSettings) async throws -> UserSettings {
        try await request("PUT", path: "/settings", body: settings)
    }

    // MARK: - AI 识别（服务器端 LLM）

    /// 通过服务器端 AI 识别图片中的书籍
    func recognizeBooks(imageData: Data) async throws -> [RecognizedBook] {
        struct Req: Codable { let image: String }
        struct Resp: Codable { let books: [RecognizedBook]; let supplier: SupplierMeta? }
        let base64 = imageData.base64EncodedString()
        let response: Resp = try await request("POST", path: "/llm/recognize", body: Req(image: base64), timeout: 120)
        SupplierStatusStore.shared.record(response.supplier)
        return response.books
    }

    /// 通过服务器端 AI 解析语音指令
    /// 仅传结构化上下文；system prompt 由服务器端构建，防止提示注入
    func processVoiceCommand(text: String, context: LibraryContext) async throws -> VoiceCommandResult {
        struct Req: Codable { let text: String; let context: LibraryContext }
        let result: VoiceCommandResult = try await request("POST", path: "/llm/voice-command", body: Req(text: text, context: context), timeout: 60)
        SupplierStatusStore.shared.record(result.supplier)
        return result
    }

    // MARK: - 供应商池（只读）

    func fetchSuppliers() async throws -> [LlmSupplier] {
        try await request("GET", path: "/suppliers")
    }

    // MARK: - LLM 缓存统计

    func fetchCacheStats() async throws -> CacheStats {
        try await request("GET", path: "/llm/cache-stats")
    }

    func resetCacheStats() async throws -> EmptyResponse {
        try await request("POST", path: "/llm/cache-stats/reset")
    }

    // MARK: - 扫描记录 API

    func saveScanRecord(mode: ScanMode, boxId: Int? = nil, extractedTitles: [String]? = nil) async throws -> ScanRecord {
        struct Req: Codable { let mode: ScanMode; let boxId: Int?; let extractedTitles: [String]? }
        return try await request("POST", path: "/scans", body: Req(mode: mode, boxId: boxId, extractedTitles: extractedTitles))
    }

    func fetchScanRecords(page: Int = 1, pageSize: Int = 20, mode: ScanMode? = nil) async throws -> PaginatedResponse<ScanRecord> {
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)")
        ]
        if let mode { queryItems.append(URLQueryItem(name: "mode", value: mode.rawValue)) }
        return try await request("GET", path: "/scans", queryItems: queryItems)
    }
}

/// 空响应体
struct EmptyResponse: Codable {}

/// 单项服务状态
struct ServiceStatus: Codable {
    let status: String
    let message: String?
}

/// 供应商健康状态（health/detailed 返回）
struct SupplierHealth: Codable {
    let name: String
    let priority: Int
    let status: String     // ok / error
    let message: String?
}

/// 详细健康检查结果
struct HealthCheckResult: Codable {
    let server: ServiceStatus
    let database: ServiceStatus
    let ai: ServiceStatus
    let suppliers: [SupplierHealth]?
}
