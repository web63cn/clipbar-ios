import Foundation
import CryptoKit

/// 剪贴板条目的内容种类（与桌面端 CBKind 一致，值不能改）
enum ClipKind: Int, Codable {
    case text = 0
    case rich = 1
    case image = 2
    case file = 3
    case color = 4
    case data = 5

    var label: String {
        switch self {
        case .text: return "文字"
        case .rich: return "富文本"
        case .image: return "图片"
        case .file: return "文件"
        case .color: return "颜色"
        case .data: return "数据"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .rich: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .data: return "shippingbox"
        }
    }
}

/// 一个剪贴板条目。
///
/// ⚠️ `fingerprint` 必须与桌面端算出来的一致，否则同步时对不上，
///    会导致同一条内容在两端被当成两条。
struct ClipItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var kind: ClipKind
    var date: Date
    /// 列表主标题（可能很长）
    var preview: String
    /// 去重指纹（24 位十六进制）
    var fingerprint: String
    /// 纯文本 / 富文本回退
    var text: String?
    /// 富文本、图片、原始数据的 UTI
    var uti: String?
    /// 富文本 / 颜色 / 原始数据（base64）
    var data: Data?
    /// 图片在缓存目录中的文件名
    var imageFileName: String?

    /// 内容指纹：SHA256 前 12 字节 → 24 位十六进制（与桌面端一致）
    static func fingerprint(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// 纯文本的指纹基准：UTF-8 字节
    static func fingerprint(text: String) -> String {
        fingerprint(of: Data(text.utf8))
    }

    /// 单行摘要
    var compactText: String {
        preview.isEmpty ? (text ?? "") : preview
    }

    /// 完整原文
    var fullText: String? {
        text
    }

    /// 载荷字节数
    var byteCount: Int {
        if let data { return data.count }
        if let text { return text.utf8.count }
        return 0
    }
}

// MARK: - 格式化工具

enum Format {

    static func size(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        if delta < 86400 { return "\(Int(delta / 3600)) 小时前" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    /// 单行化：换行转空格，压缩空白
    static func oneLine(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        var out = ""
        var lastWasSpace = false
        for ch in collapsed {
            if ch == " " {
                if !lastWasSpace { out.append(ch) }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
            if out.count >= limit { break }
        }
        return String(out.prefix(limit))
    }
}
