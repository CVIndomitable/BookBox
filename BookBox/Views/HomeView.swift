import SwiftUI

/// 主页 — Tab 导航，包含扫描入口、书库、设置
struct HomeView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ScanEntryView()
                .tabItem {
                    Label("扫描", systemImage: "camera.viewfinder")
                }
                .tag(0)

            LibraryView()
                .tabItem {
                    Label("书库", systemImage: "books.vertical")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(2)
        }
    }
}

/// 扫描入口页 — 选择预分类或装箱模式
struct ScanEntryView: View {
    @State private var showPreClassify = false
    @State private var showBoxing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                Image(systemName: "book.closed")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)

                Text("BookBox")
                    .font(.largeTitle.bold())

                Text("拍照识别书籍，轻松整理装箱")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    Button {
                        showPreClassify = true
                    } label: {
                        ModeCard(
                            icon: "rectangle.split.3x1",
                            title: "预分类模式",
                            subtitle: "快速浏览和分类书籍",
                            color: .blue
                        )
                    }

                    Button {
                        showBoxing = true
                    } label: {
                        ModeCard(
                            icon: "shippingbox",
                            title: "装箱模式",
                            subtitle: "录入书籍并关联到物理箱子",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()
                Spacer()
            }
            .navigationTitle("")
            .fullScreenCover(isPresented: $showPreClassify) {
                NavigationStack {
                    PreClassifyView()
                }
                .withVoiceAssistant()
            }
            .fullScreenCover(isPresented: $showBoxing) {
                NavigationStack {
                    BoxingView()
                }
                .withVoiceAssistant()
            }
        }
    }
}

/// 模式选择卡片
struct ModeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 50, height: 50)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HomeView()
}
