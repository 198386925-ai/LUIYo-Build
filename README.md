# LUIYo 1.0.7 Build 84（原生层架构重写版）

原生层整体重写后的源码。业务逻辑与界面外观保持原样：**`YouYouLUI_iOS/YouYouLUI/Web/` 未做任何改动**（351KB 的 `index.html` 是图片处理、配色、规则数据与 ZIP 导出的实现，也是界面外观的来源）。

## 构建

与旧版一致，使用 GitHub 标准 macOS 15 Intel runner、Xcode 26.3、iOS 26 SDK：

```bash
bash scripts/build-ipa.sh      # 产出 output/LUIYo-1.0.7-Build(84).ipa（未签名）
```

也可以 Actions → Build LUIYo IPA → Run workflow 手动打包。IPA 未签名，安装前使用自己的签名方式。构建会检查 SDK 版本；仅完成编译不代表视觉验证通过，最终玻璃效果仍需看截图和真机。

## 新的原生层结构

旧版把 3000 多行塞进 `AppDelegate.swift` + `WebViewController.swift` 两个文件，UI、网络、桥接、材质渲染、CI 快照全部混在一起。重写后按职责分层（44 个 Swift 文件 + 2 个 Objective-C 文件）：

| 目录 | 职责 | 主要类型 |
| --- | --- | --- |
| `App/` | 进程入口、根控制器选择、Bundle 配置 | `AppDelegate`、`AppRoot`、`AppConfiguration` |
| `Activation/` | 授权全流程：注册、心跳、激活码、校验、设备码授权、封禁弹窗 | `ActivationSession`、`ActivationClient`、`ActivationGateViewController`、`BlockedPopupWindow`、`DeviceIdentity` |
| `Security/` | Keychain 令牌存储 | `KeychainStore` |
| `Shell/` | 三页容器：共享 WKWebView、Tab、页面切换、搜索浮层、CI 快照 | `MainShellViewController` + `ShellTabs` / `ShellWebPlacement` / `ShellAppearance` / `ShellCommands` / `ShellBridgeHandling` / `ShellWebDelegates` / `ShellSnapshot` |
| `Bridge/` | 与 HTML 的双向通道定义 | `BridgeMessage`（21 个通道）、`BridgeScripts` |
| `Home/` | SwiftUI 首页 | `NativeHomeModel`、`NativeHomeView`、`NativeIconCatalog` 及组件 |
| `Materials/` | HTML 卡片背后的原生材质层 | `CardMaterialLayer`、`NativeMaterialView` |
| `Theme/` | 偏好存储、调色板、自定义字体 | `ThemePreferences`、`ThemePalette`、`ThemeFontController` |
| `Media/` | 照片/文件选择、头像存储 | `ImagePickerCoordinator`、`AvatarStore` |
| `Export/` | ZIP 重命名与系统分享 | `ZipExportCoordinator` |
| `Support/` | 颜色、弹窗、路径、阴影清理 | `ColorHex`、`AlertPresenter`、`AppPaths` |
| `SettingsHero/` | 设置页品牌卡（Objective-C，保持原样） | `LUISettingsHeroAdapter.{h,m}`、`LUISettingsHeroCell.m` |

`MainShellViewController` 只负责组装与状态，行为分散在各 extension 文件里，单文件均不超过 400 行。

## 保持不变的契约

- 21 个 `window.webkit.messageHandlers.*` 通道名（现在由 `BridgeMessage` 枚举统一注册与分发）
- 17 个 `window.__*` 原生调用钩子
- 所有 `UserDefaults` 键（`youyou.*`、`luiyo.nativeIconColors`），现在集中在 `PreferenceKey`
- 所有 `accessibilityIdentifier` 与 `accessibilityLabel`（UI 测试依赖）
- 通知名 `LUIYoDeviceCodeUpdated` / `LUIYoTierUpdated`
- Objective-C 桥接函数签名，以及 `youyou.auth.tier`、`youyou.device.code`、`youyou.heroCardColor.*` 的读写

## 本次重写清理的死代码

以下文件/类型在旧版中从未被编译进 target 或从未被调用，已删除（原始备份见 `backup/`）：

- `NativeSettings.swift`、`NativeThemeInline.swift`、`NativeThemeSection.swift`（未加入工程）
- `NativeThemeMinimal.swift`（编译但无人调用）
- `BlockedPopupController`、`ShieldIconView`、`presentBlockedPopup`（实际生效的是 HTML 弹窗 `BlockedPopupWindow`）
- `WebViewController.showBlockedPopup`、`setBottomSearchLayout`、`setCardTintColor`（定义后从未调用）

## 校验状态（重要）

重写在 Linux 沙箱完成，**没有 Xcode / iOS SDK，未经编译与真机验证**。已完成的静态校验：

- 44 个 Swift 文件全部通过 `swiftc -parse` 语法解析
- 契约脚本对比：桥接通道、JS 钩子、偏好键、无障碍标识、通知名、ObjC 符号与旧版一致
- `scripts/check-native-home.js`、`scripts/check-activation-export.js` 在重写版与原始版上行为一致（两者在同一条 jsdom 环境相关断言上失败，并非重写引入）
- iOS 18 / 26 专属 API（`setContentScrollView`、`tabs` / `UITab`、`tabBarMinimizeBehavior`、Liquid Glass）补足了 `#available` 保护

首次构建请在 Xcode 中执行；若报错把日志发我，按日志修。

## 已知未处理项

- 版本号不一致：`Info.plist` 是 1.0.7 / Build 84，`project.pbxproj` 的 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION` 仍是 1.0.6 与 39、40（保持旧值未动）。构建产物以 `Info.plist` 为准，IPA 名为 `LUIYo-1.0.7-Build(84).ipa`。
- `.github/workflows/build-ipa.yml` 的 artifact 名仍写作 `LUIYo-v1.0.6-build41-IPA`；`scripts/check-native.sh` 仍断言 `1.0.4 / build 19`。两者均按现状保留。
- 诊断只读键 `youyou.cardColor.*` 与写入键 `youyou.heroCardColor.*` 不一致（旧版既有行为），未改动。
