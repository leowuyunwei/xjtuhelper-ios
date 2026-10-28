//
//  HTMLForm.swift
//  XJTUBox
//
//  CAS 登录页靠解析几个隐藏 input 推进流程。Foundation 没有 HTML 解析器，
//  这里用正则做「够用」的抽取——只取 input 的 name/value 属性，不解析整棵树。
//

import Foundation

enum HTMLForm {
    /// 抽出某个 `<input name="xxx" ... value="yyy">` 的 value。
    static func hiddenValue(in html: String, name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        // 匹配 <input ... name="xxx" ... value="yyy" ...> 以及属性顺序颠倒的情况
        let patterns = [
            "<input[^>]*name\\s*=\\s*[\"']\(escaped)[\"'][^>]*value\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>",
            "<input[^>]*value\\s*=\\s*[\"']([^\"']*)[\"'][^>]*name\\s*=\\s*[\"']\(escaped)[\"'][^>]*>",
        ]
        for pattern in patterns {
            if let value = firstMatch(html, pattern: pattern) {
                return value
            }
        }
        return nil
    }

    static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    static func contains(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// CAS 的 `mfaEnabled` 开关藏在页内脚本的 globalConfig 里。
    static func mfaEnabled(in html: String) -> Bool? {
        guard let raw = firstMatch(
            html,
            pattern: "[\"']?mfaEnabled[\"']?\\s*[:=]\\s*[\"']?(true|false)[\"']?"
        ) else { return nil }
        return raw.lowercased() == "true"
    }

    /// 登录失败时 CAS 会在页面里渲染一条 alert 提示。
    static func alertMessage(in html: String) -> String? {
        let patterns = [
            "<div[^>]*class\\s*=\\s*[\"'][^\"']*alert[^\"']*[\"'][^>]*>(.*?)</div>",
            "<span[^>]*id\\s*=\\s*[\"']msg[\"'][^>]*>(.*?)</span>",
        ]
        for pattern in patterns {
            if let raw = firstMatch(html, pattern: pattern) {
                let cleaned = raw
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    /// Safety Verify（二次认证）页面与普通登录页都有 `execution`，靠 `secState` 区分。
    static func isSafetyVerifyPage(_ html: String) -> Bool {
        contains(html, pattern: "name\\s*=\\s*[\"']secState[\"']")
    }

    /// 账户选择页：同一学号对应本科生/研究生两个身份时出现。
    static func accountChoices(in html: String) -> [(name: String, label: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: "<a[^>]*href\\s*=\\s*[\"'][^\"']*[?&]username=([^\"'&]+)[^\"']*[\"'][^>]*>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var results: [(String, String)] = []
        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 1), in: html),
                  let labelRange = Range(match.range(at: 2), in: html) else { continue }
            let label = String(html[labelRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append((String(html[nameRange]), label))
        }
        return results
    }
}
