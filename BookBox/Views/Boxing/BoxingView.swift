import SwiftUI

/// 装箱模式主界面 — 选择箱子 → 拍照 → 识别校验 → 入箱
struct BoxingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var boxes: [Box] = []
    @State private var selectedBox: Box?
    @State private var showBoxCreate = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var scanResults: [ScanResultItem] = []
    @State private var isProcessing = false
    @State private var isLoadingBoxes = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 箱子选择区域
            boxSelector

            Divider()

            // 扫描结果区域
            if scanResults.isEmpty && !isProcessing {
                emptyStateView
            } else if isProcessing {
                processingView
            } else {
                ScanResultView(
                    results: $scanResults,
                    box: selectedBox
                )
            }
        }
        .navigationTitle("装箱")
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
                .disabled(selectedBox == nil)
            }
        }
        .sheet(isPresented: $showBoxCreate) {
            NavigationStack {
                BoxCreateView { newBox in
                    boxes.append(newBox)
                    selectedBox = newBox
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
        .task {
            await loadBoxes()
        }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var boxSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 新建箱子按钮
                Button {
                    showBoxCreate = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title3)
                        Text("新建")
                            .font(.caption)
                    }
                    .frame(width: 70, height: 60)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if isLoadingBoxes {
                    ProgressView()
                        .frame(width: 70, height: 60)
                } else {
                    ForEach(boxes) { box in
                        Button {
                            selectedBox = box
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "shippingbox")
                                    .font(.title3)
                                Text(box.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(width: 70, height: 60)
                            .background(selectedBox?.id == box.id ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedBox?.id == box.id ? Color.accentColor : .clear, lineWidth: 2)
                            )
                        }
                        .tint(.primary)
                    }
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(
                selectedBox == nil ? "请先选择箱子" : "拍摄书脊",
                systemImage: selectedBox == nil ? "shippingbox" : "camera.viewfinder"
            )
        } description: {
            Text(selectedBox == nil
                 ? "选择一个箱子或新建箱子后开始装箱"
                 : "拍照识别书名后自动联网校验")
        } actions: {
            if selectedBox == nil {
                Button("新建箱子") {
                    showBoxCreate = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("开始拍照") {
                    showCamera = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在识别并校验...")
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func loadBoxes() async {
        isLoadingBoxes = true
        do {
            boxes = try await NetworkService.shared.fetchBoxes()
        } catch {
            errorMessage = "加载箱子列表失败: \(error.localizedDescription)"
        }
        isLoadingBoxes = false
    }

    private func processImage(_ image: UIImage) {
        guard selectedBox != nil else { return }
        isProcessing = true

        Task {
            do {
                // 1. OCR 识别
                let blocks = try await OCRService.shared.recognizeText(from: image)
                // 2. 提取书名
                let titles = BookExtractor.shared.extractTitles(from: blocks)
                // 3. 联网校验每个书名
                let region = (try? await NetworkService.shared.fetchSettings().regionMode) ?? .mainland
                for title in titles {
                    let item = ScanResultItem(
                        extractedTitle: title,
                        verifyResult: nil,
                        isVerifying: true
                    )
                    scanResults.append(item)
                    let index = scanResults.count - 1

                    // 异步校验
                    Task {
                        do {
                            let result = try await NetworkService.shared.verifyBook(
                                title: title.title,
                                region: region
                            )
                            if index < scanResults.count {
                                scanResults[index].verifyResult = result
                                scanResults[index].isVerifying = false
                            }
                        } catch {
                            if index < scanResults.count {
                                scanResults[index].isVerifying = false
                            }
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
            capturedImage = nil
        }
    }
}

/// 扫描结果条目 — 包含提取的书名和校验结果
struct ScanResultItem: Identifiable {
    let id = UUID()
    let extractedTitle: ExtractedTitle
    var verifyResult: VerifyResult?
    var isVerifying: Bool
    var isSelected = true

    /// 最终使用的书名（校验结果优先）
    var finalTitle: String {
        verifyResult?.title ?? extractedTitle.title
    }

    /// 校验状态
    var status: VerifyStatus {
        verifyResult?.status ?? .notFound
    }
}

#Preview {
    NavigationStack {
        BoxingView()
    }
}
