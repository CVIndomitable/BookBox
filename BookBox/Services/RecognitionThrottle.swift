import Foundation

/// 限制识别接口的最大并发数，防止连拍多张时同时发起 10+ 请求压垮后端。
/// 用法：
///   try await RecognitionThrottle.shared.run { try await NetworkService.shared.recognizeBooks(...) }
actor RecognitionThrottle {
    static let shared = RecognitionThrottle(maxConcurrent: 3)

    private let maxConcurrent: Int
    private var inflight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }

    func run<T>(_ work: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    private func acquire() async {
        if inflight < maxConcurrent {
            inflight += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        // 被 release() 唤醒后计数已在 release 里 +1
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
            // 让出的槽位直接给等待者
            return
        }
        inflight -= 1
    }
}
