# iOS 端用户系统与推送集成指南

## 概述

iOS 端需要集成用户登录和 APNs 推送功能，以支持多用户书库管理和晒书提醒。

## 需要实现的功能

### 1. 用户登录界面

创建登录/注册界面，调用后端 API：

```swift
// Models/User.swift
struct User: Codable {
    let id: Int
    let username: String
    let email: String?
    let displayName: String?
    let defaultSunDays: Int
    let createdAt: String
}

struct AuthResponse: Codable {
    let user: User
    let token: String
}

// Services/AuthService.swift
class AuthService {
    static let shared = AuthService()
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    
    private var token: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }
    
    func login(username: String, password: String) async throws -> User {
        let response: AuthResponse = try await NetworkService.shared.post(
            "/auth/login",
            body: ["username": username, "password": password]
        )
        
        self.token = response.token
        self.currentUser = response.user
        self.isAuthenticated = true
        
        return response.user
    }
    
    func register(username: String, password: String, email: String?) async throws -> User {
        let body: [String: Any] = [
            "username": username,
            "password": password,
            "email": email ?? ""
        ]
        
        let response: AuthResponse = try await NetworkService.shared.post(
            "/auth/register",
            body: body
        )
        
        self.token = response.token
        self.currentUser = response.user
        self.isAuthenticated = true
        
        return response.user
    }
    
    func logout() {
        self.token = nil
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    func getAuthHeader() -> [String: String]? {
        guard let token = token else { return nil }
        return ["Authorization": "Bearer \(token)"]
    }
}
```

### 2. 更新 NetworkService

在所有请求中添加 JWT token：

```swift
// Services/NetworkService.swift
extension NetworkService {
    func post<T: Decodable, B: Encodable>(
        _ path: String,
        body: B,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加认证头
        if requiresAuth, let authHeader = AuthService.shared.getAuthHeader() {
            authHeader.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        }
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            // Token 过期，退出登录
            AuthService.shared.logout()
            throw NetworkError.unauthorized
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

### 3. APNs 推送集成

#### 3.1 注册推送通知

```swift
// AppDelegate.swift 或 App.swift
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerForPushNotifications()
        return true
    }
    
    func registerForPushNotifications() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else { return }
                
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        
        // 上传 token 到服务器
        Task {
            try? await uploadAPNsToken(token)
        }
    }
    
    func uploadAPNsToken(_ token: String) async throws {
        let _: EmptyResponse = try await NetworkService.shared.patch(
            "/auth/me",
            body: ["apnsToken": token]
        )
    }
    
    // 处理前台通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    // 处理通知点击
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        
        if let type = userInfo["type"] as? String,
           type == "sun_reminder",
           let targetType = userInfo["targetType"] as? String,
           let targetId = userInfo["targetId"] as? Int {
            // 跳转到对应的书库或箱子
            NotificationCenter.default.post(
                name: .openSunReminder,
                object: nil,
                userInfo: ["targetType": targetType, "targetId": targetId]
            )
        }
    }
}

