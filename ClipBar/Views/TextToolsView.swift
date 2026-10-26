import SwiftUI

/// 文本处理工具。
///
/// iOS 上其实比剪贴板历史更实用 —— 手机上没有全局快捷键，
/// 需要随手转换点什么的时候，有个专门的工具比翻历史快。
struct TextToolsView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var selectedTool = Tool.uppercase

    enum Tool: String, CaseIterable, Identifiable {
        case uppercase = "大写"
        case lowercase = "小写"
        case camel = "驼峰"
        case snake = "下划线"
        case kebab = "中划线"
        case trim = "去空白"
        case reverse = "反转"
        case urlEncode = "URL 编码"
        case urlDecode = "URL 解码"
        case base64 = "Base64"
        case jsonPretty = "JSON 格式化"
        case timestamp = "时间戳转换"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴或输入文本", text: $input, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .autocorrectionDisabled()
                } header: {
                    Text("输入")
                }

                Section {
                    Picker("工具", selection: $selectedTool) {
                        ForEach(Tool.allCases) { tool in
                            Text(tool.rawValue).tag(tool)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    if output.isEmpty {
                        Text("结果会显示在这里")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } header: {
                    HStack {
                        Text("结果")
                        Spacer()
                        if !output.isEmpty {
                            Button {
                                UIPasteboard.general.string = output
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                        }
                    }
                }

                if selectedTool == .jsonPretty, let err = jsonError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("文本工具")
            // ⚠️ onChange(of:initial:) 两参数版本要 iOS 17+。
            //    iOS 16 只有 onChange(of:perform:)（单参数）。
            .onChange(of: input) { _ in run() }
            .onChange(of: selectedTool) { _ in run() }
        }
    }

    private var jsonError: String? {
        guard selectedTool == .jsonPretty else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil else {
            return "不是合法的 JSON"
        }
        return nil
    }

    private func run() {
        let text = input
        switch selectedTool {
        case .uppercase: output = text.uppercased()
        case .lowercase: output = text.lowercased()
        case .camel: output = camelCase(text)
        case .snake: output = separated(text, sep: "_")
        case .kebab: output = separated(text, sep: "-")
        case .trim:
            output = text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .reverse: output = String(text.reversed())
        case .urlEncode:
            output = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        case .urlDecode:
            output = text.removingPercentEncoding ?? text
        case .base64:
            output = Data(text.utf8).base64EncodedString()
        case .jsonPretty:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
                  let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                           options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: pretty, encoding: .utf8) else {
                output = ""
                return
            }
            output = str
        case .timestamp:
            output = convertTimestamp(text)
        }
    }

    // MARK: - 辅助

    private func words(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func camelCase(_ text: String) -> String {
        let ws = words(text)
        guard let first = ws.first else { return "" }
        return first.lowercased() + ws.dropFirst().map { w in
            w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined()
    }

    private func separated(_ text: String, sep: String) -> String {
        words(text).map { $0.lowercased() }.joined(separator: sep)
    }

    private func convertTimestamp(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        // 10 位是秒，13 位是毫秒
        if let n = Double(t) {
            let seconds = n > 1_000_000_000_000 ? n / 1000 : n
            let date = Date(timeIntervalSince1970: seconds)
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = TimeZone.current
            return f.string(from: date)
        }
        // 反向：日期 → 时间戳
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        if let date = f.date(from: t) {
            return String(Int(date.timeIntervalSince1970))
        }
        return "无法识别"
    }
}
