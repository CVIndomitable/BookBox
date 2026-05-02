import Foundation

/// 晒书提醒
struct SunReminder: Identifiable, Codable {
    let id: Int
    let targetType: String
    let targetId: Int
    let targetName: String
    let lastSunAt: Date?
    let nextSunAt: Date
    let sunDays: Int
    let notified: Bool
}

struct SunReminderListResponse: Codable {
    let reminders: [SunReminder]
}

struct CreateSunReminderRequest: Codable {
    let sunDays: Int?
}

struct UpdateSunReminderRequest: Codable {
    let sunDays: Int
}
