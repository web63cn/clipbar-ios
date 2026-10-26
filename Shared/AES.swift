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
enum AES {

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
            let sealed = try AES.GCM.seal(plain, using: symmetricKey, authenticating: aad ?? Data())
            guard let combined = sealed.combined else { return nil }
            // combined = nonce(12) || ciphertext || tag(16)
            let nonce = combined.prefix(12)
            let tag = combined.suffix(16)
            let ct = combined.dropFirst(12).dropLast(16)
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
            let nonce = blob.prefix(12)
            let tag = blob.subdata(in: 12..<28)
            let ct = blob.subdata(in: 28..<blob.count)
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce),
                                             ciphertext: ct,
                                             tag: tag)
            return try AES.GCM.open(box, using: symmetricKey, authenticating: aad ?? Data())
        } catch {
            return nil
        }
    }

    /// AAD 构造：与桌面端 `aadFor:fp:` 保持一致
    static func aad(_ prefix: String, _ fp: String) -> Data {
        Data("\(prefix):\(fp)".utf8)
    }
}
