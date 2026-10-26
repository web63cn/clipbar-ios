import Foundation
import Security

/// 互联网同步（云端中转）。
///
/// 协议与桌面端（CBCloudSync.m）完全一致：
/// - deviceKey 只用于**鉴权**，各设备独立
/// - groupKey 用于**内容加密**，所有设备共用（服务端从主密钥派生后下发）
/// - 密文格式 nonce(12)||tag(16)||ciphertext，AAD = "pv:<fp>" / "bd:<fp>"
///
/// iOS 端没有后台常驻能力，所以：
/// - 只在前台时同步（用户切回 App、或从分享面板进入）
/// - 首次同步会拿到 groupKey，之后缓存在 Keychain
final class CloudSync: ObservableObject {

    enum State: Equatable {
        case off
        case idle
        case syncing
        case ok(String)
        case failed(String)

        var statusText: String {
            switch self {
            case .off: return "未启用"
            case .idle: return "待同步"
            case .syncing: return "正在同步…"
            case .ok(let s): return s
            case .failed(let s): return "同步失败：\(s)"
            }
        }
    }

    @Published var state: State = .off
    @Published var serverURL: String = ""
    @Published var enabled: Bool = false

    private let store: ClipStore
    private let session: URLSession
    private var syncing = false

    // MARK: - 密钥管理（Keychain 持久化）

    private let service = "com.clipbar.ios.keys"

    private func saveKey(_ key: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = key
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadKey(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }

    /// 设备密钥（鉴权用，各设备独立）
    private var deviceKey: Data {
        if let k = loadKey(account: "device") { return k }
        let k = AES.randomKey()
        saveKey(k, account: "device")
        return k
    }

    /// 设备 ID
    private var deviceId: String {
        if let s = loadKey(account: "deviceId"),
           let str = String(data: s, encoding: .utf8) { return str }
        let s = UUID().uuidString
        saveKey(Data(s.utf8), account: "deviceId")
        return s
    }

    /// 群组密钥（内容加密用，所有设备共用）
    private var groupKey: Data? {
        get { loadKey(account: "group") }
        set {
            if let newValue { saveKey(newValue, account: "group") }
        }
    }

    // MARK: - 初始化

    init(store: ClipStore) {
        self.store = store
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: cfg)

        let defaults = UserDefaults.standard
        self.serverURL = defaults.string(forKey: "clipbar.ios.serverURL") ?? "http://web63.cn/clip/clip.php"
        self.enabled = defaults.bool(forKey: "clipbar.ios.cloudEnabled")
    }

    func saveConfig() {
        let defaults = UserDefaults.standard
        defaults.set(serverURL, forKey: "clipbar.ios.serverURL")
        defaults.set(enabled, forKey: "clipbar.ios.cloudEnabled")
    }

    // MARK: - 同步

    func syncNow() {
        guard enabled else { state = .off; return }
        guard !syncing else { return }
        guard let base = URL(string: serverURL) else {
            state = .failed("服务器地址无效")
            return
        }
        syncing = true
        state = .syncing

        var req = URLRequest(url: base.appendingPathComponent("sync"))
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName,
            "deviceKey": deviceKey.base64EncodedString(),
            "items": buildUploadItems(),
            "tombstones": []
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            DispatchQueue.main.async {
                self.syncing = false
                if let err {
                    self.state = .failed(err.localizedDescription); return
                }
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    self.state = .failed("服务器返回 \(code)"); return
                }
                guard let data,
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.state = .failed("响应格式错误"); return
                }
                self.handle(result)
            }
        }.resume()
    }

    /// 服务端下发群组密钥
    private func handle(_ result: [String: Any]) {
        if let gk = result["groupKey"] as? String,
           let data = Data(base64Encoded: gk), data.count == 32 {
            groupKey = data
        }
        // 解析远端条目
        var remote: [ClipItem] = []
        if let items = result["items"] as? [[String: Any]] {
            remote = items.compactMap { parseRemote($0) }
        }
        let changed = store.merge(remote: remote)
        self.state = .ok(changed ? "同步完成（有更新）" : "同步完成")
    }

    /// 解析远端条目（解密）
    private func parseRemote(_ dict: [String: Any]) -> ClipItem? {
        guard let fp = dict["fp"] as? String,
              let kindRaw = dict["kind"] as? Int,
              let kind = ClipKind(rawValue: kindRaw) else { return nil }
        let date = Date(timeIntervalSince1970: dict["date"] as? Double ?? 0)

        var preview = ""
        var text: String?

        if let pvEnc = dict["previewEnc"] as? String,
           let blob = Data(base64Encoded: pvEnc),
           let key = groupKey,
           let plain = AES.decrypt(blob, key: key, aad: AES.aad("pv", fp)) {
            preview = String(data: plain, encoding: .utf8) ?? ""
        }
        if let bdEnc = dict["bodyEnc"] as? String,
           let blob = Data(base64Encoded: bdEnc),
           let key = groupKey,
           let plain = AES.decrypt(blob, key: key, aad: AES.aad("bd", fp)) {
            if let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] {
                text = obj["text"] as? String
            }
        }
        if preview.isEmpty { preview = Format.oneLine(text ?? "", limit: 200) }
        return ClipItem(id: fp, kind: kind, date: date, preview: preview,
                        fingerprint: fp, text: text,
                        uti: nil, data: nil, imageFileName: nil)
    }

    /// 构造要上传的条目（加密）
    private func buildUploadItems() -> [[String: Any]] {
        guard let key = groupKey else { return [] }
        var out: [[String: Any]] = []
        for item in store.items {
            let fp = item.fingerprint
            let pv = Data(item.preview.utf8)
            guard let pvEnc = AES.encrypt(pv, key: key, aad: AES.aad("pv", fp)) else { continue }
            var body: [String: Any] = ["text": item.text ?? ""]
            if let uti = item.uti { body["uti"] = uti }
            let bodyJson = try? JSONSerialization.data(withJSONObject: body)
            guard let bodyJson,
                  let bdEnc = AES.encrypt(bodyJson, key: key, aad: AES.aad("bd", fp)) else { continue }
            out.append([
                "fp": fp,
                "kind": item.kind.rawValue,
                "payload": 1,
                "date": item.date.timeIntervalSince1970,
                "previewEnc": pvEnc.base64EncodedString(),
                "bodyEnc": bdEnc.base64EncodedString()
            ])
        }
        return out
    }

    private var deviceName: String {
        #if targetEnvironment(simulator)
        return "iOS 模拟器"
        #else
        return ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        #endif
    }
}
