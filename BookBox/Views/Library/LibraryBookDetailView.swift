import SwiftUI
import PhotosUI

struct LibraryBookDetailView: View {
    let book: Book
    @State private var updatedBook: Book
    @State private var isEditing = false
    @State private var showImagePicker = false
    @State private var selectedImage: PhotosPickerItem?
    @State private var isUploadingCover = false
    @State private var errorMessage: String?
    @State private var showDeleteCoverConfirm = false

    init(book: Book) {
        self.book = book
        _updatedBook = State(initialValue: book)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    coverView
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if !isEditing {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedImage, matching: .images) {
                            Label("更换封面", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)

                        if updatedBook.coverUrl != nil {
                            Button(role: .destructive) {
                                showDeleteCoverConfirm = true
                            } label: {
                                Label("删除封面", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                }
            }

            Section("书籍信息") {
                LabeledContent("书名", value: updatedBook.title)
                if let author = updatedBook.author {
                    LabeledContent("作者", value: author)
                }
                if let isbn = updatedBook.isbn {
                    LabeledContent("ISBN", value: isbn)
                }
                if let publisher = updatedBook.publisher {
                    LabeledContent("出版社", value: publisher)
                }
                if let publishDate = updatedBook.publishDate {
                    LabeledContent("出版日期", value: publishDate)
                }
                if let price = updatedBook.price {
                    LabeledContent("定价", value: "¥\(price)")
                }
            }

            Section("位置信息") {
                LabeledContent("位置类型", value: updatedBook.locationDescription)
                if let libraryId = updatedBook.libraryId {
                    LabeledContent("书库 ID", value: "\(libraryId)")
                }
            }

            if let status = updatedBook.verifyStatus {
                Section("校验状态") {
                    HStack {
                        Text("状态")
                        Spacer()
                        StatusBadge(status: status)
                    }
                    if let source = updatedBook.verifySource {
                        LabeledContent("来源", value: source)
                    }
                }
            }

            if let createdAt = updatedBook.createdAt {
                Section("时间信息") {
                    LabeledContent("创建时间", value: createdAt.formatted())
                    if let updatedAt = updatedBook.updatedAt {
                        LabeledContent("更新时间", value: updatedAt.formatted())
                    }
                }
            }
        }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedImage) { _, newValue in
            if newValue != nil {
                Task { await uploadCover() }
            }
        }
        .alert("删除封面", isPresented: $showDeleteCoverConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { await deleteCover() }
            }
        } message: {
            Text("确定要删除这本书的封面吗？")
        }
        .alert("错误", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if isUploadingCover {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("上传中...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var coverView: some View {
        Group {
            if let coverUrl = updatedBook.coverUrl,
               let url = URL(string: NetworkService.shared.baseURL + coverUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        coverPlaceholder
                    default:
                        ProgressView()
                            .frame(width: 200, height: 280)
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(maxWidth: 200, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 200, height: 280)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("暂无封面")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private func uploadCover() async {
        guard let selectedImage else { return }

        isUploadingCover = true
        defer { isUploadingCover = false }

        do {
            guard let imageData = try await selectedImage.loadTransferable(type: Data.self) else {
                errorMessage = "无法加载图片"
                return
            }

            let compressedData: Data
            if let uiImage = UIImage(data: imageData),
               let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                compressedData = jpegData
            } else {
                compressedData = imageData
            }

            updatedBook = try await NetworkService.shared.uploadCover(
                bookId: book.id,
                imageData: compressedData
            )

            self.selectedImage = nil
        } catch {
            errorMessage = error.chineseDescription
        }
    }

    private func deleteCover() async {
        isUploadingCover = true
        defer { isUploadingCover = false }

        do {
            updatedBook = try await NetworkService.shared.deleteCover(bookId: book.id)
        } catch {
            errorMessage = error.chineseDescription
        }
    }
}
