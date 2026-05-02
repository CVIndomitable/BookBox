import SwiftUI

/// 供应商降级横幅：当顶级 AI 供应商失败、已自动切换到备用时显示
struct SupplierDegradationBanner: View {
    @ObservedObject var store = SupplierStatusStore.shared

    var body: some View {
        if store.shouldShowBanner, let meta = store.currentDegradation {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .font(.callout)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 服务已降级")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(meta.degradationMessage)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(3)
                }

                Spacer(minLength: 4)

                Button {
                    store.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.orange.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: store.shouldShowBanner)
        }
    }
}
