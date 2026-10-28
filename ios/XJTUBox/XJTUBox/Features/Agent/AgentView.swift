//
//  AgentView.swift
//  XJTUBox
//
//  「屁岱」对话界面：流式输出、上下文注入、可按需清空。
//

import SwiftUI

struct AgentView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.pageMetrics) private var metrics

    @State private var messages: [AgentMessage] = []
    @State private var input: String = ""
    @State private var streaming: Bool = false
    @State private var errorText: String?
    @State private var showSettings = false

    private let service = AgentService()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                        if messages.isEmpty {
                            welcome
                        }
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        if let errorText {
                            ErrorBanner(message: errorText)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, AppTheme.pagePadding(for: metrics.width))
                    .padding(.vertical, AppTheme.spacing16)
                    .readableWidth()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    withAnimation(AppTheme.springSoft) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            composer
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            AgentSettingsSheet()
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("屁岱")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(session.agentModel.isEmpty ? "未配置模型" : session.agentModel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.thinMaterial))
            }
            .buttonStyle(.plain)

            if !messages.isEmpty {
                Button {
                    messages.removeAll()
                    errorText = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.thinMaterial))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.pagePadding(for: metrics.width))
        .padding(.vertical, AppTheme.spacing12)
    }

    // MARK: - 空态

    private var welcome: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text("我是屁岱")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("可以查课表、算 GPA、讲清楚哪门课在哪儿上，也可以就校园生活随便聊。")
                    .font(AppTheme.bodyText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppTheme.spacing8) {
                suggestion("我这周还有几节课？")
                suggestion("帮我算一下现在的加权 GPA")
                suggestion("明天要带什么书去上课？")
                suggestion("给我一个复习本周课程的计划")
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                Text("请求会发给你自己配置的模型服务，请使用可信服务商并保管好 API Key。")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.top, AppTheme.spacing16)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            input = text
            Task { await send() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accentOrange)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 气泡

    private func bubble(_ message: AgentMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content.isEmpty ? "…" : message.content)
                .font(AppTheme.bodyText)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, AppTheme.spacing12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                        .fill(message.role == .user
                              ? AnyShapeStyle(AppTheme.brand)
                              : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    // MARK: - 输入

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(alignment: .bottom, spacing: AppTheme.spacing8) {
                TextField("问点什么…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .font(AppTheme.bodyText)
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: streaming ? "hourglass" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(input.isEmpty || streaming ? Color.gray.opacity(0.4) : AppTheme.brand)
                        )
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || streaming)
            }
            .padding(.horizontal, AppTheme.pagePadding(for: metrics.width))
            .padding(.vertical, AppTheme.spacing8)
            .readableWidth()
        }
        .background(.regularMaterial)
    }

    // MARK: - 发送

    @MainActor
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !streaming else { return }
        input = ""
        errorText = nil
        messages.append(AgentMessage(role: .user, content: text))
        let placeholder = AgentMessage(role: .assistant, content: "")
        messages.append(placeholder)
        streaming = true

        let context = AgentService.contextSummary(session: session)
        let history = messages.filter { $0.role == .user || !$0.content.isEmpty }
        let stream = service.stream(
            messages: history,
            context: context,
            baseURL: session.agentBaseURL,
            model: session.agentModel,
            apiKey: session.agentKey
        )

        do {
            for try await chunk in stream {
                if let index = messages.lastIndex(where: { $0.id == placeholder.id }) {
                    messages[index].content += chunk
                }
            }
        } catch {
            errorText = error.localizedDescription
            if let index = messages.lastIndex(where: { $0.id == placeholder.id }),
               messages[index].content.isEmpty {
                messages.remove(at: index)
            }
        }
        streaming = false
    }
}

// MARK: - 模型设置

struct AgentSettingsSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var session = session

        NavigationStack {
            Form {
                Section("接口") {
                    TextField("https://api.deepseek.com/v1", text: $session.agentBaseURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("模型名，例如 deepseek-chat", text: $session.agentModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Key", text: $session.agentKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Text("兼容任意 OpenAI Chat Completions 接口：DeepSeek、Kimi、通义、自建网关都可以。Key 只存在本机钥匙串。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("提示词") {
                    Text(Prefs.agentSystemPrompt)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("屁岱设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        session.saveAgentSettings()
                        dismiss()
                    }
                }
            }
        }
    }
}
