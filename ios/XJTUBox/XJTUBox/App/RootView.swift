//
//  RootView.swift
//  XJTUBox
//
//  根视图：启动页 → 登录页 → 主界面（自绘玻璃底栏）。
//

import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var tab: RootTab = .home

    var body: some View {
        GeometryReader { proxy in
            let metrics = PageMetrics(
                width: proxy.size.width,
                isLandscape: proxy.size.width > proxy.size.height
            )
            Group {
                switch session.phase {
                case .launching:
                    LaunchView()
                case .signedOut:
                    LoginView()
                case .signedIn:
                    MainTabs(selection: $tab)
                }
            }
            .environment(\.pageMetrics, metrics)
            .animation(AppTheme.springSoft, value: session.phase)
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            AppTheme.brandGradient.ignoresSafeArea()
            VStack(spacing: AppTheme.spacing16) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
                Text("岱宗盒子")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

private struct MainTabs: View {
    @Binding var selection: RootTab
    @Environment(AppSession.self) private var session

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassTabBar(selection: $selection)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .home:
            HomeView(selection: $selection)
        case .schedule:
            ScheduleView()
        case .score:
            ScoreView()
        case .agent:
            AgentView()
        case .me:
            SettingsView()
        }
    }
}
