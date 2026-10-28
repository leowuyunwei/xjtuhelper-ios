//
//  XJTUBoxApp.swift
//  XJTUBox
//
//  应用入口。会话对象在 App 层创建，注入到环境里。
//

import SwiftUI

@main
struct XJTUBoxApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.bootstrap() }
        }
    }
}
