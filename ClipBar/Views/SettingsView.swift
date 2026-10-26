import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ClipStore
    @EnvironmentObject private var cloud: CloudSync
    @State private var urlText = ""
    @State private var showingKeyboardHelp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("启用云端同步", isOn: Binding(
                        get: { cloud.enabled },
                        set: { cloud.enabled = $0; cloud.saveConfig() }
                    ))
                    if cloud.enabled {
                        TextField("服务器地址", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("保存地址并立即同步") {
                            cloud.serverURL = urlText
                            cloud.saveConfig()
                            cloud.syncNow()
                        }
                    }
                    LabeledContent("状态", value: cloud.state.statusText)
                } header: {
                    Text("互联网同步")
                } footer: {
                    Text("与 Mac / Windows 端共用同一套加密协议，内容在客户端加密后才上传，服务器只存密文。")
                }

                Section {
                    LabeledContent("共享机制", value: store.mechanism)
                    LabeledContent("上限", value: "\(store.items.count) / \(store.maxItems) 条")
                    Button("清空历史") {
                        store.removeAll()
                    }
                    .foregroundStyle(.red)
                } header: {
                    Text("本机")
                } footer: {
                    Text(store.mechanism.hasPrefix("剪贴板桥")
                         ? "当前用剪贴板桥共享（免费账号限制）。首次在键盘里打开历史面板时，系统会弹一次「粘贴自 ClipBar」的提示，允许后不再出现。"
                         : "当前用 App Group 共享，扩展与应用直接共享沙盒。")
                }

                Section {
                    Button("如何启用键盘扩展") { showingKeyboardHelp = true }
                } header: {
                    Text("键盘扩展")
                } footer: {
                    Text("启用后可以在任意 App 的输入框里，从历史中挑一条直接插入。")
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4")
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("设置")
            .onAppear { urlText = cloud.serverURL }
            .sheet(isPresented: $showingKeyboardHelp) {
                KeyboardHelpView()
            }
        }
    }
}

struct KeyboardHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "打开「设置 → 通用 → 键盘 → 键盘」")
                    step(2, "点右上角「添加新键盘…」，选 ClipBar")
                    step(3, "回到任何输入框，长按左下角的地球图标，选 ClipBar 键盘")
                    step(4, "在键盘上方点「历史」按钮，就能从列表里挑一条插入")

                    Divider()

                    Text("注意")
                        .font(.headline)
                    Text("· 首次打开历史面板时，系统会弹「ClipBar 粘贴自 ClipBar」的提示 —— 这是 iOS 读取剪贴板的固定行为，绕不过去。")
                    Text("· 不想看到提示：设置 → 隐私与安全性 → 粘贴板 → ClipBar → 选「完全允许」。")
                    Text("· 键盘扩展只能读主 App 发布的历史，两边数据靠系统剪贴板中转。")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("启用键盘扩展")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
