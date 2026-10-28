//
//  Theme.swift
//  XJTUBox
//
//  设计令牌：颜色、圆角、间距、字体。
//  取色参考原 Android 版 MIUIX 主题：大圆角卡片 + 半透明材质 + 跟随系统深浅色。
//

import SwiftUI

enum AppTheme {
    // MARK: - 间距

    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    /// 页面左右留白。iPhone 竖屏 20pt，横屏/大屏略大。
    static func pagePadding(for width: CGFloat) -> CGFloat {
        if width > 900 { return 32 }
        if width > 600 { return 24 }
        return 20
    }

    /// 大屏上限宽，避免 iPad / 横屏把一行拉得过长。
    static let contentMaxWidth: CGFloat = 720

    // MARK: - 圆角

    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 22
    static let radiusXLarge: CGFloat = 28

    // MARK: - 品牌色

    static let brand = Color(red: 0.09, green: 0.36, blue: 0.78)
    static let brandLight = Color(red: 0.32, green: 0.60, blue: 0.95)
    static let accentOrange = Color(red: 0.96, green: 0.55, blue: 0.16)
    static let accentGreen = Color(red: 0.16, green: 0.66, blue: 0.45)
    static let accentRed = Color(red: 0.86, green: 0.24, blue: 0.24)

    /// 品牌渐变（登录页、首页头图）。
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brand, brandLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - 语义色

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator)

    // MARK: - 字体

    /// 大标题（页面主标题）。iPhone 17 Pro Max 这类大屏上略放大。
    static func largeTitle(for width: CGFloat) -> Font {
        .system(size: width > 600 ? 34 : 30, weight: .bold, design: .rounded)
    }

    static let cardTitle = Font.system(size: 17, weight: .semibold)
    static let bodyText = Font.system(size: 15, weight: .regular)
    static let captionText = Font.system(size: 13, weight: .regular)
    static let monoNumber = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()

    // MARK: - 动画

    static let springSnappy = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let springSoft = Animation.spring(response: 0.46, dampingFraction: 0.9)
}

extension View {
    /// 标准卡片：材质背景 + 大圆角 + 细描边。
    func cardStyle(padding: CGFloat = AppTheme.spacing16, corner: CGFloat = AppTheme.radiusLarge) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
            )
    }

    /// 只有一行的列表容器（设置页那种）。
    func insetGroupStyle() -> some View {
        self
            .padding(.horizontal, AppTheme.spacing16)
            .padding(.vertical, AppTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    /// 限制内容宽度并居中，大屏适配的关键。
    func readableWidth(_ maxWidth: CGFloat = AppTheme.contentMaxWidth) -> some View {
        self.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}

/// 页面尺寸信息，供布局按屏幕宽度微调（iPhone 17 Pro Max 竖屏约 440pt 宽）。
struct PageMetrics: Equatable {
    var width: CGFloat = 393
    var isLandscape: Bool = false

    var isWide: Bool { width > 600 }
    var isLargePhone: Bool { width >= 420 }
}

private struct PageMetricsKey: EnvironmentKey {
    static let defaultValue = PageMetrics()
}

extension EnvironmentValues {
    var pageMetrics: PageMetrics {
        get { self[PageMetricsKey.self] }
        set { self[PageMetricsKey.self] = newValue }
    }
}
