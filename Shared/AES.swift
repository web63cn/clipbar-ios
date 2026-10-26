import Foundation
import CryptoKit

/// AES-256-GCM 加解密。
///
/// ⚠️ 密文格式必须和桌面端（CBAES.m）完全一致，否则两端解不开：
///     nonce(12) || tag(16) || ciphertext
///
/// 而 CryptoKit 的 `combined` 是 nonce||ciphertext||tag（tag 在后），
/// 所以这里手工重排字节顺序。
///
/// AAD（附加认证数据）把密文绑定到内容指纹，
/// 防止攻击者把一条内容的密文换到另一条上。
///
/// ⚠️ 名字故意不叫 `AES` —— 那会遮蔽 CryptoKit 的 `AES.GCM`，
///    编译器会把 `AES.GCM.seal` 解析成自己的类型，报
///    "type 'AES' has no member 'GCM'"。
enum ClipAES {

    static func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// 加密。返回 nonce||tag||ciphertext，失败返回 nil
    static func encrypt(_ plain: Data, key: Data, aad: Data?) -> Data? {
        guard key.count == 32 else { return nil }
        do {
            let symmetricKey = SymmetricKey(data: key)
            let sealed = try CryptoKit.AES.GCM.seal(plain, using: symmetricKey,
                                                  authenticating: aad ?? Data())
            guard let combined = sealed.combined else { return nil }
            // combined = nonce(12) || ciphertext || tag(16)
            // 桌面端布局 = nonce(12) || tag(16) || ciphertext → 这里重排
            // 注意要显式转成 Data：prefix/suffix 返回的是 SubSequence，
            // 直接相加会报类型不匹配。
            let nonce = Data(combined.prefix(12))
            let tag = Data(combined.suffix(16))
            let ct = Data(combined.dropFirst(12).dropLast(16))
            return nonce + tag + ct
        } catch {
            return nil
        }
    }

    /// 解密。失败返回 nil
    static func decrypt(_ blob: Data, key: Data, aad: Data?) -> Data? {
        guard key.count == 32, blob.count > 28 else { return nil }
        do {
            let symmetricKey = SymmetricKey(data: key)
            let nonce = Data(blob.prefix(12))
            let tag = Data(blob.subdata(in: 12..<28))
            let ct = Data(blob.subdata(in: 28..<blob.count))
            let box = try CryptoKit.AES.GCM.SealedBox(
                nonce: CryptoKit.AES.GCM.Nonce(data: nonce),
                ciphertext: ct,
                tag: tag)
            return try CryptoKit.AES.GCM.open(box, using: symmetricKey,
                                              authenticating: aad ?? Data())
        } catch {
            return nil
        }
    }

    /// AAD 构造：与桌面端 `aadFor:fp:` 保持一致
    static func aad(_ prefix: String, _ fp: String) -> Data {
        Data("\(prefix):\(fp)".utf8)
    }
}
