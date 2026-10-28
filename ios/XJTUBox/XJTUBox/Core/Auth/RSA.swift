//
//  RSA.swift
//  XJTUBox
//
//  XJTU 统一认证要求把密码用服务端下发的 RSA 公钥做 PKCS#1 v1.5 加密，
//  再以 "__RSA__<base64>" 的形式提交。Security.framework 只接受 PKCS#1 的
//  RSA 公钥 DER，而服务端给的是 X.509 SubjectPublicKeyInfo，所以这里做了
//  一层最小化的 DER 拆包（不引第三方库）。
//

import Foundation
import Security

enum RSAError: LocalizedError {
    case badPEM
    case badDER
    case keyCreationFailed(String)
    case encryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .badPEM: return "服务器公钥格式无法识别"
        case .badDER: return "服务器公钥解析失败（DER 结构异常）"
        case .keyCreationFailed(let detail): return "无法加载 RSA 公钥：\(detail)"
        case .encryptionFailed(let detail): return "密码加密失败：\(detail)"
        }
    }
}

enum RSA {
    /// 把统一的标识前缀带上，服务端据此判断是否需要解密。
    static let marker = "__RSA__"

    static func encryptPassword(_ password: String, publicKeyPEM: String) throws -> String {
        let cypher = try encrypt(Data(password.utf8), publicKeyPEM: publicKeyPEM)
        return marker + cypher.base64EncodedString()
    }

    static func encrypt(_ plaintext: Data, publicKeyPEM: String) throws -> Data {
        let der = try derFromPEM(publicKeyPEM)
        let pkcs1 = try pkcs1FromSPKI(der)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            pkcs1 as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            let message = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "未知错误"
            throw RSAError.keyCreationFailed(message)
        }

        guard let cipher = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            plaintext as CFData,
            &error
        ) else {
            let message = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "未知错误"
            throw RSAError.encryptionFailed(message)
        }
        return cipher as Data
    }

    // MARK: - PEM / DER

    static func derFromPEM(_ pem: String) throws -> [UInt8] {
        var body = pem
        for marker in [
            "-----BEGIN PUBLIC KEY-----",
            "-----END PUBLIC KEY-----",
            "-----BEGIN RSA PUBLIC KEY-----",
            "-----END RSA PUBLIC KEY-----",
        ] {
            body = body.replacingOccurrences(of: marker, with: "")
        }
        body = body.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !body.isEmpty, let data = Data(base64Encoded: body, options: [.ignoreUnknownCharacters]) else {
            throw RSAError.badPEM
        }
        return [UInt8](data)
    }

    /// X.509 SubjectPublicKeyInfo → PKCS#1 RSAPublicKey
    /// SEQUENCE { SEQUENCE { OID, NULL }, BIT STRING { 0x00, RSAPublicKey } }
    static func pkcs1FromSPKI(_ der: [UInt8]) throws -> Data {
        var index = 0
        guard try readTag(der, &index) == 0x30 else { throw RSAError.badDER }
        _ = try readLength(der, &index)

        // AlgorithmIdentifier
        guard try readTag(der, &index) == 0x30 else { throw RSAError.badDER }
        let algorithmLength = try readLength(der, &index)
        index += algorithmLength
        guard index < der.count else { throw RSAError.badDER }

        // BIT STRING
        guard try readTag(der, &index) == 0x03 else { throw RSAError.badDER }
        let bitStringLength = try readLength(der, &index)
        guard index < der.count, der[index] == 0x00 else { throw RSAError.badDER }
        let start = index + 1
        let end = index + bitStringLength
        guard end <= der.count, start < end else { throw RSAError.badDER }
        return Data(der[start..<end])
    }

    private static func readTag(_ bytes: [UInt8], _ index: inout Int) throws -> UInt8 {
        guard index < bytes.count else { throw RSAError.badDER }
        let tag = bytes[index]
        index += 1
        return tag
    }

    private static func readLength(_ bytes: [UInt8], _ index: inout Int) throws -> Int {
        guard index < bytes.count else { throw RSAError.badDER }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 == 0 {
            return length
        }
        let count = length & 0x7F
        guard count > 0, count <= 4, index + count <= bytes.count else { throw RSAError.badDER }
        length = 0
        for _ in 0..<count {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
