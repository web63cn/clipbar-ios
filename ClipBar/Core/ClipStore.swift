import Foundation
import UIKit

/// 本地历史存储。
///
/// 与桌面端一致：50 条上限，fp 去重，date 新的胜出。
/// 用 UserDefaults 存（数据量小，50 条文本撑死几百 KB）。
final class ClipStore: ObservableObject {

    static let shared = ClipStore()

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var maxItems = 50

    private let defaultsKey = "clipbar.ios.history"
    private let shared: SharedStore
    private let queue = DispatchQueue(label: "com.clipbar.ios.store")

    init(shared: SharedStore = SharedStoreFactory.make()) {
        self.shared = shared
        load()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data)
        else { return }
        items = decoded.sorted { $0.date > $1.date }
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - 增删改

    /// 加入一条（fp 相同则保留 date 更新的）
    @discardableResult
    func add(_ item: ClipItem) -> Bool {
        var changed = false
        queue.sync {
            if let idx = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
                if item.date > items[idx].date {
                    items[idx] = item
                    changed = true
                }
            } else {
                items.insert(item, at: 0)
                changed = true
            }
            if items.count > maxItems {
                items = Array(items.prefix(maxItems))
            }
        }
        if changed {
            DispatchQueue.main.async { self.publish() }
        }
        return changed
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        publish()
    }

    func removeAll() {
        items.removeAll()
        publish()
    }

    /// 合并远端条目（同步用）
    @discardableResult
    func merge(remote: [ClipItem]) -> Bool {
        var changed = false
        queue.sync {
            for item in remote {
                if let idx = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
                    if item.date > items[idx].date {
                        items[idx] = item
                        changed = true
                    }
                } else {
                    items.append(item)
                    changed = true
                }
            }
            items.sort { $0.date > $1.date }
            if items.count > maxItems {
                items = Array(items.prefix(maxItems))
                changed = true
            }
        }
        if changed {
            DispatchQueue.main.async { self.publish() }
        }
        return changed
    }

    /// 把历史写给键盘扩展
    func publish() {
        save()
        shared.publishHistory(items)
    }

    /// 取走键盘扩展归档的内容
    func drainCaptures() -> [ClipItem] {
        shared.drainCaptures().map { text in
            ClipItem(kind: .text, date: Date(),
                     preview: Format.oneLine(text, limit: 200),
                     fingerprint: ClipItem.fingerprint(text: text),
                     text: text)
        }
    }

    // MARK: - 剪贴板读取

    /// 读取当前系统剪贴板并存进历史。
    ///
    /// ⚠️ iOS 16+ 读取剪贴板会弹「XX 粘贴自 XX」的系统提示，
    ///    这是系统行为，绕不过去。
    ///    用户可在「设置 → 隐私与安全性 → 粘贴板 → ClipBar」里允许，
    ///    之后就不会反复提示。
    @discardableResult
    func captureFromPasteboard() -> ClipItem? {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return nil }
        let item = ClipItem(kind: .text, date: Date(),
                            preview: Format.oneLine(text, limit: 200),
                            fingerprint: ClipItem.fingerprint(text: text),
                            text: text)
        add(item)
        return item
    }

    /// 写回剪贴板（用户自己再去目标 app 粘贴）
    func copyToPasteboard(_ item: ClipItem) {
        if let text = item.text {
            UIPasteboard.general.string = text
        }
    }

    /// 共享机制说明（设置页显示）
    var mechanism: String { shared.mechanismDescription }
}
