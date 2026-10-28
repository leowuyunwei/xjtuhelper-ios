# 岱宗盒子 · iOS

西安交通大学校园工具箱「岱宗盒子」的 iOS 重写版。原项目是 Kotlin + Jetpack Compose 的
[Android 应用](https://github.com/yeliqin666/xjtu-toolbox-android)；本项目用 SwiftUI 重新实现，
接口契约、字段映射和大部分交互逻辑都对齐 Android 版源码。

> 非西安交通大学官方应用。仅用于学习与个人信息管理，请遵守学校各系统的使用规则，不要高频请求。

---

## 现在能做什么

| 模块 | 状态 | 说明 |
|---|---|---|
| 统一身份认证登录 | ✅ | 新 CAS（login.xjtu.edu.cn）、RSA 加密密码、短信二次验证、账户身份选择 |
| 课表 | ✅ | 当前学期、周次切换、11 节网格、课程颜色、学期起点推算「第几周」 |
| 成绩 | ✅ | 教务精确成绩（xscjcx），按学期分组，4.3 制加权 GPA |
| 屁岱 AI 助手 | ✅ | 任意 OpenAI 兼容接口、流式输出、自动注入课表/成绩上下文 |
| 校园卡 / 付款码 | ⛔️ 待移植 | 接口契约已摸清（OAuth ticket + JWT），UI 未写 |
| 图书馆座位 / 空闲教室 | ⛔️ 待移植 | 接口是 HTML 抓取 + WebVPN，工作量大 |
| 思源学堂 / 通知聚合 | ⛔️ 待移植 | 29 个 HTML 源，需要逐个适配 |

界面上「我的 → 模块进度」会如实标注哪些能用、哪些没做，不会假装实现。

---

## 构建与安装（需要一台 Mac）

这个仓库只有 Swift 源码和一个 Xcode 工程，**Windows 上无法编译 iOS 应用**（Apple 的工具链只在 macOS 上）。
下面是最短路径：

### 1. 准备

- macOS + Xcode 16 或更新版本（App Store 装，首次启动要装附加组件）
- 一个 Apple ID（免费即可）

### 2. 打开工程

```bash
cd ios/XJTUBox
open XJTUBox.xcodeproj
```

工程用的是 **文件系统同步组（Xcode 16+）**：`XJTUBox/` 目录下新增的 `.swift` 文件会自动进入 target，
不需要手动往项目里拖。

> 如果你的 Xcode 版本较老、打不开这个工程，用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 重新生成：
> `brew install xcodegen && xcodegen generate`

### 3. 签名

1. 选中左侧 `XJTUBox` 工程 → `TARGETS: XJTUBox` → **Signing & Capabilities**
2. 勾上 `Automatically manage signing`
3. `Team` 选你的 Apple ID（没有就 `Add an Account…` 登录一下）
4. 如果 `Bundle Identifier` 冲突（默认 `com.xjtu.toolbox.ios`），改成 `com.<你的名字>.xjtu.toolbox`

### 4. 跑起来

- 真机：iPhone 用数据线连上，工具栏选你的设备 → `⌘R`
- 模拟器：选 `iPhone 17 Pro Max` → `⌘R`（模拟器上校园网接口大概率不通，只能看界面）

首次在真机上运行，iOS 会拦一次：**设置 → 通用 → VPN与设备管理 → 开发者 App → 信任你的 Apple ID**。

### 5. 免费证书的代价

用免费 Apple ID 签出来的 App 有效期 **7 天**、最多 3 个，过期后要重新 `⌘R` 一次。
长期使用有两条路：

| 方式 | 成本 | 说明 |
|---|---|---|
| 付费开发者账号 | 99 美元/年 | 有效期 1 年，可装 100 台设备，可用 TestFlight 分发 |
| SideStore / AltStore | 免费 | 在手机上自签续期，需要一台常开的电脑或配合 StosVPN |

---

## 代码结构

```
ios/XJTUBox/
├── XJTUBox.xcodeproj/          # 手写的 pbxproj（objectVersion 77 + 同步文件组）
├── project.yml                 # XcodeGen 备用描述文件
└── XJTUBox/
    ├── App/                    # 入口、根视图、全局会话（AppSession）
    ├── Core/
    │   ├── Auth/               # CAS 登录、RSA、HTML 表单解析
    │   ├── Network/            # URLSession 封装、错误分类
    │   └── Storage/            # 钥匙串、UserDefaults
    ├── Design/                 # 主题令牌与通用组件
    └── Features/
        ├── Auth/               # 登录页（含短信验证码）
        ├── Home/               # 首页仪表盘
        ├── Schedule/           # 课表接口 + 网格视图
        ├── Score/              # 成绩接口 + GPA
        ├── Agent/              # 屁岱（流式对话）
        └── Settings/           # 我的
```

### 关键实现点

- **登录**（`Core/Auth/CASLogin.swift`）：完全对齐 Android 版 `XJTULogin.kt`
  - `GET cas/login?service=…` 拿 `execution` 与 `mfaEnabled`
  - `POST cas/mfa/detect` 判断是否需要短信；`POST /cas/mfa/initByType/securephone` 取手机号与 `gid`
  - 密码用服务端下发的 PEM 公钥做 **RSA/PKCS#1 v1.5** 加密，加 `__RSA__` 前缀（`RSA.swift` 里手写 DER 拆包，不引第三方库）
  - `POST` 登录表单 → 401 / alert / Safety Verify 页面 / 账户选择页 分别处理
  - UA 固定为安卓客户端那一串：TGC 与 UA 绑定，换 UA 会导致登录态失效
- **课表**（`Features/Schedule/JwxtService.swift`）：`jwxt.xjtu.edu.cn` 的 `xskcb.do`，纯 Cookie 会话，
  周次用 `SKZC` 位串（`1111000011110000` 这种），学期起点来自 `cxjcs.do` 的 `XQKSRQ`
- **成绩**：`cjcx/modules/cjcx/xscjcx.do` 分页拉全量，GPA 用学校 4.3 制（95+ = 4.3），
  按学分加权，「通过/不通过」不计入
- **适配 iPhone 17 Pro Max**：不用固定尺寸，用 `PageMetrics`（屏幕宽度）+ 限宽 `readableWidth()`
  让 6.9 寸大屏不把一行拉得太散；横屏/ iPad 自动加宽留白；动态岛与 Home 指示条靠 `safeAreaInset` 处理；
  支持动态字号与深色模式

---

## 已知限制

1. **没有在真机上验证过**：代码是在 Windows 上写的，只做了语法级校验（tree-sitter Swift 语法树无错误），
   没有跑过 `xcodebuild`。第一次编译大概率需要修几处类型/API 细节。
2. **校外网络**：教务系统（jwxt）在校园网外可能不可达；Android 版有 WebVPN 自动切换，iOS 这版还没实现，
   校外使用时课程/成绩会加载失败（登录本身可以成）。
3. **账号身份**：同一学号同时有本科/研究生身份时，自动选「研究生」；如果选错会在界面上报错，
   需要到安卓版选一次。
4. **未移植的模块**：见上面的表格。它们的接口契约已经整理在 `docs/api-notes.md`，适合后续接着做。

---

## 想接着往下做？

`docs/api-notes.md` 里记了从 Android 源码里挖出来的接口细节（校园卡 OAuth、图书馆座位、空闲教室 CDN、
通知抓取的 29 个源、成绩合并与 GPA 公式），可以直接照着写。

许可：GPL-3.0，与原项目一致。
