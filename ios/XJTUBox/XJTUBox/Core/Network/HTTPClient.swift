//
//  HTTPClient.swift
//  XJTUBox
//
//  URLSession 之上的薄封装：
//  - 默认自动带 Cookie（CAS 登录全靠它）
//  - 可选「不跟随重定向」，用来读 302 的 Location 判断登录结果
//  - 统一超时、UA、错误分类
//

import Foundation

enum HTTPError: Error, LocalizedError {
    case invalidURL
    case transport(Error)
    case status(Int)
    case decoding(Error)
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请求地址无效"
        case .transport(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet: return "网络未连接"
                case .timedOut: return "请求超时"
                case .cannotFindHost, .cannotConnectToHost: return "无法连接服务器"
                case .secureConnectionFailed, .serverCertificateUntrusted:
                    return "HTTPS 证书校验失败"
                case .appTransportSecurityRequiresSecureConnection:
                    return "该地址不允许非 HTTPS 访问"
                default: return "网络错误（\(urlError.code.rawValue)）"
                }
            }
            return error.localizedDescription
        case .status(let code):
            return "服务器返回 \(code)"
        case .decoding:
            return "解析响应失败"
        case .emptyBody:
            return "响应内容为空"
        }
    }
}

struct HTTPResponse {
    var status: Int
    var headers: [AnyHashable: Any]
    var data: Data
    var url: URL?

    var text: String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let gbk = String(data: data, encoding: String.Encoding(rawValue: 0x80000632)) { return gbk }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    var location: String? {
        header("Location")
    }

    func header(_ name: String) -> String? {
        for (key, value) in headers {
            if let key = key as? String, key.caseInsensitiveCompare(name) == .orderedSame {
                return value as? String
            }
        }
        return nil
    }

    func json<T: Decodable>(_ type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPError.decoding(error)
        }
    }
}

/// 不跟随重定向的会话代理：只捕获第一跳，便于读 Location。
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// 全局共享的 HTTP 客户端。Cookie 走 HTTPCookieStorage.shared，CAS 会话在进程内复用。
final class HTTPClient {
    static let shared = HTTPClient()

    private let redirecting: URLSession
    private let nonRedirecting: URLSession
    private let noRedirectDelegate = NoRedirectDelegate()

    /// 统一认证下发的 TGC 与 UA 绑定，全流程必须用同一个 UA。
    /// 这里沿用安卓客户端那串：学校 WAF 对它最友好，且与官方客户端的指纹一致。
    static let userAgent =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/131.0.0.0 Mobile Safari/537.36"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": HTTPClient.userAgent,
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        redirecting = URLSession(configuration: config)

        let rawConfig = URLSessionConfiguration.default
        rawConfig.timeoutIntervalForRequest = 20
        rawConfig.timeoutIntervalForResource = 45
        rawConfig.httpCookieAcceptPolicy = .always
        rawConfig.httpShouldSetCookies = true
        rawConfig.httpCookieStorage = HTTPCookieStorage.shared
        rawConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        rawConfig.httpAdditionalHeaders = [
            "User-Agent": HTTPClient.userAgent,
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        nonRedirecting = URLSession(
            configuration: rawConfig,
            delegate: noRedirectDelegate,
            delegateQueue: nil
        )
    }

    // MARK: - 便捷方法

    func get(
        _ url: String,
        query: [String: String] = [:],
        headers: [String: String] = [:],
        followRedirects: Bool = true
    ) async throws -> HTTPResponse {
        guard var components = URLComponents(string: url) else { throw HTTPError.invalidURL }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }
        guard let finalURL = components.url else { throw HTTPError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await perform(request, followRedirects: followRedirects)
    }

    func postForm(
        _ url: String,
        fields: [String: String],
        headers: [String: String] = [:],
        followRedirects: Bool = true
    ) async throws -> HTTPResponse {
        guard let finalURL = URL(string: url) else { throw HTTPError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = HTTPClient.formEncode(fields).data(using: .utf8)
        return try await perform(request, followRedirects: followRedirects)
    }

    func postJSON(
        _ url: String,
        object: Any,
        headers: [String: String] = [:],
        followRedirects: Bool = true
    ) async throws -> HTTPResponse {
        guard let finalURL = URL(string: url) else { throw HTTPError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: object, options: [])
        return try await perform(request, followRedirects: followRedirects)
    }

    /// 发一个自定义请求（流式场景会用到，比如 AI 助手的 SSE）。
    func rawRequest(_ request: URLRequest, followRedirects: Bool = true) async throws -> HTTPResponse {
        try await perform(request, followRedirects: followRedirects)
    }

    /// 取流式响应（AI 助手逐字输出）。
    func stream(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = redirecting.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.finish(throwing: HTTPError.transport(error))
                    return
                }
                guard let data, let http = response as? HTTPURLResponse else {
                    continuation.finish(throwing: HTTPError.emptyBody)
                    return
                }
                guard (200..<300).contains(http.statusCode) else {
                    continuation.finish(throwing: HTTPError.status(http.statusCode))
                    return
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    if let chunk = HTTPClient.parseSSELine(String(line)), !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
            task.resume()
        }
    }

    private func perform(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        let session = followRedirects ? redirecting : nonRedirecting
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.emptyBody }
            return HTTPResponse(
                status: http.statusCode,
                headers: http.allHeaderFields,
                data: data,
                url: http.url
            )
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.transport(error)
        }
    }

    // MARK: - 工具

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var parts: [String] = []
        for key in fields.keys.sorted() {
            let value = fields[key] ?? ""
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            parts.append("\(k)=\(v)")
        }
        allowed = .init()
        return parts.joined(separator: "&")
    }

    /// 解析一行 SSE（`data: {...}`），返回其中 `choices[0].delta.content`。
    static func parseSSELine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return nil }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        if let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        return nil
    }
}
