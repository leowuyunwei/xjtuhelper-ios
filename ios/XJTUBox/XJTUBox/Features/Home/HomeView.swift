//
//  HomeView.swift
//  XJTUBox
//
//  首页：问候 + 本周状态 + 今天的课 + 成绩概览 + 快捷入口。
//

import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.pageMetrics) private var metrics

    @Binding var selection: RootTab

    var body: some View {
        PageScaffold(
            showsRefresh: true,
            onRefresh: { Task { await session.refreshAll() } }
        ) {
            heroCard

            if let error = session.lastError {
                ErrorBanner(message: error) {
                    Task { await session.refreshAll() }
                }
            }

            todaySection
            statsSection
            quickSection
            aboutSection
        }
    }

    // MARK: - 顶部

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(session.displayName.isEmpty ? "西交同学" : session.displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("第 \(session.week) 周")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(session.termName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.18))
                )
            }

            Divider().overlay(.white.opacity(0.25))

            HStack(spacing: AppTheme.spacing20) {
                heroStat(title: "今日课程", value: "\(session.todayCourses.count)", unit: "节")
                heroStat(title: "本学期课程", value: "\(session.courses.count)", unit: "门")
                heroStat(
                    title: "GPA",
                    value: session.grades.isEmpty ? "—" : String(format: "%.2f", session.gpa),
                    unit: ""
                )
            }
        }
        .padding(AppTheme.spacing20)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusXLarge, style: .continuous)
                .fill(AppTheme.brandGradient)
                .shadow(color: AppTheme.brand.opacity(0.25), radius: 18, y: 10)
        )
    }

    private func heroStat(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    // MARK: - 今天的课

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            SectionHeader(title: "今天的课", subtitle: Weekday.full[session.selectedDay - 1]) {
                selection = .schedule
            }

            if !session.scheduleLoaded {
                LoadingCard(text: "正在加载课表…")
            } else if session.todayCourses.isEmpty {
                EmptyStateView(
                    icon: "cup.and.saucer",
                    title: "今天没有课",
                    message: "安心自习，或者去屁岱那里看看作业。"
                )
            } else {
                VStack(spacing: AppTheme.spacing8) {
                    ForEach(session.todayCourses) { course in
                        courseRow(course)
                    }
                }
            }
        }
    }

    private func courseRow(_ course: Course) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(course.color)
                .frame(width: 4, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(course.location) · \(course.teacher)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(sectionTimeText(course))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text("第 \(course.sectionRange) 节")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle(padding: AppTheme.spacing12, corner: AppTheme.radiusMedium)
    }

    private func sectionTimeText(_ course: Course) -> String {
        let start = SectionTime.of(course.startSection)?.start ?? "--:--"
        let end = SectionTime.of(course.endSection)?.end ?? "--:--"
        return "\(start)–\(end)"
    }

    // MARK: - 数据卡片

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            SectionHeader(title: "学业", subtitle: "来自教务系统") {
                selection = .score
            }

            HStack(spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("GPA")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(session.grades.isEmpty ? "—" : String(format: "%.2f", session.gpa))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.brand)
                    Text("4.3 制 · 加权")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: AppTheme.spacing16)

                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text("已修学分")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", session.earnedCredits))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accentGreen)
                    Text("共 \(session.grades.count) 门课")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: AppTheme.spacing16)
            }
        }
    }

    // MARK: - 快捷入口

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            SectionHeader(title: "快捷入口")
            HStack(spacing: AppTheme.spacing12) {
                quickButton(title: "课表", icon: "calendar", tint: AppTheme.brand) {
                    selection = .schedule
                }
                quickButton(title: "成绩", icon: "chart.bar.fill", tint: AppTheme.accentGreen) {
                    selection = .score
                }
                quickButton(title: "屁岱", icon: "sparkles", tint: AppTheme.accentOrange) {
                    selection = .agent
                }
                quickButton(title: "设置", icon: "gearshape.fill", tint: Color(uiColor: .systemGray)) {
                    selection = .me
                }
            }
        }
    }

    private func quickButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: AppTheme.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 说明

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            SectionHeader(title: "关于这个版本")
            Text(
                "这是「岱宗盒子」的 iOS 重写版：登录、课表、成绩、AI 助手已经可以用；" +
                "校园卡、图书馆座位、思源学堂等模块还在移植中，界面上会明确标注。" +
                "所有数据直接来自学校系统，不经过第三方服务器。"
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .cardStyle(padding: AppTheme.spacing16)
        }
    }
}
