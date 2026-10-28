//
//  LoginView.swift
//  XJTUBox
//
//  登录页：学号 + 密码 → 可能需要短信验证码（MFA）→ 进主界面。
//

import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.pageMetrics) private var metrics

    @State private var username = ""
    @State private var password = ""
    @State private var captcha = ""
    @State private var smsCode = ""
    @State private var showPassword = false
    @State private var errorText: String?
    @State private var working = false

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: AppTheme.spacing24) {
                    Spacer(minLength: 40)
                    header
                    credentialCard
                    if let mfaPhone = session.mfaPhone, !mfaPhone.isEmpty {
                        mfaCard(phone: mfaPhone)
                    }
                    if session.needCaptcha {
                        captchaField
                    }
                    if let errorText {
                        ErrorBanner(message: errorText)
                    }
                    submitButton
                    footer
                }
                .padding(.horizontal, AppTheme.pagePadding(for: metrics.width))
                .padding(.bottom, AppTheme.spacing32)
                .readableWidth(520)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            if username.isEmpty { username = session.username }
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.brand.opacity(0.95),
                    AppTheme.brandLight.opacity(0.85),
                    Color(uiColor: .systemGroupedBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: -120, y: -220)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: AppTheme.spacing12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )

            Text("岱宗盒子")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("西安交通大学校园工具箱 · iOS 版")
                .font(AppTheme.captionText)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.bottom, AppTheme.spacing8)
    }

    // MARK: - 表单

    private var credentialCard: some View {
        VStack(spacing: 0) {
            fieldRow(icon: "person", title: "学号") {
                TextField("例如 2124110000", text: $username)
                    .textContentType(.username)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
            }
            Divider().opacity(0.4)
            fieldRow(icon: "lock", title: "密码") {
                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("统一身份认证密码", text: $password)
                        } else {
                            SecureField("统一身份认证密码", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLarge, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLarge, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var captchaField: some View {
        fieldRow(icon: "checkmark.shield", title: "图形验证码") {
            TextField("连续失败后需要", text: $captcha)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.trailing)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private func mfaCard(phone: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
            HStack(spacing: 8) {
                Image(systemName: "message.badge.filled.fill")
                    .foregroundStyle(AppTheme.brand)
                Text("短信验证")
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Text(phone)
                    .font(AppTheme.captionText)
                    .foregroundStyle(.secondary)
            }
            Text("学校统一认证要求二次验证，验证码会发送到上面这个号码。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppTheme.spacing12) {
                TextField("6 位验证码", text: $smsCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .padding(.horizontal, AppTheme.spacing12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    )
                Button(session.mfaSent ? "重新发送" : "发送验证码") {
                    Task { await session.sendSMSCode() }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.brand)
                .disabled(working)
            }

            Button {
                Task { await submitSMS() }
            } label: {
                Text("验证并登录")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                            .fill(AppTheme.brand)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(smsCode.count < 4 || working)
        }
        .cardStyle(padding: AppTheme.spacing16)
    }

    private func fieldRow<T: View>(icon: String, title: String, @ViewBuilder field: () -> T) -> some View {
        HStack(spacing: AppTheme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(AppTheme.bodyText)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            field()
                .font(AppTheme.bodyText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacing16)
        .padding(.vertical, 14)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if working {
                    ProgressView().tint(.white)
                }
                Text(working ? "登录中…" : "登录")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLarge, style: .continuous)
                    .fill(AppTheme.brandGradient)
            )
            .foregroundStyle(.white)
            .opacity(working ? 0.75 : 1)
        }
        .buttonStyle(.plain)
        .disabled(working || username.isEmpty || password.isEmpty)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("账号密码只在设备与学校系统之间传输，不经过任何第三方服务器。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Text("非西安交通大学官方应用，使用前请阅读原项目许可（GPL-3.0）。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppTheme.spacing8)
    }

    // MARK: - 动作

    private func submit() async {
        guard !working else { return }
        working = true
        errorText = nil
        defer { working = false }
        do {
            try await session.signIn(username: username, password: password, captcha: captcha)
        } catch {
            // MFA 不是错误：界面会切到验证码卡片
            if case LoginError.needMFA = error {
                return
            }
            errorText = error.localizedDescription
        }
    }

    private func submitSMS() async {
        guard !working else { return }
        working = true
        errorText = nil
        defer { working = false }
        do {
            try await session.submitSMSCode(smsCode)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
