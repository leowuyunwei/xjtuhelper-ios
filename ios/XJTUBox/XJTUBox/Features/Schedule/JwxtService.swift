//
//  JwxtService.swift
//  XJTUBox
//
//  教务（jwxt.xjtu.edu.cn）接口。走 CAS 会话 Cookie，不需要额外 token。
//  对齐 Android 版 JwxtScheduleApi / CjcxApi 的请求形状。
//

import Foundation

struct JwxtError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// 教务返回的 `{code, datas:{...}}` 信封。
private struct JwxtEnvelope {
    let code: String
    let datas: [String: Any]
}

enum JwxtParser {
    static func envelope(_ data: Data) throws -> JwxtEnvelope {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JwxtError(message: "教务返回的不是 JSON，可能登录已失效，请重试")
        }
        let codeValue = root["code"]
        let code: String
        if let number = codeValue as? Int {
            code = String(number)
        } else if let text = codeValue as? String {
            code = text
        } else {
            code = "0"
        }
        let datas = root["datas"] as? [String: Any] ?? [:]
        return JwxtEnvelope(code: code, datas: datas)
    }

    static func rows(_ datas: [String: Any], key: String) -> [[String: Any]] {
        guard let block = datas[key] as? [String: Any],
              let rows = block["rows"] as? [[String: Any]] else { return [] }
        return rows
    }

    static func string(_ object: [String: Any], _ key: String) -> String {
        if let value = object[key] as? String { return value }
        if let value = object[key] as? Int { return String(value) }
        if let value = object[key] as? Double { return String(value) }
        return ""
    }

    static func int(_ object: [String: Any], _ key: String, default fallback: Int) -> Int {
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? String, let parsed = Int(value) { return parsed }
        if let value = object[key] as? Double { return Int(value) }
        return fallback
    }

    static func double(_ object: [String: Any], _ key: String) -> Double? {
        if let value = object[key] as? Double { return value }
        if let value = object[key] as? Int { return Double(value) }
        if let value = object[key] as? String { return Double(value) }
        return nil
    }
}

/// 教务客户端。
final class JwxtService {
    static let shared = JwxtService()

    private let http = HTTPClient.shared
    private let base = "https://jwxt.xjtu.edu.cn"
    private var didWarmUp = false

    private init() {}

    /// 打开教务首页，必要时先走一次 CAS SSO。
    func warmUp() async throws {
        if didWarmUp { return }
        let index = "\(base)/jwapp/sys/homeapp/index.do"
        let response = try await http.get(index)
        if isLoginPage(response) {
            let ok = await CASLogin.shared.silentSSO(service: index)
            let retry = try await http.get(index)
            if !ok || isLoginPage(retry) {
                throw JwxtError(message: "教务系统需要重新登录")
            }
        }
        didWarmUp = true
    }

    private func isLoginPage(_ response: HTTPResponse) -> Bool {
        let url = response.url?.absoluteString ?? ""
        if url.contains("login.xjtu.edu.cn") { return true }
        if response.status == 401 || response.status == 403 { return true }
        return false
    }

    private func post(_ path: String, fields: [String: String]) async throws -> Data {
        try await warmUp()
        let response = try await http.postForm(
            "\(base)\(path)",
            fields: fields,
            headers: [
                "X-Requested-With": "XMLHttpRequest",
                "Accept": "application/json, text/javascript, */*; q=0.01",
                "Referer": "\(base)/jwapp/sys/wdkb/*default/index.do",
            ]
        )
        if isLoginPage(response) {
            didWarmUp = false
            throw JwxtError(message: "教务登录已过期，请重新登录")
        }
        return response.data
    }

    // MARK: - 学期

    /// 当前学期（`dqxnxq.do`）。
    func currentTerm() async throws -> String {
        let data = try await post("/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do", fields: [:])
        let envelope = try JwxtParser.envelope(data)
        let rows = JwxtParser.rows(envelope.datas, key: "dqxnxq")
        guard let first = rows.first else {
            throw JwxtError(message: "教务没有返回当前学期")
        }
        let code = JwxtParser.string(first, "DM").trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else {
            throw JwxtError(message: "教务没有返回当前学期代码")
        }
        return code
    }

