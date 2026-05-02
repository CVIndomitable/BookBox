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
            // 服务端错误 body 一般是 {"error":"...","attempts":[...]}，抽出 error 字段展示；
            // 解析不到就退回原始 message，避免丢失信息。
            let extracted = Self.extractErrorField(from: message) ?? message ?? "未知错误"
            return "请求失败(\(code)): \(extracted)"
        case .decodingError:
            return "数据解析失败"
        case .networkUnavailable:
            return "网络不可用，请检查网络连接"
        }
    }

    private static func extractErrorField(from body: String?) -> String? {
        guard let body, let data = body.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["error"] as? String
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

    /// 服务器地址（根据编译配置切换）
    let baseURL = AppConfig.current

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        // 服务器 Prisma 返回 ISO-8601 带毫秒（如 2026-04-16T08:20:57.558Z），
        // iOS 18 及以下 .iso8601 策略不支持小数秒会解码失败。自定义兼容两种格式。
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = NetworkService.iso8601WithFractional.date(from: string)
                ?? NetworkService.iso8601Plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析日期: \(string)"
            )
        }

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
        if let token = AuthService.shared.token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 非幂等写请求带一个稳定的 X-Request-Id，网络抖动重试时服务端可识别去重，
        // 避免重复下单/建书。GET 天然幂等，不需要 ID。
        let isWrite = method == "POST" || method == "PUT" || method == "DELETE"
        if isWrite {
            urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        }

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

        // 所有请求都自动重试（最多 3 次，指数退避）；
        // 写请求有 X-Request-Id 去重保底，不会在服务端产生重复记录。
        let maxRetries = 3
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
            // 401 视为登录态失效，清 token 触发 LoginView
            if httpResponse.statusCode == 401 {
                AuthService.shared.clear()
            }
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

    // MARK: - 认证 API

    struct LoginRequest: Codable { let username: String; let password: String }
    struct RegisterRequest: Codable {
        let username: String
        let password: String
        let email: String?
        let displayName: String?
    }
    struct AuthResponse: Codable { let user: AuthUser; let token: String }

    func login(username: String, password: String) async throws {
        let resp: AuthResponse = try await request(
            "POST",
            path: "/auth/login",
            body: LoginRequest(username: username, password: password)
        )
        AuthService.shared.setSession(token: resp.token, user: resp.user)
    }

    func register(username: String, password: String, email: String?, displayName: String?) async throws {
        let resp: AuthResponse = try await request(
            "POST",
            path: "/auth/register",
            body: RegisterRequest(username: username, password: password, email: email, displayName: displayName)
        )
        AuthService.shared.setSession(token: resp.token, user: resp.user)
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

    // MARK: - 房间 API

    func fetchRooms(libraryId: Int? = nil) async throws -> [Room] {
        var queryItems: [URLQueryItem]?
        if let libraryId {
            queryItems = [URLQueryItem(name: "libraryId", value: "\(libraryId)")]
        }
        return try await request("GET", path: "/rooms", queryItems: queryItems)
    }

    func createRoom(_ room: RoomRequest) async throws -> Room {
        try await request("POST", path: "/rooms", body: room)
    }

    func updateRoom(id: Int, _ req: RoomUpdateRequest) async throws -> Room {
        try await request("PUT", path: "/rooms/\(id)", body: req)
    }

    func deleteRoom(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/rooms/\(id)")
    }

    // MARK: - 箱子 API

    func fetchBoxes(libraryId: Int? = nil, roomId: Int? = nil) async throws -> [Box] {
        var queryItems: [URLQueryItem] = []
        if let libraryId {
            queryItems.append(URLQueryItem(name: "libraryId", value: "\(libraryId)"))
        }
        if let roomId {
            queryItems.append(URLQueryItem(name: "roomId", value: "\(roomId)"))
        }
        return try await request("GET", path: "/boxes", queryItems: queryItems.isEmpty ? nil : queryItems)
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

    func fetchShelves(libraryId: Int? = nil, roomId: Int? = nil) async throws -> [Shelf] {
        var queryItems: [URLQueryItem] = []
        if let libraryId {
            queryItems.append(URLQueryItem(name: "libraryId", value: "\(libraryId)"))
        }
        if let roomId {
            queryItems.append(URLQueryItem(name: "roomId", value: "\(roomId)"))
        }
        return try await request("GET", path: "/shelves", queryItems: queryItems.isEmpty ? nil : queryItems)
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

    /// 查重：按"书名 + 出版社"精确匹配，跨全部书库
    func checkDuplicates(
        candidates: [DuplicateCheckCandidate]
    ) async throws -> [DuplicateHit] {
        struct Req: Codable { let books: [DuplicateCheckCandidate] }
        struct Resp: Codable { let duplicates: [DuplicateHit] }
        let resp: Resp = try await request(
            "POST",
            path: "/books/check-duplicates",
            body: Req(books: candidates)
        )
        return resp.duplicates
    }

    /// 全库查重：扫描所有书，返回重复分组
    func fetchLibraryDuplicates() async throws -> DuplicateLibraryResponse {
        try await request("GET", path: "/books/duplicates", timeout: 30)
    }

    func fetchBook(id: Int) async throws -> Book {
        try await request("GET", path: "/books/\(id)")
    }

    func updateBook(id: Int, _ book: NewBookRequest) async throws -> Book {
        try await request("PUT", path: "/books/\(id)", body: book)
    }

    /// 软删：把书放进回收站（服务端会在 30 天后物理删除）
    func deleteBook(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/books/\(id)")
    }

    // MARK: - 回收站

    func fetchTrashedBooks() async throws -> TrashResponse {
        try await request("GET", path: "/books/trash")
    }

    func restoreBook(id: Int) async throws -> EmptyResponse {
        try await request("POST", path: "/books/\(id)/restore")
    }

    /// 跳过 30 天等待，立即彻底删除
    func purgeBook(id: Int) async throws -> EmptyResponse {
        try await request("DELETE", path: "/books/\(id)/purge")
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

    /// 从照片提取书籍详情（ISBN/出版时间/定价/出版社），并尝试匹配库内已有书
    /// libraryId 传了就只在该库内匹配；不传则跨全库
    func extractBookDetails(imageData: Data, libraryId: Int? = nil) async throws -> ExtractBookDetailsResponse {
        struct Req: Codable { let image: String; let libraryId: Int? }
        let base64 = imageData.base64EncodedString()
        let response: ExtractBookDetailsResponse = try await request(
            "POST",
            path: "/llm/extract-book-details",
            body: Req(image: base64, libraryId: libraryId),
            timeout: 120
        )
        return response
    }

    /// Siri/语音查书的智能搜索：严格子串 → 归一化宽松 → AI 兜底
    /// method 告诉调用方匹配等级：strict 精确、loose 宽松、ai 由 AI 猜的、none 没找到
    /// useAI=false 时只跑 DB 两层（供级联流程里前几轮只做快速筛查用）
    func findBookSmart(query: String, libraryId: Int? = nil, useAI: Bool = true) async throws -> SmartFindResult {
        struct Req: Codable { let query: String; let libraryId: Int?; let useAI: Bool }
        let result: SmartFindResult = try await request("POST", path: "/llm/find-book", body: Req(query: query, libraryId: libraryId, useAI: useAI), timeout: 60)
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

    // MARK: - 封面上传 API

    func uploadCover(bookId: Int, imageData: Data) async throws -> Book {
        guard var components = URLComponents(string: baseURL + "/covers/\(bookId)") else {
            throw NetworkError.invalidURL
        }
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        let boundary = UUID().uuidString
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = AuthService.shared.token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"cover\"; filename=\"cover.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        urlRequest.httpBody = body

        isLoading = true
        defer { isLoading = false }

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 401 {
                AuthService.shared.clear()
            }
            throw NetworkError.httpError(httpResponse.statusCode, message)
        }

        return try decoder.decode(Book.self, from: data)
    }

    func deleteCover(bookId: Int) async throws -> Book {
        try await request("DELETE", path: "/covers/\(bookId)")
    }

    // MARK: - 书库成员 API

    func fetchMembers(libraryId: Int) async throws -> [LibraryMember] {
        let resp: MembersResponse = try await request("GET", path: "/library-members/\(libraryId)/members")
        return resp.members
    }

    func addMember(libraryId: Int, username: String, role: MemberRole) async throws -> LibraryMember {
        struct AddResp: Codable { let member: LibraryMember }
        let resp: AddResp = try await request(
            "POST",
            path: "/library-members/\(libraryId)/members",
            body: AddMemberRequest(username: username, role: role)
        )
        return resp.member
    }

    func updateMemberRole(libraryId: Int, userId: Int, role: MemberRole) async throws -> LibraryMember {
        struct UpdateResp: Codable { let member: LibraryMember }
        let resp: UpdateResp = try await request(
            "PATCH",
            path: "/library-members/\(libraryId)/members/\(userId)",
            body: UpdateMemberRoleRequest(role: role)
        )
        return resp.member
    }

    func removeMember(libraryId: Int, userId: Int) async throws {
        let _: EmptyResponse = try await request("DELETE", path: "/library-members/\(libraryId)/members/\(userId)")
    }

    func transferOwnership(libraryId: Int, to username: String) async throws {
        let _: EmptyResponse = try await request(
            "POST",
            path: "/library-members/\(libraryId)/transfer",
            body: TransferOwnershipRequest(username: username)
        )
    }

    func leaveLibrary(libraryId: Int) async throws {
        let _: EmptyResponse = try await request("POST", path: "/library-members/\(libraryId)/leave")
    }

    // MARK: - 晒书提醒 API

    func fetchSunReminders() async throws -> [SunReminder] {
        let resp: SunReminderListResponse = try await request("GET", path: "/sun-reminders")
        return resp.reminders
    }

    func createLibrarySunReminder(libraryId: Int, sunDays: Int? = nil) async throws -> SunReminder {
        struct CreateResp: Codable { let reminder: SunReminder }
        let resp: CreateResp = try await request(
            "POST",
            path: "/sun-reminders/library/\(libraryId)",
            body: CreateSunReminderRequest(sunDays: sunDays)
        )
        return resp.reminder
    }

    func createBoxSunReminder(boxId: Int, sunDays: Int? = nil) async throws -> SunReminder {
        struct CreateResp: Codable { let reminder: SunReminder }
        let resp: CreateResp = try await request(
            "POST",
            path: "/sun-reminders/box/\(boxId)",
            body: CreateSunReminderRequest(sunDays: sunDays)
        )
        return resp.reminder
    }

    func updateSunReminder(id: Int, sunDays: Int) async throws -> SunReminder {
        struct UpdateResp: Codable { let reminder: SunReminder }
        let resp: UpdateResp = try await request(
            "PATCH",
            path: "/sun-reminders/\(id)",
            body: UpdateSunReminderRequest(sunDays: sunDays)
        )
        return resp.reminder
    }

    func markSunReminderAsSunned(id: Int) async throws -> SunReminder {
        struct MarkResp: Codable { let reminder: SunReminder }
        let resp: MarkResp = try await request("POST", path: "/sun-reminders/\(id)/mark-sunned")
        return resp.reminder
    }

    func deleteSunReminder(id: Int) async throws {
        let _: EmptyResponse = try await request("DELETE", path: "/sun-reminders/\(id)")
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