extension Notification.Name {
    static let openSunReminder = Notification.Name("openSunReminder")
}
```

#### 3.2 在主 App 中注册 AppDelegate

```swift
// BookBoxApp.swift
@main
struct BookBoxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService = AuthService.shared
    
    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                ContentView()
            } else {
                LoginView()
            }
        }
    }
}
```

### 4. 登录界面

```swift
// Views/LoginView.swift
struct LoginView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRegister = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("BookBox")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                TextField("用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: login) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("登录")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || username.isEmpty || password.isEmpty)
                
                Button("还没有账号？注册") {
                    showRegister = true
                }
                .font(.caption)
            }
            .padding()
            .navigationTitle("登录")
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
        }
    }
    
    private func login() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await AuthService.shared.login(
                    username: username,
                    password: password
                )
            } catch {
                errorMessage = "登录失败：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
```

### 5. 书库列表更新

更新书库列表以支持多用户：

```swift
// Views/LibraryListView.swift
struct LibraryListView: View {
    @State private var libraries: [LibraryWithRole] = []
    
    struct LibraryWithRole: Codable, Identifiable {
        let id: Int
        let name: String
        let location: String?
        let bookCount: Int
        let role: String // owner/admin/member
    }
    
    var body: some View {
        List(libraries) { library in
            NavigationLink(destination: LibraryDetailView(libraryId: library.id)) {
                VStack(alignment: .leading) {
                    Text(library.name)
                        .font(.headline)
                    if let location = library.location {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("\(library.bookCount) 本书")
                            .font(.caption)
                        Spacer()
                        Text(roleText(library.role))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(roleColor(library.role))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .navigationTitle("我的书库")
        .task {
            await loadLibraries()
        }
    }
    
    private func loadLibraries() async {
        do {
            libraries = try await NetworkService.shared.get("/libraries")
        } catch {
            print("加载书库失败: \(error)")
        }
    }
    
    private func roleText(_ role: String) -> String {
        switch role {
        case "owner": return "所有者"
        case "admin": return "管理员"
        case "member": return "成员"
        default: return role
        }
    }
    
    private func roleColor(_ role: String) -> Color {
        switch role {
        case "owner": return .yellow
        case "admin": return .blue
        case "member": return .gray
        default: return .gray
        }
    }
}
```

### 6. 晒书提醒视图

```swift
// Views/SunRemindersView.swift
struct SunRemindersView: View {
    @State private var reminders: [SunReminder] = []
    
    struct SunReminder: Codable, Identifiable {
        let id: Int
        let targetType: String
        let targetId: Int
        let targetName: String
        let lastSunAt: String?
        let nextSunAt: String
        let sunDays: Int
        let notified: Bool
    }
    
    var body: some View {
        List(reminders) { reminder in
            VStack(alignment: .leading, spacing: 8) {
                Text(reminder.targetName)
                    .font(.headline)
                
                Text(reminder.targetType == "library" ? "书库" : "箱子")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("下次晒书：\(formatDate(reminder.nextSunAt))")
                    .font(.caption)
                
                Button("已晒书") {
                    Task {
                        await markSunned(reminder.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("晒书提醒")
        .task {
            await loadReminders()
        }
    }
    
    private func loadReminders() async {
        do {
            let response: RemindersResponse = try await NetworkService.shared.get("/sun-reminders")
            reminders = response.reminders
        } catch {
            print("加载提醒失败: \(error)")
        }
    }
    
    private func markSunned(_ id: Int) async {
        do {
            let _: EmptyResponse = try await NetworkService.shared.post(
                "/sun-reminders/\(id)/mark-sunned",
                body: EmptyBody()
            )
            await loadReminders()
        } catch {
            print("标记失败: \(error)")
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        displayFormatter.locale = Locale(identifier: "zh_CN")
        
        return displayFormatter.string(from: date)
    }
}

struct RemindersResponse: Codable {
    let reminders: [SunRemindersView.SunReminder]
}

struct EmptyBody: Codable {}
struct EmptyResponse: Codable {}
```

## 配置清单

### Info.plist 添加权限

```xml
<key>NSUserNotificationsUsageDescription</key>
<string>需要通知权限以提醒您晒书</string>
```

### 启用推送能力

1. 在 Xcode 中选择项目 Target
2. Signing & Capabilities → + Capability → Push Notifications
3. 在 Apple Developer 后台配置 APNs 证书

### 环境变量

确保 `AppConfig.swift` 中的服务器地址正确：

```swift
struct AppConfig {
    static let serverURL = "http://47.113.221.26:3002"
}
```

## 测试步骤

1. 注册新用户
2. 登录成功后查看书库列表
3. 创建书库（自动成为 owner）
4. 添加书籍
5. 设置晒书提醒
6. 等待推送通知（或手动触发测试）
7. 点击通知跳转到对应页面

## 注意事项

- JWT token 有效期 30 天，过期后需重新登录
- APNs 推送需要真机测试，模拟器不支持
- 生产环境需配置正式的 APNs 证书
- 推送通知的 payload 包含 `type`, `targetType`, `targetId` 字段
