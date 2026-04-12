import SwiftUI

/// 箱子列表视图
struct BoxListView: View {
    @State private var boxes: [Box] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxHeight: .infinity)
            } else if boxes.isEmpty {
                ContentUnavailableView("暂无箱子", systemImage: "shippingbox")
            } else {
                List(boxes) { box in
                    NavigationLink(value: box) {
                        boxRow(box)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: Box.self) { box in
                    BoxDetailView(box: box)
                }
            }
        }
        .task {
            await loadBoxes()
        }
        .refreshable {
            await loadBoxes()
        }
    }

    private func boxRow(_ box: Box) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(box.name)
                    .font(.body.weight(.medium))
                Text(box.boxUid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(box.bookCount) 本")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func loadBoxes() async {
        isLoading = true
        do {
            boxes = try await NetworkService.shared.fetchBoxes()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        BoxListView()
    }
}
