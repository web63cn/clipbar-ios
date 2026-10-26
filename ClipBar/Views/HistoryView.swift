import SwiftUI

/// 历史列表。
///
/// iOS 上没有全局悬浮窗，所以历史只能在 App 内看。
/// 剪贴板内容靠「手动读取」按钮采集（系统限制，无法后台监听）。
struct HistoryView: View {
    @EnvironmentObject private var store: ClipStore
    @EnvironmentObject private var cloud: CloudSync
    @State private var showingCopied = false

    var body: some View {
        NavigationStack {
            List {
                if store.items.isEmpty {
                    ContentUnavailableView {
                        Label("还没有记录", systemImage: "tray")
                    } description: {
                        Text("点下面的按钮读取当前剪贴板，或等云端同步下来")
                    } actions: {
                        Button("读取剪贴板") { capture() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(store.items) { item in
                        row(item)
                    }
                    .onDelete { store.remove(at: $0) }
                }
            }
            .navigationTitle("剪贴板历史")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        capture()
                    } label: {
                        Label("读取剪贴板", systemImage: "doc.on.clipboard")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        cloud.syncNow()
                    } label: {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!cloud.enabled)
                }
            }
            .safeAreaInset(edge: .bottom) {
                statusBar
            }
            .overlay(alignment: .center) {
                if showingCopied {
                    Text("已复制到剪贴板")
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.opacity)
                }
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        Button {
            store.copyToPasteboard(item)
            withAnimation { showingCopied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { showingCopied = false }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.preview)
                        .lineLimit(2)
                        .font(.body)
                    HStack(spacing: 8) {
                        Text(item.kind.label)
                        Text(Format.relative(item.date))
                        if item.byteCount > 0 {
                            Text(Format.size(item.byteCount))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusBar: some View {
        HStack {
            Text(cloud.state.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.items.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func capture() {
        if store.captureFromPasteboard() == nil {
            // 剪贴板是空的或只有图片
            if UIPasteboard.general.hasImages {
                let msg = "剪贴板里是图片，iOS 版只存文字"
                print(msg)
            }
        }
    }
}
