import Foundation
import SwiftUI

/// 降级状态全局存储：识别 / 语音指令返回 SupplierMeta 时，在这里记录一下
/// UI 层订阅，在顶部展示横幅提醒用户。
@MainActor
final class SupplierStatusStore: ObservableObject {
    static let shared = SupplierStatusStore()

    @Published var currentDegradation: SupplierMeta?
    @Published var dismissedAt: Date?

    private init() {}

    /// 由网络层在每次 AI 调用返回后调用
    func record(_ meta: SupplierMeta?) {
        guard let meta else { return }
        if meta.degraded {
            currentDegradation = meta
            dismissedAt = nil
        } else {
            // 顶级供应商又活过来了：清除降级提示
            if currentDegradation != nil {
                currentDegradation = nil
            }
        }
    }

    /// 用户手动关闭横幅
    func dismiss() {
        dismissedAt = Date()
        currentDegradation = nil
    }

    var shouldShowBanner: Bool {
        guard currentDegradation != nil else { return false }
        // 用户关闭后 10 分钟内不再打扰
        if let dismissed = dismissedAt, Date().timeIntervalSince(dismissed) < 600 {
            return false
        }
        return true
    }
}
