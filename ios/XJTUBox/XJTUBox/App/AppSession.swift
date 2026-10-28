//
//  AppSession.swift
//  XJTUBox
//
//  全局会话：登录态、课表、成绩、AI 配置。页面只读这里的状态，不各自发请求。
//

import Foundation
import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home
    case schedule
    case score
    case agent
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .schedule: return "课表"
        case .score: return "成绩"
        case .agent: return "屁岱"
        case .me: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .schedule: return "calendar"
        case .score: return "chart.bar"
        case .agent: return "sparkles"
        case .me: return "person.crop.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .schedule: return "calendar" // calendar 没有 filled 变体
        case .score: return "chart.bar.fill"
        case .agent: return "sparkles"
        case .me: return "person.crop.circle.fill"
        }
    }
}

enum SessionPhase: Equatable {
    case launching
    case signedOut
    case signedIn
}

@MainActor
@Observable
final class AppSession {
    // MARK: - 登录态

    var phase: SessionPhase = .launching
    var username: String = ""
    var displayName: String = ""

    /// 正在进行的动作提示（登录按钮 / 页面 loading 用）。
    var activity: String?
    var lastError: String?

    /// MFA 弹窗需要的手机号；非空即展示验证码界面。
    var mfaPhone: String?
    var mfaSent: Bool = false
    var needCaptcha: Bool = false

    // MARK: - 业务数据

    var term: TermInfo?
    var courses: [Course] = []
    var grades: [Grade] = []
    var scheduleLoaded = false
    var gradesLoaded = false

    /// 当前查看的周次（1 起）。
    var week: Int = 1
    var selectedDay: Int = Weekday.current()

    // MARK: - AI

    var agentBaseURL: String = Prefs.agentBaseURL
    var agentModel: String = Prefs.agentModel
    var agentKey: String = SecretStore.get("agent.apiKey") ?? ""

    // MARK: - 生命周期

    func bootstrap() async {
        username = Prefs.activeAccount ?? ""
        displayName = username
        if username.isEmpty {
            phase = .signedOut
            return
        }
        // 有账号就先用 Cookie 试一次免密，失败再回登录页
        activity = "恢复登录状态…"
        let alive = await CASLogin.shared.silentSSO(service: CASService.jwxt)
        activity = nil
        if alive {
            phase = .signedIn
            await refreshAll()
        } else {
            phase = .signedOut
        }
    }

    // MARK: - 登录

    /// 返回 true 表示登录流程已经走完（成功或需要 MFA 才会返回，其它失败抛错）。
    func signIn(username: String, password: String, captcha: String = "") async throws {
        self.username = username
        lastError = nil
        needCaptcha = false
        activity = "正在登录…"
        defer { activity = nil }

        _ = await CASLogin.shared.bootstrap(service: CASService.jwxt)
        do {
            try await CASLogin.shared.signIn(
                username: username,
                password: password,
                captcha: captcha
            )
            try await completeSignIn()
        } catch {
            if case LoginError.needMFA(let phone) = error {
                mfaPhone = phone
                mfaSent = false
                throw error
            }
            if case LoginError.needCaptcha = error {
                needCaptcha = true
                throw error
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    func sendSMSCode() async {
        activity = "发送验证码…"
        defer { activity = nil }
        do {
            _ = try await CASLogin.shared.sendSMSCode()
            mfaSent = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func submitSMSCode(_ code: String) async throws {
        activity = "验证中…"
        defer { activity = nil }
        do {
            try await CASLogin.shared.verifySMSCode(code)
            mfaPhone = nil
            try await completeSignIn()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func completeSignIn() async throws {
        Prefs.activeAccount = username
        var accounts = Prefs.savedAccounts
        if !accounts.contains(username) { accounts.append(username) }
        Prefs.savedAccounts = accounts
        SecretStore.set(username, for: "account.username")

        phase = .signedIn
        mfaPhone = nil
        scheduleLoaded = false
        gradesLoaded = false
        await refreshAll()
    }

    func signOut() {
        // 清 Cookie，否则下次 silentSSO 会直接成功
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        CASLogin.shared.reset()
        courses = []
        grades = []
        term = nil
        scheduleLoaded = false
        gradesLoaded = false
        Prefs.activeAccount = nil
        SecretStore.remove("cas.encryptedPassword")
        phase = .signedOut
    }

    // MARK: - 数据刷新

    func refreshAll() async {
        async let scheduleTask: Void = loadSchedule()
        async let gradesTask: Void = loadGrades()
        _ = await (scheduleTask, gradesTask)
    }

    func loadSchedule() async {
        activity = "加载课表…"
        defer { activity = nil }
        do {
            let termCode = try await JwxtService.shared.currentTerm()
            let info = try await JwxtService.shared.termInfo(code: termCode)
            let list = try await JwxtService.shared.schedule(term: termCode)
            term = info
            courses = list
            week = info.week(of: Date())
            scheduleLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadGrades() async {
        do {
            grades = try await JwxtService.shared.scores()
            gradesLoaded = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 汇总

    var gpa: Double {
        ScoreCalculator.weightedGPA(grades)
    }

    var earnedCredits: Double {
        ScoreCalculator.earnedCredits(grades)
    }

    var coursesThisWeek: [Course] {
        courses.filter { $0.occurs(inWeek: week) }
    }

    func courses(on day: Int) -> [Course] {
        coursesThisWeek
            .filter { $0.dayOfWeek == day }
            .sorted { $0.startSection < $1.startSection }
    }

    /// 今天剩下的课，用于首页。
    var todayCourses: [Course] {
        courses(on: selectedDay)
    }

    var nextCourse: Course? {
        todayCourses.first
    }

    var termName: String {
        term?.name ?? "本学期"
    }

    func saveAgentSettings() {
        Prefs.agentBaseURL = agentBaseURL
        Prefs.agentModel = agentModel
        SecretStore.set(agentKey, for: "agent.apiKey")
    }
}