    /// 学期起点与周数（`cxjcs.do`）。拿不到时返回 nil，界面按今天推算周次。
    func termInfo(code: String) async throws -> TermInfo {
        var info = TermInfo(code: code, name: code, startDate: nil, totalWeeks: 20)
        let parts = code.split(separator: "-")
        if parts.count >= 3 {
            let fields = [
                "XN": "\(parts[0])-\(parts[1])",
                "XQ": String(parts[2]),
            ]
            if let data = try? await post("/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do", fields: fields),
               let envelope = try? JwxtParser.envelope(data),
               let block = envelope.datas.values.compactMap({ $0 as? [String: Any] }).first,
               let rows = block["rows"] as? [[String: Any]],
               let first = rows.first {
                let raw = JwxtParser.string(first, "XQKSRQ")
                if !raw.isEmpty {
                    info.startDate = DateFormats.parseDay(String(raw.prefix(10)))
                }
                let weeks = JwxtParser.int(first, "ZZC", default: 0)
                if weeks > 0 && weeks <= 30 { info.totalWeeks = weeks }
            }
        }
        return info
    }

    // MARK: - 课表

    func schedule(term: String) async throws -> [Course] {
        let data = try await post(
            "/jwapp/sys/wdkb/modules/xskcb/xskcb.do",
            fields: ["XNXQDM": term]
        )
        let envelope = try JwxtParser.envelope(data)
        let rows = JwxtParser.rows(envelope.datas, key: "xskcb")
        return rows.enumerated().compactMap { index, row in
            let name = JwxtParser.string(row, "KCM")
            guard !name.isEmpty else { return nil }
            let type = JwxtParser.string(row, "KCXZMC").isEmpty
                ? JwxtParser.string(row, "KCXZDM_DISPLAY")
                : JwxtParser.string(row, "KCXZMC")
            return Course(
                id: "\(JwxtParser.string(row, "JXBID"))-\(index)",
                name: name,
                teacher: JwxtParser.string(row, "SKJS"),
                location: JwxtParser.string(row, "JASMC"),
                courseCode: JwxtParser.string(row, "KCH"),
                courseType: type,
                weekBits: JwxtParser.string(row, "SKZC"),
                dayOfWeek: JwxtParser.int(row, "SKXQ", default: 1),
                startSection: JwxtParser.int(row, "KSJC", default: 1),
                endSection: JwxtParser.int(row, "JSJC", default: 1)
            )
        }
    }

    // MARK: - 成绩

    func scores() async throws -> [Grade] {
        _ = try? await http.get("\(base)/jwapp/sys/cjcx/*default/index.do")
        var all: [Grade] = []
        var page = 1
        let pageSize = 100
        let querySetting = """
        [{"name":"SFYX","caption":"是否有效","linkOpt":"AND","builderList":"cbl_m_List","builder":"m_value_equal","value":"1","value_display":"是"}]
        """
        while page <= 20 {
            let data = try await post(
                "/jwapp/sys/cjcx/modules/cjcx/xscjcx.do",
                fields: [
                    "querySetting": querySetting,
                    "pageSize": String(pageSize),
                    "pageNumber": String(page),
                ]
            )
            let envelope = try JwxtParser.envelope(data)
            let rows = JwxtParser.rows(envelope.datas, key: "xscjcx")
            if rows.isEmpty { break }
            for row in rows {
                let name = JwxtParser.string(row, "KCM")
                guard !name.isEmpty else { continue }
                all.append(
                    Grade(
                        id: JwxtParser.string(row, "JXBID") + "-" + JwxtParser.string(row, "KCH"),
                        courseName: name,
                        termCode: JwxtParser.string(row, "XNXQDM"),
                        score: JwxtParser.double(row, "ZCJ"),
                        gpaPoint: JwxtParser.double(row, "XFJD"),
                        credit: JwxtParser.double(row, "XF") ?? 0,
                        gradeName: JwxtParser.string(row, "DJCJMC"),
                        passed: JwxtParser.string(row, "SFJG") == "1",
                        courseCode: JwxtParser.string(row, "KCH")
                    )
                )
            }
            if rows.count < pageSize { break }
            page += 1
        }
        return all
    }
}

enum DateFormats {
    /// 教务给的是 `2026-09-14` 这种纯日期。
    static func parseDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
