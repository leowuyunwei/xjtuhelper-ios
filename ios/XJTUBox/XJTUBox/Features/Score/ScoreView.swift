//
//  ScoreView.swift
//  XJTUBox
//
//  成绩：总览 + 按学期分组的课程列表。
//

import SwiftUI

struct ScoreView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.pageMetrics) private var metrics

    @State private var showOnlyPassed = false

    private var groupedTerms: [(term: String, grades: [Grade])] {
        var buckets: [String: [Grade]] = [:]
        for grade in session.grades {
            let term = grade.termCode.isEmpty ? "未知学期" : grade.termCode
            buckets[term, default: []].append(grade)
        }
        return buckets
            .map { (term: $0.key, grades: $0.value.sorted { $0.courseName < $1.courseName }) }
            .sorted { $0.term > $1.term }
    }

    var body: some View {
        PageScaffold(
            title: "成绩",
            subtitle: session.grades.isEmpty ? nil : "\(session.grades.count) 门课程",
            showsRefresh: true,
            onRefresh: { Task { await session.loadGrades() } }
        ) {
            summaryCard

            if let error = session.lastError, session.grades.isEmpty {
                ErrorBanner(message: error) {
                    Task { await session.loadGrades() }
                }
            }

            if !session.gradesLoaded {
                LoadingCard(text: "正在加载成绩…")
            } else if session.grades.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "还没有成绩",
                    message: "教务系统暂时没有返回成绩，或者尚未评教。"
                )
            } else {
                ForEach(groupedTerms, id: \.term) { group in
                    termSection(term: group.term, grades: group.grades)
                }
                footerNote
            }
        }
    }

    // MARK: - 总览

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing8) {
                Text(String(format: "%.2f", session.gpa))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("GPA")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                Text("4.3 制")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: AppTheme.spacing20) {
                summaryItem(title: "已修学分", value: String(format: "%.1f", session.earnedCredits))
                summaryItem(title: "课程数", value: "\(session.grades.count)")
                summaryItem(
                    title: "不及格",
                    value: "\(session.grades.filter { !$0.passed }.count)"
                )
            }
        }
        .padding(AppTheme.spacing20)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusXLarge, style: .continuous)
                .fill(AppTheme.brandGradient)
        )
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 学期分组

    private func termSection(term: String, grades: [Grade]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing8) {
            HStack(alignment: .firstTextBaseline) {
                Text(termDisplay(term))
                    .font(.system(size: 14, weight: .semibold))
                Text("\(grades.count) 门")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Text(String(format: "%.2f", ScoreCalculator.weightedGPA(grades)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.brand)
            }
            .padding(.top, AppTheme.spacing4)

            VStack(spacing: 0) {
                ForEach(Array(grades.enumerated()), id: \.element.id) { index, grade in
                    gradeRow(grade)
                    if index < grades.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    private func gradeRow(_ grade: Grade) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.courseName)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !grade.gradeName.isEmpty && grade.score != nil {
                        Text(grade.gradeName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(grade.creditText) 学分")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if !grade.courseCode.isEmpty {
                        Text(grade.courseCode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(grade.scoreText)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(scoreColor(grade))
                Text("绩点 \(grade.gpaText)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func scoreColor(_ grade: Grade) -> Color {
        if !grade.passed { return AppTheme.accentRed }
        guard let score = grade.score else { return .primary }
        if score >= 90 { return AppTheme.brand }
        if score >= 80 { return AppTheme.accentGreen }
        if score >= 60 { return .primary }
        return AppTheme.accentRed
    }

    private func termDisplay(_ code: String) -> String {
        let parts = code.split(separator: "-")
        guard parts.count == 3 else { return code }
        let season: String
        switch parts[2] {
        case "1": season = "秋季学期"
        case "2": season = "春季学期"
        case "3": season = "夏季学期"
        default: season = "学期 \(parts[2])"
        }
        return "\(parts[0])-\(parts[1]) \(season)"
    }

    private var footerNote: some View {
        Text(
            "GPA 采用学校 4.3 制加权算法（按学分加权，等级制「通过/不通过」不计入）。" +
            "数据来自教务系统，若与纸质成绩单不一致请以教务为准。"
        )
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, AppTheme.spacing8)
    }
}
