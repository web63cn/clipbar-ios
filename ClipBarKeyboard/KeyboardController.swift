import UIKit
import SwiftUI

/// 键盘扩展。
///
/// 这是 iOS 上**唯一**能替代桌面端「点记录自动粘贴」的能力：
/// 桌面端往目标 App 发合成 ⌘V，iOS 没这权限；
/// 但键盘扩展可以直接 `insertText` 到当前光标处，效果等价。
///
/// 数据来源：主 App 通过「共享机制」发布的历史。
/// 免费账号（无 App Group）时走剪贴板桥，读取会触发一次系统粘贴提示。
final class KeyboardController: UIInputViewController {

    private var host: UIHostingController<KeyboardRootView>?
    private var items: [ClipItem] = []
    private let shared: SharedStore = SharedStoreFactory.make()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    private func setupUI() {
        // 输入视图的高度：给历史列表留出空间
        let height: CGFloat = 240
        let inputView = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: height))
        inputView.allowsSelfSizing = true

        let root = KeyboardRootView(
            items: items,
            onPick: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onSave: { [weak self] text in
                // 存回主 App（走共享通道），主 App 下次前台时收走
                self?.shared.enqueueCapture(text)
            },
            onRefresh: { [weak self] in
                self?.refresh()
            },
            onDelete: { [weak self] fp in
                self?.shared.enqueueCapture("__delete__:\(fp)")
            },
            onNextKeyboard: { [weak self] in
                // 切换到下一个键盘必须在 UIInputViewController 上调用
                // （SwiftUI 的 View 上下文里没有这个方法）
                self?.advanceToNextInputMode()
            }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        inputView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: inputView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)
        ])
        addChild(host)
        host.didMove(toParent: self)
        self.host = host
        self.inputView = inputView
    }

    private func refresh() {
        items = shared.readPublishedHistory()
        // 通知 SwiftUI 刷新
        NotificationCenter.default.post(name: .clipBarKeyboardDataChanged, object: nil)
    }
}

extension Notification.Name {
    static let clipBarKeyboardDataChanged = Notification.Name("clipBarKeyboardDataChanged")
}

/// 键盘面板的 SwiftUI 界面
struct KeyboardRootView: View {
    let items: [ClipItem]
    let onPick: (String) -> Void
    let onSave: (String) -> Void
    let onRefresh: () -> Void
    let onDelete: (String) -> Void
    let onNextKeyboard: () -> Void

    @State private var mode: Mode = .history
    @State private var currentItems: [ClipItem] = []

    enum Mode { case history, save }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .onAppear { currentItems = items }
        .onReceive(NotificationCenter.default.publisher(for: .clipBarKeyboardDataChanged)) { _ in
            currentItems = items
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                mode = .history
            } label: {
                Label("历史", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(mode == .history ? .accentColor : .secondary)

            Button {
                mode = .save
            } label: {
                Label("存剪贴板", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(mode == .save ? .accentColor : .secondary)

            Spacer()

            Button {
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.bordered)

            Button {
                onNextKeyboard()
            } label: {
                Image(systemName: "globe").font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .history:
            if currentItems.isEmpty {
                emptyHint("主 App 里还没有历史。先在 ClipBar App 里同步或读取剪贴板。")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(currentItems) { item in
                            Button {
                                onPick(item.text ?? item.preview)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.kind.symbol)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 16)
                                    Text(item.preview)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        case .save:
            savePanel
        }
    }

    private var savePanel: some View {
        VStack(spacing: 10) {
            Text("把当前剪贴板存进历史")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                if let text = UIPasteboard.general.string, !text.isEmpty {
                    onSave(text)
                }
            } label: {
                Label("读取剪贴板并存入", systemImage: "tray.and.arrow.down")
                    .font(.footnote)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .padding(12)
    }

    private func emptyHint(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
