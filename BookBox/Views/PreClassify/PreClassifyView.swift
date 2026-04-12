import SwiftUI

/// 预分类模式 — 拍照识别书籍并快速分类
struct PreClassifyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var extractedTitles: [ExtractedTitle] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if extractedTitles.isEmpty && !isProcessing {
                // 空状态 — 提示拍照
                emptyStateView
            } else if isProcessing {
                // 正在处理
                processingView
            } else {
                // 识别结果列表
                ClassifyResultView(titles: $extractedTitles)
            }
        }
        .navigationTitle("预分类")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关闭") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("拍照", systemImage: "camera") {
                        showCamera = true
                    }
                    Button("从相册选取", systemImage: "photo") {
                        showPhotoPicker = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView(capturedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(selectedImage: $capturedImage)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                processImage(image)
            }
        }
        .alert("识别失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("拍摄书脊或封面", systemImage: "text.viewfinder")
        } description: {
            Text("拍照后自动识别书名并进行分类")
        } actions: {
            Button("开始拍照") {
                showCamera = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在识别文字...")
                .foregroundStyle(.secondary)
        }
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        Task {
            do {
                // OCR 识别
                let blocks = try await OCRService.shared.recognizeText(from: image)
                // 规则式提取书名
                let titles = BookExtractor.shared.extractTitles(from: blocks)
                extractedTitles.append(contentsOf: titles)
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
            capturedImage = nil
        }
    }
}

#Preview {
    NavigationStack {
        PreClassifyView()
    }
}
