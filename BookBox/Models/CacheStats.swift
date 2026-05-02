import Foundation

/// LLM 缓存统计
struct CacheStats: Codable {
    let hits: Int
    let misses: Int
    let total: Int
    let hitRate: String
    let cacheSize: Int
    let activeEntries: Int
    let maxSize: Int
    let startedAt: String
}
