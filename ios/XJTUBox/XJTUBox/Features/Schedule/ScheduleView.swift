//
//  ScheduleView.swift
//  XJTUBox
//
//  课表：周次切换 + 7 列网格。iPhone 竖屏按可用宽度等分，横屏/大屏自动放宽。
//

import SwiftUI

struct ScheduleView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.pageMetrics) private var metrics

    private let timeColumnWidth: CGFloat = 34
    private let rowHeight: CGFloat = 46

    private var totalWeeks: Int {
        session.term?.effectiveTotalWeeks ?? 20
    }

    var body: some View {
        PageScaffold(
            title: "课表",
            subtitle: subtitle,
            showsRefresh: true,
            onRefresh: { Task { await session.loadSchedule() } }
        ) {
            weekStrip
            if let error = session.lastError, !session.scheduleLoaded {
                ErrorBanner(message: error) {
                    Task { await session.loadSchedule() }
                }
            }
            if session.scheduleLoaded {
                grid
                legend
            } else {
                LoadingCard(text: "正在加载课表…")
            }
        }
    }

    private var subtitle: String {
        let term = session.term?.name ?? "本学期"
        return "\(term) · 第 \(session.week) 周"
    }

    // MARK: - 周次

    private var weekStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacing8) {
                    ForEach(1...totalWeeks, id: \.self) { week in
                        weekChip(week)
                            .id(week)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(session.week, anchor: .center)
            }
        }
    }

    private func weekChip(_ week: Int) -> some View {
        let selected = week == session.week
        let isCurrent = week == (session.term?.week(of: Date()) ?? session.week)
        return Button {
            withAnimation(AppTheme.springSnappy) { session.week = week }
        } label: {
            VStack(spacing: 2) {
                Text("\(week)")
                    .font(.system(size: 15, weight: selected ? .bold : .medium, design: .rounded))
                Text(weekLabel(week))
                    .font(.system(size: 9))
                    .opacity(selected ? 0.85 : 0.55)
            }
            .frame(width: 44, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? AppTheme.brand : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isCurrent && !selected ? AppTheme.brand.opacity(0.5) : .clear,
                        lineWidth: 1.2
                    )
            )
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func weekLabel(_ week: Int) -> String {
        guard let start = session.term?.startDate,
              let date = Calendar.current.date(byAdding: .day, value: (week - 1) * 7, to: start) else {
            return "周"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    // MARK: - 网格

    private var grid: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - timeColumnWidth
            let columnWidth = max(available / 7, 38)

            VStack(spacing: 0) {
                dayHeader(columnWidth: columnWidth)
                ZStack(alignment: .topLeading) {
                    backgroundGrid(columnWidth: columnWidth)
                    courseBlocks(columnWidth: columnWidth)
                }
                .frame(height: rowHeight * 11)
            }
        }
        .frame(height: rowHeight * 11 + 34)
    }

    private func dayHeader(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("节")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: timeColumnWidth)
            ForEach(1...7, id: \.self) { day in
                let isToday = day == Weekday.current()
                VStack(spacing: 1) {
                    Text(Weekday.short[day - 1])
                        .font(.system(size: 12, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? AppTheme.brand : .secondary)
                }
                .frame(width: columnWidth, height: 30)
            }
        }
    }

    private func backgroundGrid(columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(1...11, id: \.self) { section in
                let y = CGFloat(section - 1) * rowHeight
                HStack(spacing: 0) {
                    Text("\(section)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: timeColumnWidth, height: rowHeight)
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 0.5)
                        .offset(y: -rowHeight / 2)
                }
                .offset(y: y)
            }

            // 今天那一列淡淡高亮
            let todayIndex = Weekday.current() - 1
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.brand.opacity(0.05))
                .frame(width: columnWidth - 2, height: rowHeight * 11)
                .offset(x: timeColumnWidth + CGFloat(todayIndex) * columnWidth + 1)
        }
    }

    private func courseBlocks(columnWidth: CGFloat) -> some View {
        let courses = session.coursesThisWeek
        return ZStack(alignment: .topLeading) {
            ForEach(Array(courses.enumerated()), id: \.offset) { _, course in
                let x = timeColumnWidth + CGFloat(course.dayOfWeek - 1) * columnWidth + 1
                let y = CGFloat(course.startSection - 1) * rowHeight + 1
                let height = CGFloat(course.endSection - course.startSection + 1) * rowHeight - 3

                VStack(alignment: .leading, spacing: 1) {
                    Text(course.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text(course.location)
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .opacity(0.75)
                }
                .padding(4)
                .frame(width: columnWidth - 3, height: max(height, 20), alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(course.color.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(course.color.opacity(0.45), lineWidth: 0.8)
                )
                .foregroundStyle(course.color)
                .offset(x: x, y: y)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text("左右滑动切换周次；本周共 \(session.coursesThisWeek.count) 个上课时段。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, AppTheme.spacing4)
    }
}
