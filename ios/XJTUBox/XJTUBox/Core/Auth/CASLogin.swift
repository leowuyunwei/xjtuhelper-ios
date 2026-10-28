//
//  CASLogin.swift
//  XJTUBox
//
//  西安交通大学统一身份认证（login.xjtu.edu.cn，2025-07 之后的新 CAS）。
//
//  流程（对齐 Android 版 XJTULogin.kt）：
//    1. GET  cas/login?service=<目标站>            → 拿到 execution，并判断是否已经免密登录
//    2. 若页面里有 mfaEnabled：POST cas/mfa/detect → {"data":{"state","need"}}
//       need=true 时：GET cas/mfa/initByType/securephone?state= 拿手机号 + gid
//                     POST attest/api/guard/securephone/send 发短信
//                     POST attest/api/guard/securephone/valid 校验
//    3. POST <cas 登录页> 账号密码（密码 __RSA__ 加密）+ execution + mfaState
//    4. 结果判定：401/alert → 密码错误；页面含 secState → 二次认证；含账户选择 → 选身份
//
//  说明：这里只做「够 iOS 端用」的路径，Safety Verify 的完整分支也实现了，
//  但部分站点的 postLogin（例如先换 OAuth code）留给各业务模块自己补。
//

import Foundation
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

enum LoginState: Equatable {
    case idle
    case working(String)
    case needMFA(phone: String)
    case needCaptcha
    case authenticated
    case failed(String)
}

enum LoginError: LocalizedError {
    case notCASPage
    case badCredentials(String)
    case needMFA(phone: String)
    case needCaptcha
    case serverError(String)
    case aborted

    var errorDescription: String? {
        switch self {
        case .notCASPage: return "没有打开统一认证登录页，请稍后重试"
        case .badCredentials(let message): return message
        case .needMFA(let phone): return "需要短信验证（\(phone)）"
        case .needCaptcha: return "需要输入验证码"
        case .serverError(let message): return message
        case .aborted: return "登录已取消"
        }
    }
}

@MainActor
final class CASLogin {
    static let shared = CASLogin()

    private let http = HTTPClient.shared

    /// 统一认证入口。
    private let casLoginURL = "https://login.xjtu.edu.cn/cas/login"
    /// 提交表单的地址（GET 后可能被重定向到带 service 的地址）。
    private(set) var postURL: String = ""
    private(set) var execution: String = ""
    private(set) var serviceURL: String = ""
    private(set) var mfaEnabled: Bool = true
    private(set) var mfaState: String = ""
    private(set) var mfaGID: String?
    private(set) var mfaPhone: String?

    /// Safety Verify 流程的上下文。
    private var safetyTriggerURL: String?
    private var safetyExecution: String?
    private var safetySecState: String?
    private var safetyEventId: String = "submit"
    private var safetySubmitValue: String = "Login1"
    private(set) var isSafetyVerify: Bool = false

    /// 失败次数，≥3 时服务端会要求图形验证码。
    private(set) var failureCount: Int = 0

    private init() {}

    // MARK: - 设备指纹

    /// 服务端靠这个 ID 区分设备，频繁变化会反复触发 MFA。
    /// 与安卓端同样的算法：稳定设备字段 + 账号做 SHA-256，取前 32 个十六进制字符。
    private var visitorID: String {
        if let existing = SecretStore.get("fpVisitorId.v2") { return existing }
        let seed = [
            "ios",
            "Apple",
            deviceModel,
            deviceVendorID,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let value = String(hex.prefix(32))
        SecretStore.set(value, for: "fpVisitorId.v2")
        return value
    }

    private var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "iOS"
        #endif
    }

    private var deviceVendorID: String {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #else
        return "unknown"
        #endif
    }

    // MARK: - 第一步：打开登录页

