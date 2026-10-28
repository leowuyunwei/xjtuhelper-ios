# 没有 Mac 怎么把它装到 iPhone 上

iOS 应用不可能在 Windows 上编译——`SwiftUI` / `UIKit` 这些框架只随 Xcode 发布、只在 macOS 上可用。
但「不需要 Mac」不等于「不需要 macOS」：把编译这一步租出去就行。下面两条路都是真的能走通的。

---

## 路线 A：GitHub Actions（免费，推荐）

GitHub 给公开仓库每月 2000 分钟 macOS 机器，编这个小项目大约 3–5 分钟一次，等于白嫖。

### 1. 推一个仓库

把 `ios/XJTUBox/` **这个目录**当作仓库根（里面有 `XJTUBox.xcodeproj`、`XJTUBox/`、`.github/workflows/build.yml`）：

```bash
cd ios/XJTUBox
git init && git add -A && git commit -m "iOS port"
git remote add origin https://github.com/<你的用户名>/xjtu-toolbox-ios.git
git push -u origin main
```

> 推送时如果卡在 github.com 连不上，用 `git config --global http.proxy` 挂你自己的代理，或者用 Gitee 的镜像 + 手动触发。

### 2. 触发构建

打开仓库 → **Actions** → 左侧 `Build iOS IPA` → **Run workflow**。
3–5 分钟后，页面底部 **Artifacts** 里会有一个 `XJTUBox-unsigned-ipa`，下载解压得到 `XJTUBox-unsigned.ipa`。

如果红了，点开 `Build (unsigned, device)` 那一步，把报错贴给我——第一次编译大概率有几处类型错误，我按报错改。

### 3. 在 Windows 上签名并安装

iOS 必须签名才能装。**签名可以在 Windows 上完成**，不需要 Mac：

| 工具 | 需要 | 有效期 |
|---|---|---|
| [SideStore](https://sidestore.io) | Windows 装好 iTunes + iCloud，手机装 SideStore | 7 天，自动续期 |
| [AltStore](https://altstore.io) | Windows 装 AltServer（同上） | 7 天，手动续 |
| 付费开发者账号 | 99 美元/年 | 1 年 |

流程（SideStore 为例）：
1. Windows 上装 iTunes（**官网版**，不是 Microsoft Store 版）和 iCloud
2. 手机装 SideStore（用 Safari 打开官网的安装链接，通过 AltServer 推过去）
3. 手机「设置 → 通用 → VPN与设备管理」信任你的 Apple ID
4. 把 `XJTUBox-unsigned.ipa` 传到手机（AirDrop / 文件 App / 局域网），在 SideStore 里「+」选中它，用你的 Apple ID 签名安装

免费账号的限制：**7 天过期**、同时最多 3 个自签 App。SideStore 可以在同一 Wi-Fi 下自动续期。

---

## 路线 B：租一小时云 Mac

如果你不想把代码推 GitHub，可以按小时租 macOS：Scaleway、MacinCloud、AWS EC2 mac 实例都行，
便宜的几元到十几元一小时，**30 分钟足够装好 Xcode 并传出 ipa**。

拿到云 Mac 后：

```bash
# 1. 传代码（scp / 私有仓库 clone）
# 2. 装 Xcode（App Store，约 10 分钟）
# 3. 打开工程，Signing 里登录你的 Apple ID，⌘R —— 直接装到你插着的 iPhone 上
```

云 Mac 的 USB 不通，所以「直接装到手机」这条路走不了；只能在云上编出未签名 ipa 再走路线 A 第 3 步的签名流程。
所以路线 A 其实更省事。

---

## 路线 C：别折腾 iOS 了（如果你只是想用）

说实话，如果你的目标只是「在 iPhone 上查课表、看成绩」，还有个折中方案：
把这个 App 做成 **PWA**（Safari 添加到主屏幕，不需要签名、不需要编译）。

但它有个硬伤：学校接口不返回 CORS 头，Safari 里的网页直接请求 `jwxt.xjtu.edu.cn` 会被浏览器拦掉，
必须自己搭一个同源反向代理。也就是说 PWA 版要么放弃「不经过第三方服务器」这条底线，
要么你得有一台自己的服务器。原生 App 没有这个问题（App 内部的网络请求不受 CORS 限制）。

所以我仍然建议走路线 A。

---

## 参数说明

- **部署目标**：`IPHONEOS_DEPLOYMENT_TARGET = 18.0`。用 iOS 18 SDK 编出来的 App 可以直接跑在 iOS 27 上。
  想只支持最新系统，把它改成 `27.0`（需要 Xcode 27）。
- **工作流里的机器**：`macos-15`（Xcode 16.x，带 iOS 18 SDK）。如果日后 GitHub 只剩更新的镜像，
  把 `runs-on` 改成 `macos-latest`，并在 `Build` 步骤前加一步 `sudo xcode-select -s /Applications/Xcode.app`。
- **签名 secrets**：`.github/workflows/build.yml` 下半段有一个 `sign` job，默认 `if: false` 关着。
  有付费开发者账号时，按注释配 4 个 secrets 再打开，就能直接产出可安装的 ipa。
