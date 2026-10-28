//
//  AgentService.swift
//  XJTUBox
//
//  「屁岱」：任意 OpenAI 兼容接口的流式对话。
//  校园数据以「上下文」形式拼进 system prompt，不额外上传到第三方。
//

import Foundation

struct AgentMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id = UUID()
    var role: Role
    var content: String
}

enum AgentError: LocalizedError {
    case missingKey
    case badURL
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "还没有填写 API Key，请到「我的 → 屁岱设置」里配置"
        case .badURL: return "接口地址不正确，需要形如 https://api.deepseek.com/v1"
        case .upstream(let message): return message
        }
    }
}

final class AgentService {
    /// 把课表 / 成绩压成一段可读上下文，让模型不必自己猜。
    @MainActor
    static func contextSummary(session: AppSession) -> String {
        var lines: [String] = []
        lines.append("当前时间：\(Date().formatted(date: .complete, time: .shortened))")
        if let term = session.term {
            lines.append("当前学期：\(term.name)，第 \(session.week) 周")
        }

        if !session.courses.isEmpty {
            lines.append("本周课表：")
            for day in 1...7 {
                let courses = session.courses(on: day)
                if courses.isEmpty { continue }
                let text = courses.map {
                    "\($0.name)（\($0.location)，第\($0.sectionRange)节，\($0.teacher)）"
                }.joined(separator: "；")
                lines.append("- \(Weekday.full[day - 1])：\(text)")
            }
        } else {
            lines.append("课表暂未加载。")
        }

        if !session.grades.isEmpty {
            lines.append(String(format: "GPA：%.2f（4.3 制加权），已修 %.1f 学分，共 %d 门课。",
                                session.gpa, session.earnedCredits, session.grades.count))
            let recent = session.grades.prefix(12).map {
                "\($0.courseName) \($0.scoreText)"
            }.joined(separator: "、")
            lines.append("最近的课程成绩：\(recent)")
        }
        return lines.joined(separator: "\n")
    }

    /// 发起一次流式请求，逐个返回增量文本。
    func stream(
        messages: [AgentMessage],
        context: String,
        baseURL: String,
        model: String,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !apiKey.isEmpty else { throw AgentError.missingKey }
                    guard let url = Self.completionsURL(baseURL) else { throw AgentError.badURL }

                    var payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": Self.buildPayload(messages: messages, context: context),
                    ]
                    if model.contains("reasoner") {
                        // 推理模型不吃 temperature
                    } else {
                        payload["temperature"] = 0.7
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AgentError.upstream("接口没有返回响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 600 { break }
                        }
                        throw AgentError.upstream(Self.friendlyError(code: http.statusCode, body: body))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payloadText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payloadText == "[DONE]" { break }
                        guard let data = payloadText.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = object["choices"] as? [[String: Any]],
                              let first = choices.first else { continue }

                        if let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                        if let finish = first["finish_reason"] as? String, finish == "stop" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func buildPayload(messages: [AgentMessage], context: String) -> [[String: String]] {
        var result: [[String: String]] = []
        result.append([
            "role": "system",
            "content": Prefs.agentSystemPrompt + "\n\n以下是这台设备上已有的校园数据，回答时优先使用：\n" + context,
        ])
        for message in messages.suffix(20) {
            result.append(["role": message.role.rawValue, "content": message.content])
        }
        return result
    }

    private static func completionsURL(_ base: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        if trimmed.hasSuffix("/v1") {
            return URL(string: trimmed + "/chat/completions")
        }
        return URL(string: trimmed + "/v1/chat/completions")
    }

    private static func friendlyError(code: Int, body: String) -> String {
        switch code {
        case 401: return "API Key 无效或已过期（401）"
        case 402: return "账户余额不足（402）"
        case 403: return "该 Key 无权访问这个模型（403）"
        case 404: return "接口地址或模型名不正确（404）"
        case 429: return "请求太频繁或额度用尽（429）"
        default:
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "接口返回 \(code)" : "接口返回 \(code)：\(trimmed.prefix(160))"
        }
    }
}