    /// 打开 CAS 登录页。若 TGC 仍然有效，会直接跳转到目标站（视为已登录）。
    @discardableResult
    func bootstrap(service: String) async -> Bool {
        serviceURL = service
        let encoded = service.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? service
        let url = "\(casLoginURL)?service=\(encoded)"

        guard let response = try? await http.get(url) else { return false }
        let html = response.text
        let finalURL = response.url?.absoluteString ?? ""

        if HTMLForm.isSafetyVerifyPage(html) {
            captureSafetyVerify(html: html, triggerURL: finalURL)
            return false
        }

        let found = HTMLForm.hiddenValue(in: html, name: "execution") ?? ""
        execution = found
        postURL = finalURL
        mfaEnabled = HTMLForm.mfaEnabled(in: html) ?? true

        // 页面没有登录表单、且落在非统一的站点上 → 免密已经走通
        if found.isEmpty && !finalURL.contains("login.xjtu.edu.cn") {
            return true
        }
        return false
    }

    // MARK: - 第二步：账号密码登录

    /// 完整登录。需要 MFA 时抛 `.needMFA`，调用方展示验证码界面后调 `verifySMSCode`。
    func signIn(username: String, password: String, captcha: String = "") async throws {
        if postURL.isEmpty {
            _ = await bootstrap(service: serviceURL.isEmpty ? CASService.default : serviceURL)
        }
        // 已经免密登录成功
        if execution.isEmpty && !postURL.contains("login.xjtu.edu.cn") {
            return
        }
        guard !execution.isEmpty else { throw LoginError.notCASPage }
        guard failureCount < 3 || !captcha.isEmpty else { throw LoginError.needCaptcha }

        let encrypted = try RSA.encryptPassword(password, publicKeyPEM: try await rsaPublicKey())
        SecretStore.set(encrypted, for: "cas.encryptedPassword")
        SecretStore.set(username, for: "cas.username")

        // MFA 探测：先确认这次登录是否需要短信验证
        if mfaEnabled && mfaState.isEmpty {
            try await detectMFA(username: username, encryptedPassword: encrypted)
            if !mfaState.isEmpty {
                // 需要验证码：先拉手机号，抛给 UI
                let phone = try await fetchMFAChallenge(state: mfaState, pathSegment: "mfa")
                throw LoginError.needMFA(phone: phone)
            }
        }

        try await submitLoginForm(username: username, encryptedPassword: encrypted, captcha: captcha)
    }

