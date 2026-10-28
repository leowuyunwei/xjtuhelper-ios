//
//  Components.swift
//  XJTUBox
//
//  通用 UI 组件：页面骨架、卡片标题、空态、错误态、加载态、玻璃底栏。
//

import SwiftUI

// MARK: - 页面骨架

/// 统一的页面容器：滚动 + 背景 + 限宽 + 左右留白。
struct PageScaffold<Content: View>: View {
    @Environment(\.pageMetrics) private var metrics

    var title: String?
    var subtitle: String?
    var showsRefresh: Bool = false
    var onRefresh: (() -> Void)?
    var content: () -> Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        showsRefresh: Bool = false,
        onRefresh: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsRefresh = showsRefresh
        self.onRefresh = onRefresh
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                if let title {
                    header(title: title, subtitle: subtitle)
                }
                content()
            }
            .padding(.horizontal, AppTheme.pagePadding(for: metrics.width))
            .padding(.top, AppTheme.spacing8)
            .padding(.bottom, AppTheme.spacing32)
            .readableWidth()
        }
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func header(title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(title)
                    .font(AppTheme.largeTitle(for: metrics.width))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.captionText)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if showsRefresh, let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.thinMaterial))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新")
            }
        }
        .padding(.bottom, AppTheme.spacing2)
    }
}

// MARK: - 卡片标题

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var action: (() -> Void)?
    var actionTitle: String = "全部"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.spacing8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(AppTheme.captionText)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.brand)
            }
        }
    }
}

// MARK: - 状态视图

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String?

    var body: some View {
        VStack(spacing: AppTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(AppTheme.captionText)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.spacing32)
    }
}

struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.accentOrange)
            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(message)
                    .font(AppTheme.captionText)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button("重试", action: retry)
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.brand)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                .fill(AppTheme.accentOrange.opacity(0.12))
        )
    }
}

struct LoadingCard: View {
    var text: String = "加载中…"

    var body: some View {
        HStack(spacing: AppTheme.spacing12) {
            ProgressView()
            Text(text)
                .font(AppTheme.captionText)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .cardStyle(padding: AppTheme.spacing16)
    }
}

// MARK: - 玻璃底栏

struct GlassTabBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases) { tab in
                Button {
                    withAnimation(AppTheme.springSnappy) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? AppTheme.brand : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, AppTheme.spacing8)
        .padding(.horizontal, AppTheme.spacing8)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.separator.opacity(0.5))
                .frame(height: 0.5)
        }
    }
}

// MARK: - 小工具

/// 带图标 + 标题 + 可选副标题 + 右侧箭头的一行。
struct NavRow: View {
    var icon: String
    var title: String
    var subtitle: String?
    var tint: Color = AppTheme.brand

    var body: some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.bodyText)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// 数据小标签：标题 + 数值。
struct StatTile: View {
    var title: String
    var value: String
    var unit: String?
    var tint: Color = AppTheme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
