//
//  SettingsView.swift
//  XJTUBox
//
//  「我的」：账号、模块进度、数据来源与关于。
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.pageMetrics) private var metrics

    @State private var confirmSignOut = false
    @State private var showAgentSettings = false

    var body: some View {
        PageScaffold {
            profileCard
            accountSection
            modulesSection
            dataSection
            aboutSection
        }
        .confirmationDialog("退出登录？", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                session.signOut()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新输入统一身份认证密码，本机缓存的数据不会上传。")
        }
        .sheet(isPresented: $showAgentSettings) {
            AgentSettingsSheet()
        }
    }

    // MARK: - 顶部

    private var profileCard: some View {
        HStack(spacing: AppTheme.spacing16) {
            Image(systemName: "person.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.brandGradient)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName.isEmpty ? "未登录" : session.displayName)
                    .font(.system(size: 18, weight: .semibold))
                Text(session.termName + (session.term.map { " · 共 \($0.effectiveTotalWeeks) 周" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLarge, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    // MARK: - 账号

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            SectionHeader(title: "账号")
            VStack(spacing: 0) {
                Button {
                    Task { await session.refreshAll() }
                } label: {
                    NavRow(icon: "arrow.triangle.2.circlepath", title: "刷新全部数据", subtitle: "课表与成绩")
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 48)

                Button {
                    showAgentSettings = true
                } label: {
                    NavRow(
                        icon: "sparkles",
                        title: "屁岱设置",
                        subtitle: session.agentModel,
                        tint: AppTheme.accentOrange
                    )
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 48)

                Button(role: .destructive) {
                    confirmSignOut = true
                } label: {
                    NavRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "退出登录",
                        subtitle: nil,
                        tint: AppTheme.accentRed
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.vertical, AppTheme.spacing4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - 模块进度

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            SectionHeader(title: "模块进度", subtitle: "如实标注，不做的功能不会假装有")
            VStack(spacing: 0) {
                moduleRow("登录 / 短信二次验证", icon: "lock.shield.fill", done: true)
                Divider().padding(.leading, 48)
                moduleRow("课表（含周次、操行时间）", icon: "calendar", done: true)
                Divider().padding(.leading, 48)
                moduleRow("成绩 / 4.3 制 GPA", icon: "chart.bar.fill", done: true)
                Divider().padding(.leading, 48)
                moduleRow("屁岱 AI 助手（OpenAI 兼容）", icon: "sparkles", done: true)
                Divider().padding(.leading, 48)
                moduleRow("校园卡 / 付款码", icon: "creditcard", done: false)
                Divider().padding(.leading, 48)
                moduleRow("图书馆座位 / 空闲教室", icon: "building.2", done: false)
                Divider().padding(.leading, 48)
                moduleRow("思源学堂 / 通知聚合", icon: "tray.full", done: false)
            }
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.vertical, AppTheme.spacing4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    private func moduleRow(_ title: String, icon: String, done: Bool) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(done ? AppTheme.accentGreen : Color(uiColor: .tertiaryLabel))
                .frame(width: 24)
            Text(title)
                .font(AppTheme.bodyText)
            Spacer(minLength: 0)
            Text(done ? "已可用" : "待移植")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(done ? AppTheme.accentGreen : .tertiary)
        }
        .padding(.vertical, 11)
    }

    // MARK: - 数据来源

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            SectionHeader(title: "数据来源")
            VStack(alignment: .leading, spacing: 6) {
                Text("· 统一认证：login.xjtu.edu.cn（新 CAS，密码经 RSA 公钥加密后提交）")
                Text("· 课表与成绩：jwxt.xjtu.edu.cn 教务系统，使用登录后的会话 Cookie")
                Text("· AI 助手：你自己配置的模型服务")
                Text("所有请求都直接发往学校系统或你配置的服务，本应用没有任何自建中转服务器。")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AppTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            SectionHeader(title: "关于")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("岱宗盒子 iOS")
                        .font(AppTheme.bodyText)
                    Spacer(minLength: 0)
                    Text("1.0.0")
                        .font(AppTheme.captionText)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "基于 yeliqin666/xjtu-toolbox-android 重写的 iOS 客户端，遵循 GPL-3.0。" +
                    "原项目为 Android 版，本仓库只包含 iOS 实现，接口契约与交互尽量与原版保持一致。"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text("非西安交通大学官方应用。请遵守学校各系统的使用规则，不要高频请求。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .padding(.bottom, AppTheme.spacing16)
    }
}
