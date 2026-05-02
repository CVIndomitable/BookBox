import Foundation

extension Error {
    /// 获取中文错误描述，确保所有错误信息都以中文展示
    var chineseDescription: String {
        // 自定义错误类型已有中文描述
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        // URLError 映射
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "网络未连接，请检查网络设置"
            case .timedOut:
                return "请求超时，请稍后重试"
            case .cannotFindHost, .cannotConnectToHost:
                return "无法连接到服务器"
            case .networkConnectionLost:
                return "网络连接已断开"
            case .cancelled:
                return "请求已取消"
            case .badURL:
                return "无效的请求地址"
            case .badServerResponse:
                return "服务器响应异常"
            case .secureConnectionFailed:
                return "安全连接失败"
            default:
                return "网络请求失败"
            }
        }

        // DecodingError 映射（附带字段信息帮助排查）
        if let decodingError = self as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, _):
                return "数据解析失败：缺少字段「\(key.stringValue)」"
            case .typeMismatch(let type, let context):
                let field = context.codingPath.map(\.stringValue).joined(separator: ".")
                return "数据解析失败：字段「\(field)」类型不匹配（期望 \(type)）"
            case .valueNotFound(_, let context):
                let field = context.codingPath.map(\.stringValue).joined(separator: ".")
                return "数据解析失败：字段「\(field)」值为空"
            case .dataCorrupted:
                return "数据解析失败：数据格式损坏"
            @unknown default:
                return "数据解析失败"
            }
        }

        // EncodingError 映射
        if self is EncodingError {
            return "数据编码失败"
        }

        return "操作失败，请稍后重试"
    }
}
