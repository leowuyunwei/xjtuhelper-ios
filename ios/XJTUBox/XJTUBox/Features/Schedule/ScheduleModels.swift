//
//  ScheduleModels.swift
//  XJTUBox
//
//  课表数据模型与本地推导逻辑（周次、节次时间、颜色）。
//

import Foundation
import SwiftUI

/// 一门课在课表里的一次排课。
struct Course: Identifiable, Hashable {
    let id: String
    let name: String
    let teacher: String
    let location: String
    let courseCode: String
    let courseType: String
    /// 教务原始的周次位串，例如 `111111111111111100`（第 1 位是第 1 周）。
    let weekBits: String
    let dayOfWeek: Int
    let startSection: Int
    let endSection: Int

    /// 解析出的周集合。位串异常时退化成「全学期都上」，避免整张课表空白。
    var weeks: Set<Int> {
        let cleaned = weekBits.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count >= 2,
              cleaned.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            return Set(1...20)
        }
        var result = Set<Int>()
        for (offset, char) in cleaned.enumerated() where char == "1" {
            result.insert(offset + 1)
        }
        return result
    }

    func occurs(inWeek week: Int) -> Bool {
        weeks.contains(week)
    }

    var sectionRange: String {
        startSection == endSection ? "\(startSection)" : "\(startSection)-\(endSection)"
    }

    /// 按课程名稳定取色，同一门课每次渲染颜色一致。
    var color: Color {
        CoursePalette.color(for: name)
    }
}

enum CoursePalette {
    private static let colors: [Color] = [
        Color(red: 0.24, green: 0.48, blue: 0.92),
        Color(red: 0.16, green: 0.66, blue: 0.52),
        Color(red: 0.94, green: 0.55, blue: 0.22),
        Color(red: 0.78, green: 0.35, blue: 0.55),
        Color(red: 0.36, green: 0.42, blue: 0.78),
        Color(red: 0.20, green: 0.60, blue: 0.72),
        Color(red: 0.86, green: 0.42, blue: 0.32),
        Color(red: 0.52, green: 0.46, blue: 0.80),
    ]

    static func color(for seed: String) -> Color {
        var hash = 5381
        for scalar in seed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        let index = abs(hash) % colors.count
        return colors[index]
    }
}

/// 学期信息（起点日期 + 总周数），用来算「第几周」。
struct TermInfo: Equatable {
    var code: String
    var name: String
    var startDate: Date?
    var totalWeeks: Int

    var effectiveTotalWeeks: Int {
        totalWeeks > 0 && totalWeeks <= 30 ? totalWeeks : 20
    }

    /// 今天落在第几周。学期还没开始返回 1；已结束返回总周数。
    func week(of date: Date, calendar: Calendar = .current) -> Int {
        guard let startDate else { return 1 }
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        let week = days / 7 + 1
        return min(max(week, 1), effectiveTotalWeeks)
    }
}

/// 作息时间。与学校本科课表一致（每节 45 分钟）。
struct SectionTime {
    let index: Int
    let start: String
    let end: String

    static let all: [SectionTime] = [
        .init(index: 1, start: "08:00", end: "08:45"),
        .init(index: 2, start: "08:50", end: "09:35"),
        .init(index: 3, start: "09:50", end: "10:35"),
        .init(index: 4, start: "10:40", end: "11:25"),
        .init(index: 5, start: "11:30", end: "12:15"),
        .init(index: 6, start: "14:00", end: "14:45"),
        .init(index: 7, start: "14:50", end: "15:35"),
        .init(index: 8, start: "15:50", end: "16:35"),
        .init(index: 9, start: "16:40", end: "17:25"),
        .init(index: 10, start: "17:30", end: "18:15"),
        .init(index: 11, start: "19:00", end: "19:45"),
        .init(index: 12, start: "19:50", end: "20:35"),
        .init(index: 13, start: "20:40", end: "21:25"),
    ]

    static func of(_ index: Int) -> SectionTime? {
        all.first { $0.index == index }
    }
}

enum Weekday {
    static let short = ["一", "二", "三", "四", "五", "六", "日"]
    static let full = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 教务的 1 = 周一 … 7 = 周日。
    static func current(from date: Date = Date(), calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1 = 周日
        return weekday == 1 ? 7 : weekday - 1
    }
}
