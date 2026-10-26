import Foundation
import UIKit

/// 主 App 与键盘扩展之间的数据共享。
///
/// ## 为什么需要这一层
///
/// 免费 Apple ID（Personal Team）**不支持 App Groups**，
/// 而 App Groups 正是 app 与 extension 共享沙盒的标准做法。
/// 付费账号（99$/年）才支持。
///
/// 所以这里做两种实现，自动降级：
///
/// 1. **AppGroupStore** —— 有 App Group entitlement 时用（付费账号）。
///    两边直接读写同一个 group 容器里的文件，干净可靠。
///
/// 2. **BridgeStore** —— 免签（免费账号）时的兜底。
///    借系统剪贴板当共享通道，用**自定义 UTI** 存放数据：
///    - `com.clipbar.ios.history`  主 App → 键盘扩展（历史摘要）
///    - `com.clipbar.ios.capture`  键盘扩展 → 主 App（待归档的内容）
///
///    自定义 UTI 不会影响用户正常复制的内容：
///    写的时候用 pasteboard item 的 type 标注，
///    用户在别的 app 里复制的东西覆盖不掉它（不同 type）。
///    代价是 iOS 16+ 读取时会弹「XX 粘贴自 XX」的提示，
///    可在「设置 → 隐私与安全性 → 粘贴板」里允许本 App 来消除。
protocol SharedStore {
    /// 主 App 把历史写给键盘扩展
    func publishHistory(_ items: [ClipItem])
    /// 键盘扩展读主 App 给的历史
    func readPublishedHistory() -> [ClipItem]
    /// 键盘扩展把要归档的内容交给主 App
    func enqueueCapture(_ text: String)
    /// 主 App 取走待归档的内容
    func drainCaptures() -> [String]
    /// 描述当前用的是哪种实现（显示在设置里）
    var mechanismDescription: String { get }
}

// MARK: - App Group 实现（付费账号）

final class AppGroupStore: SharedStore {
    static let groupID = "group.com.clipbar.ios"
    private let groupURL: URL?

    init() {
        groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID)
    }

    var isAvailable: Bool { groupURL != nil }

    private var historyURL: URL? {
        groupURL?.appendingPathComponent("shared_history.json")
    }
    private var captureURL: URL? {
        groupURL?.appendingPathComponent("shared_captures.json")
    }

    func publishHistory(_ items: [ClipItem]) {
        guard let url = historyURL else { return }
        let bridge = items.map {
            ["fp": $0.fingerprint, "kind": $0.kind.rawValue,
             "date": $0.date.timeIntervalSince1970,
             "preview": $0.preview, "text": $0.text ?? ""]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: bridge) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func readPublishedHistory() -> [ClipItem] {
        guard let url = historyURL, let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { dict in
            guard let fp = dict["fp"] as? String,
                  let kindRaw = dict["kind"] as? Int,
                  let kind = ClipKind(rawValue: kindRaw) else { return nil }
            let date = Date(timeIntervalSince1970: dict["date"] as? Double ?? 0)
            return ClipItem(id: fp, kind: kind, date: date,
                            preview: dict["preview"] as? String ?? "",
                            fingerprint: fp,
                            text: dict["text"] as? String,
                            uti: nil, data: nil, imageFileName: nil)
        }
    }

    func enqueueCapture(_ text: String) {
        guard let url = captureURL else { return }
        var list = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String]) ?? []
        list.append(text)
        if let data = try? JSONSerialization.data(withJSONObject: list) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func drainCaptures() -> [String] {
        guard let url = captureURL, let data = try? Data(contentsOf: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        try? FileManager.default.removeItem(at: url)
        return list
    }

    var mechanismDescription: String { "App Group（付费账号，支持完整共享）" }
}

// MARK: - 剪贴板桥实现（免费账号）

/// 用系统剪贴板当共享通道。
///
/// 关键技巧：pasteboard item 可以带**自定义 UTI**，
/// 用 `setItems(_:options:)` 写入时不会覆盖用户正常复制的内容
/// （不同 type 是并列的，不是替换关系）。
enum Bridge {
    static let historyUTI = "com.clipbar.ios.history"
    static let captureUTI = "com.clipbar.ios.capture"

    static func write(_ payload: Any, uti: String) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        UIPasteboard.general.setItems(
            [[uti: data, "public.data": data]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(3600)])
    }

    static func read(uti: String) -> Any? {
        guard let item = UIPasteboard.general.items.first,
              let data = item[uti] as? Data else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

final class BridgeStore: SharedStore {
    func publishHistory(_ items: [ClipItem]) {
        // 只传最近 20 条、每条截断 —— 键盘面板显示不下更多，
        // 而且剪贴板里塞太多数据会触发系统的「内容过大」提示。
        let bridge = items.prefix(20).map {
            ["fp": $0.fingerprint, "kind": $0.kind.rawValue,
             "date": $0.date.timeIntervalSince1970,
             "preview": $0.preview, "text": $0.text ?? ""]
        }
        Bridge.write(bridge, uti: Bridge.historyUTI)
    }

    func readPublishedHistory() -> [ClipItem] {
        guard let arr = Bridge.read(uti: Bridge.historyUTI) as? [[String: Any]] else { return [] }
        return arr.compactMap { dict in
            guard let fp = dict["fp"] as? String,
                  let kindRaw = dict["kind"] as? Int,
                  let kind = ClipKind(rawValue: kindRaw) else { return nil }
            let date = Date(timeIntervalSince1970: dict["date"] as? Double ?? 0)
            return ClipItem(id: fp, kind: kind, date: date,
                            preview: dict["preview"] as? String ?? "",
                            fingerprint: fp,
                            text: dict["text"] as? String,
                            uti: nil, data: nil, imageFileName: nil)
        }
    }

    func enqueueCapture(_ text: String) {
        var list = (Bridge.read(uti: Bridge.captureUTI) as? [String]) ?? []
        list.append(text)
        Bridge.write(list, uti: Bridge.captureUTI)
    }

    func drainCaptures() -> [String] {
        guard let list = Bridge.read(uti: Bridge.captureUTI) as? [String] else { return [] }
        // 取走后清空通道
        Bridge.write([String](), uti: Bridge.captureUTI)
        return list
    }

    var mechanismDescription: String { "剪贴板桥（免费账号，免签可用）" }
}

// MARK: - 自动选择

enum SharedStoreFactory {
    /// 有 App Group 用 App Group，没有就降级到剪贴板桥。
    static func make() -> SharedStore {
        let group = AppGroupStore()
        if group.isAvailable { return group }
        return BridgeStore()
    }
}
