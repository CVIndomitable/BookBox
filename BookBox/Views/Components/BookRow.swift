import SwiftUI

/// 书籍列表行组件 — 展示书名、作者、校验状态
struct BookRow: View {
    let book: Book
    var showStatus = true

    var body: some View {
        HStack(spacing: 12) {
            // 封面缩略图
            AsyncImage(url: book.coverDisplayUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    coverPlaceholder
                default:
                    coverPlaceholder
                }
            }
            .frame(width: 44, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // 书籍信息
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.body)
                    .lineLimit(2)

                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let publisher = book.publisher, !publisher.isEmpty {
                    Text(publisher)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 校验状态指示器
            if showStatus, let status = book.verifyStatus {
                StatusBadge(status: status)
            }
        }
        .padding(.vertical, 4)
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }
}

/// 校验状态徽章（三色标识）
struct StatusBadge: View {
    let status: VerifyStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .matched: .green
        case .uncertain: .orange
        case .notFound, .manual: .red
        }
    }
}

#Preview {
    List {
        BookRow(book: Book(
            id: 1,
            title: "深入理解计算机系统",
            author: "Randal E. Bryant",
            isbn: "9787111544937",
            publisher: "机械工业出版社",
            verifyStatus: .matched
        ))
        BookRow(book: Book(
            id: 2,
            title: "算法导论",
            author: "Thomas H. Cormen",
            verifyStatus: .uncertain
        ))
        BookRow(book: Book(
            id: 3,
            title: "未知书名",
            verifyStatus: .notFound
        ))
    }
}