    /// MFA 探测。need=false 时不设置 mfaState，直接继续密码登录。
    private func detectMFA(username: String, encryptedPassword: String) async throws {
        let response = try await http.postForm(
            "https://login.xjtu.edu.cn/cas/mfa/detect",
            fields: [
                "username": username,
                "password": encryptedPassword,
                "fpVisitorId": visitorID,
            ],
            headers: ["Referer": postURL]
        )
        guard let data = response.data as Data?,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any] else {
            // 探测接口异常不阻塞登录：CAS 会在提交表单时再次判断
            return
        }
        let state = payload["state"] as? String ?? ""
        let need = (payload["need"] as? Bool) ?? false
        if need, !state.isEmpty {
            mfaState = state
        }
    }

    /// 拉取脱敏手机号，同时把 gid 存下来（发短信要用）。
    private func fetchMFAChallenge(state: String, pathSegment: String) async throws -> String {
        let url = "https://login.xjtu.edu.cn/cas/\(pathSegment)/initByType/securephone?state=\(state)"
        let response = try await http.get(url)
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw LoginError.serverError("获取手机号失败：响应格式异常")
        }
        let code = (object["code"] as? Int) ?? -1
        guard code == 0, let payload = object["data"] as? [String: Any] else {
            let message = object["message"] as? String ?? "未知错误"
            throw LoginError.serverError("获取手机号失败：\(message)")
        }
        mfaGID = payload["gid"] as? String
        let phone = payload["securePhone"] as? String ?? "已绑定手机"
        mfaPhone = phone
        return phone
    }

    /// 发送短信验证码，返回脱敏手机号。
    func sendSMSCode() async throws -> String {
        guard let gid = mfaGID else {
            if isSafetyVerify, let secState = safetySecState {
                return try await fetchMFAChallenge(state: secState, pathSegment: "sec")
            }
            throw LoginError.serverError("尚未获取到验证会话，请重新登录")
        }
        let response = try await http.postJSON(
            "https://login.xjtu.edu.cn/attest/api/guard/securephone/send",
            object: ["gid": gid]
        )
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              ((object["code"] as? Int) ?? -1) == 0 else {
            let message = (try? JSONSerialization.jsonObject(with: response.data) as? [String: Any])
                .flatMap { $0?["message"] as? String } ?? "发送失败"
            throw LoginError.serverError(message)
        }
        return mfaPhone ?? "已绑定手机"
    }

    /// 校验短信验证码，成功后继续完成登录。
    func verifySMSCode(_ code: String) async throws {
        guard let gid = mfaGID else {
            throw LoginError.serverError("尚未发送验证码")
        }
        let response = try await http.postJSON(
            "https://login.xjtu.edu.cn/attest/api/guard/securephone/valid",
            object: ["gid": gid, "code": code]
        )
        guard let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              ((object["code"] as? Int) ?? -1) == 0 else {
            let message = (try? JSONSerialization.jsonObject(with: response.data) as? [String: Any])
                .flatMap { $0?["message"] as? String } ?? "验证码错误"
            throw LoginError.badCredentials(message)
        }
        if let data = object["data"] as? [String: Any],
           let status = data["status"] as? String, status != "2" {
            throw LoginError.badCredentials("验证码验证失败")
        }

        if isSafetyVerify {
            try await submitSafetyVerify()
            return
        }

        let username = SecretStore.get("cas.username") ?? ""
        let encrypted = SecretStore.get("cas.encryptedPassword") ?? ""
        guard !username.isEmpty, !encrypted.isEmpty else {
            throw LoginError.serverError("登录状态已丢失，请重新登录")
        }
        try await submitLoginForm(username: username, encryptedPassword: encrypted, captcha: "")
    }

    // MARK: - 第三步：提交表单

    private func submitLoginForm(username: String, encryptedPassword: String, captcha: String) async throws {
        let fields: [String: String] = [
            "username": username,
            "password": encryptedPassword,
            "execution": execution,
            "_eventId": "submit",
            "submit1": "Login1",
            "fpVisitorId": visitorID,
            "captcha": captcha,
            "currentMenu": "1",
            "failN": String(failureCount),
            "mfaState": mfaState,
            "geolocation": "",
            "trustAgent": mfaState.isEmpty ? "" : "true",
        ]

        let response = try await http.postForm(postURL, fields: fields)
        try await handleLoginResponse(response)
    }

    private func handleLoginResponse(_ response: HTTPResponse) async throws {
        if response.status == 401 {
            failureCount += 1
            throw LoginError.badCredentials("用户名或密码错误")
        }

        let html = response.text

        if let alert = HTMLForm.alertMessage(in: html) {
            failureCount += 1
            throw LoginError.badCredentials(alert)
        }

        if HTMLForm.isSafetyVerifyPage(html) {
            captureSafetyVerify(html: html, triggerURL: response.url?.absoluteString ?? postURL)
            let phone = try await fetchMFAChallenge(state: safetySecState ?? "", pathSegment: "sec")
            throw LoginError.needMFA(phone)
        }

        let choices = HTMLForm.accountChoices(in: html)
        if !choices.isEmpty {
            try await chooseAccount(choices: choices, pageHTML: html)
            return
        }

        failureCount = 0
        isSafetyVerify = false
        mfaState = ""
        mfaGID = nil
        // 停在统一认证页说明没有真正登录成功
        if let finalURL = response.url?.absoluteString, finalURL.contains("login.xjtu.edu.cn"),
           !execution.isEmpty {
            failureCount += 1
            throw LoginError.badCredentials("登录未完成，请检查账号密码或稍后重试")
        }
    }

    /// 账户选择：同一学号同时存在本科 / 研究生身份时，CAS 让用户先选一个。
    /// 提交目标是 `cas/login`（不带 service），且 execution 要用选择页上的新值。
    private func chooseAccount(choices: [(name: String, label: String)], pageHTML: String) async throws {
        let preferred = choices.first { $0.label.contains("研究") } ?? choices.first
        guard let preferred else { return }
        let choiceExecution = HTMLForm.hiddenValue(in: pageHTML, name: "execution") ?? execution
        if !choiceExecution.isEmpty { execution = choiceExecution }

        let response = try await http.postForm(
            casLoginURL,
            fields: [
                "execution": execution,
                "_eventId": "submit",
                "geolocation": "",
                "fpVisitorId": visitorID,
                "trustAgent": mfaState.isEmpty ? "" : "true",
                "username": preferred.name,
                "useDefault": "false",
            ]
        )
        if let alert = HTMLForm.alertMessage(in: response.text) {
            throw LoginError.badCredentials(alert)
        }
        if let finalURL = response.url?.absoluteString, finalURL.contains("cas/login") {
            // 还在选择页 → 说明提交没生效，给出可读错误而不是静默成功
            let remaining = HTMLForm.accountChoices(in: response.text)
            if !remaining.isEmpty {
                throw LoginError.serverError("该学号有多个身份，自动选择失败，请到安卓版选择一次后再试")
            }
        }
    }

    // MARK: - Safety Verify（二次认证）

    private func captureSafetyVerify(html: String, triggerURL: String) {
        isSafetyVerify = true
        safetyTriggerURL = triggerURL
        safetySecState = HTMLForm.hiddenValue(in: html, name: "secState")
        safetyExecution = HTMLForm.hiddenValue(in: html, name: "execution")
        safetyEventId = HTMLForm.hiddenValue(in: html, name: "_eventId") ?? "submit"
        safetySubmitValue = HTMLForm.hiddenValue(in: html, name: "submit") ?? "Login1"
    }

    private func submitSafetyVerify() async throws {
        guard let trigger = safetyTriggerURL,
              let secState = safetySecState,
              let exec = safetyExecution else {
            throw LoginError.serverError("二次认证上下文缺失，请重新登录")
        }
        let response = try await http.postForm(
            trigger,
            fields: [
                "secState": secState,
                "execution": exec,
                "_eventId": safetyEventId,
                "geolocation": "",
                "fpVisitorId": visitorID,
                "submit": safetySubmitValue,
            ],
            headers: ["Referer": trigger]
        )
        if let alert = HTMLForm.alertMessage(in: response.text) {
            throw LoginError.badCredentials(alert)
        }
        isSafetyVerify = false
    }

    // MARK: - RSA 公钥

    private var cachedPublicKey: String?

    private func rsaPublicKey() async throws -> String {
        if let cachedPublicKey { return cachedPublicKey }
        let response = try await http.get(
            "https://login.xjtu.edu.cn/cas/jwt/publicKey",
            headers: ["Referer": postURL.isEmpty ? casLoginURL : postURL]
        )
        let body = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.lowercased().contains("<html") else {
            throw LoginError.serverError("公钥接口返回了网页，可能被网络代理拦截")
        }
        cachedPublicKey = body
        return body
    }

    // MARK: - 会话复用

    /// 尝试用现有 Cookie 直接完成某个站点的 SSO。
    /// 返回 true 表示已经可以访问该站点，不需要重新输密码。
    @discardableResult
    func silentSSO(service: String) async -> Bool {
        let encoded = service.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? service
        guard let response = try? await http.get("\(casLoginURL)?service=\(encoded)") else { return false }
        let finalURL = response.url?.absoluteString ?? ""
        if finalURL.contains("login.xjtu.edu.cn") {
            let html = response.text
            if HTMLForm.hiddenValue(in: html, name: "execution") != nil { return false }
            if HTMLForm.isSafetyVerifyPage(html) { return false }
        }
        return true
    }

    func reset() {
        execution = ""
        postURL = ""
        mfaState = ""
        mfaGID = nil
        mfaPhone = nil
        isSafetyVerify = false
        safetyTriggerURL = nil
        safetySecState = nil
        failureCount = 0
        cachedPublicKey = nil
    }
}

/// 各业务站点的 CAS service 参数。
enum CASService {
    /// 默认入口：教务（jwapp）的 SSO。
    static let `default` = "https://jwapp.xjtu.edu.cn/app/index"
    static let jwapp = "https://jwapp.xjtu.edu.cn/app/index"
    static let jwxt = "https://jwxt.xjtu.edu.cn/jwapp/sys/homeapp/index.do"
    static let card = "https://ncard.xjtu.edu.cn/"
    static let library = "https://rg.lib.xjtu.edu.cn/"
    static let lms = "https://lms.xjtu.edu.cn/"
    static let ehall = "https://ehall.xjtu.edu.cn/"
    static let ywtb = "https://ywtb.xjtu.edu.cn/"
}
