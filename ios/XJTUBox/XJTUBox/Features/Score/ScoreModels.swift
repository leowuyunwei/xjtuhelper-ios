//
//  ScoreModels.swift
//  XJTUBox
//
//  成绩模型与 GPA 计算。
//

import Foundation

struct Grade: Identifiable, Hashable {
    let id: String
    let courseName: String
    /// 形如 `2025-2026-1`。
    let termCode: String
    /// 百分制成绩；等级制课程为 nil。
    let score: Double?
    /// 教务给的绩点（XFJD）。
    let gpaPoint: Double?
    let credit: Double
    /// 等级制成绩的文字，例如「优秀」「通过」。
    let gradeName: String
    let passed: Bool
    let courseCode: String

    var scoreText: String {
        if let score { return ScoreFormatter.format(score) }
        return gradeName.isEmpty ? "—" : gradeName
    }

    var gpaText: String {
        guard let gpaPoint else { return "—" }
        return String(format: "%.2f", gpaPoint)
    }

    var creditText: String {
        credit > 0 ? String(format: "%.1f", credit) : "—"
    }

    /// 没有 XFJD 时按成绩本地换算（4.0 制，60 分及格线）。
    var effectiveGpa: Double {
        if let gpaPoint, gpaPoint > 0 { return gpaPoint }
        if let score { return ScoreCalculator.gpa(fromScore: score) }
        return 0
    }
}

enum ScoreFormatter {
    static func format(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

enum ScoreCalculator {
    /// 西安交大 4.3 制换算（西交教〔2015〕87 号，与 Android 版 ScoreCalculator 一致）。
    static func gpa(fromScore score: Double) -> Double {
        switch score {
        case 95...: return 4.3
        case 90..<95: return 4.0
        case 85..<90: return 3.7
        case 81..<85: return 3.3
        case 78..<81: return 3.0
        case 75..<78: return 2.7
        case 72..<75: return 2.3
        case 68..<72: return 2.0
        case 64..<68: return 1.7
        case 60..<64: return 1.3
        default: return 0
        }
    }

    /// 是否参与 GPA：「通过 / 不通过」这类等级制课程不计入。
    static func countsTowardGPA(_ grade: Grade) -> Bool {
        let text = grade.gradeName.trimmingCharacters(in: .whitespaces)
        if text == "通过" || text == "不通过" { return false }
        if grade.score == nil && grade.gpaPoint == nil { return false }
        return true
    }

    static func weightedGPA(_ grades: [Grade]) -> Double {
        var totalCredit = 0.0
        var totalPoints = 0.0
        for grade in grades where grade.credit > 0 && countsTowardGPA(grade) {
            // 「不合格」仍然要进分母（与安卓端口径一致：分母算学分，分子只算绩点）
            guard grade.passed || grade.score != nil else { continue }
            totalCredit += grade.credit
            if grade.passed {
                totalPoints += grade.credit * grade.effectiveGpa
            }
        }
        guard totalCredit > 0 else { return 0 }
        return totalPoints / totalCredit
    }

    static func totalCredits(_ grades: [Grade]) -> Double {
        grades.reduce(0) { $0 + $1.credit }
    }

    static func earnedCredits(_ grades: [Grade]) -> Double {
        grades.filter { $0.passed }.reduce(0) { $0 + $1.credit }
    }
}
