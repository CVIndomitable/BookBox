import Foundation

/// 成员角色
enum MemberRole: String, Codable, Comparable {
    case owner
    case admin
    case member

    static func < (lhs: MemberRole, rhs: MemberRole) -> Bool {
        let rank: [MemberRole: Int] = [.owner: 3, .admin: 2, .member: 1]
        return (rank[lhs] ?? 0) < (rank[rhs] ?? 0)
    }

    var label: String {
        switch self {
        case .owner: "所有者"
        case .admin: "管理员"
        case .member: "成员"
        }
    }
}

/// 书库成员
struct LibraryMember: Identifiable, Codable {
    let id: Int
    let userId: Int
    let role: MemberRole
    let user: MemberUser
}

/// 成员用户信息
struct MemberUser: Codable, Equatable {
    let id: Int
    let username: String
    let displayName: String?
}

struct MembersResponse: Codable {
    let members: [LibraryMember]
}

struct AddMemberRequest: Codable {
    let username: String
    let role: MemberRole
}

struct UpdateMemberRoleRequest: Codable {
    let role: MemberRole
}

struct TransferOwnershipRequest: Codable {
    let username: String
}
