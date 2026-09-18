# Kairos 架构

本文记录稳定的系统边界和主要数据流。类型成员、具体 UI 布局和外部接口字段以源码为准。

## 系统概览

Kairos 是 macOS 26+ 的 Apple Silicon 菜单栏应用，由两个进程组成：

- `Kairos`：SwiftUI/AppKit 主应用，负责 UI、网络监控、场景编排、外部网络请求、用户级文件与设置。
- `KairosHelper`：通过 `SMAppService` 注册的 LaunchDaemon，以 Mach service 提供范围固定的特权 DNS 和维护操作。

主应用没有 App Sandbox。需要 root 权限的操作仍必须收敛在 Helper 的固定 XPC 接口内，不能把 Helper 变成通用命令执行器。

## 应用入口与窗口

`App/KairosApp.swift` 在应用级创建唯一的 `NetworkMonitor`、`MihomoViewModel` 和 `WindowCoordinator`，并注入 SwiftUI 环境。应用同时提供菜单栏入口和 ID 为 `main` 的主窗口。

`App/AppDelegate.swift` 初始化 Sparkle、通知和 Helper 健康检查，将持久化场景交给 `NetworkMonitor` 启动监听。登录项启动时保持窗口隐藏；手动启动时请求显示。关闭最后一个窗口不会退出菜单栏进程，Cmd+Q 由 `QuitConfirmationCoordinator` 实现二次确认。

`App/ContentView.swift` 是六个页面的导航容器：网络控制、网络工具、Mihomo、日志、设置和关于。`WindowCoordinator` 只保存页面选择和显示/隐藏请求；`MenuBarView` 执行实际的 SwiftUI/AppKit 窗口操作。

## 代码职责

- `Models/`：`Codable` 业务数据与网络响应模型，不执行 IO。
- `Views/`：页面、组件和用户交互。
- `ViewModels/`：页面状态、取消、进度和异步流程编排。
- `Services/`：系统框架、文件、网络、进程和持久化边界。
- `UseCases/IPQuality/`：IP 质量检测的领域步骤与聚合逻辑。
- `Managers/`：登录项、通知、Toast 等应用级系统服务。
- `Coordinators/`：窗口、退出确认和通知等跨视图流程。
- `Utils/`：日志、校验、超时、文件面板和设计 token。

依赖方向通常为 `View → ViewModel/Coordinator → Service/UseCase → 系统或外部边界`。新增功能应沿用这一方向，不让 View 直接承载复杂 IO，也不让底层 Service 依赖具体页面。

## 网络场景

`NetworkMonitor` 使用 `NWPathMonitor` 监听路径变化，是网络自动化的应用级编排器。路径变化后，它在后台通过 `RouterInfoService` 读取默认网关 IP、ARP 表中的 MAC 和活跃接口，再回到主线程更新状态并运行两套匹配引擎。

应用控制链路：

1. `SceneMatchingEngine` 按启用状态、网关 IP 和 MAC 精确匹配场景，并计算与上次场景的差异。
2. `AppControlService` 通过 `NSWorkspace` 启动或退出应用；退出其他应用需要辅助功能权限。
3. 离开场景后，只恢复不再受当前场景控制、且此前由 Kairos 关闭的应用。

DNS 链路：

1. `DNSSceneMatchingEngine` 使用相同的网关 IP + MAC 规则选出第一个启用场景。
2. `DNSManager` 经 XPC 请求 Helper 设置或清除当前网络接口的 DNS。
3. 没有匹配场景时保持现有 DNS，不把 DNS 场景当作代理 profile。

## 特权 Helper 与 XPC

`DNSManager` 负责 Helper 注册、系统批准状态、版本和 bundle 指纹健康检查、必要时重新注册，以及带超时的 XPC 调用。`KairosHelper/main.swift` 建立 privileged Mach listener，并使用双方当前签名的 Team ID 和 bundle identifier 生成 reciprocal code-signing requirement；无法建立可信要求时拒绝连接或监听。

XPC 契约在以下文件各保留一份：

- `App/Services/DNSHelperProtocol.swift`
- `KairosHelper/DNSHelperProtocol.swift`

两份 selector、参数和返回类型必须同步。Helper 通过 `SystemConfiguration` 设置 DNS 和刷新接口；对于无公开 API 的操作，只执行代码中固定绝对路径的 DNS cache、ARP 和 `purge` 命令。不得接受任意命令、参数拼接或不受限文件路径。

Helper 由 Kairos 自行注册和升级，不属于 Sparkle 的运行时控制范围。修改 target 嵌入方式、LaunchDaemon plist、entitlements、bundle identifier 或签名逻辑时，必须把 app 与 Helper 作为一个发布契约验证。

## 网络工具与外部服务

- IP 查询：`IPQueryViewModel → IPQueryService → ipapi.is`。
- IP 质量：`IPQualityViewModel` 调度 `UseCases/IPQuality/`，并由 `IPDataSourceService` 并行访问可用的数据提供方。
- DNS 基准：`DNSBenchmarkService` actor 直接向用户选择的 resolver 发送 UDP/53 A 记录查询。
- 深度清理：`NetworkMaintenanceService` 会短暂断开并恢复 Wi-Fi，经 Helper 清 DNS/ARP、刷新接口和执行 `purge`，同时直接清除 Chrome/Firefox cache。该功能会中断网络并删除用户浏览器缓存，只能由明确的用户操作触发。

`App/Info.plist` 当前允许任意网络加载。不要把现状描述为所有请求均受默认 ATS 限制；新增外部来源仍应使用 HTTPS，并在系统边界验证 URL、状态码和响应数据。

## Mihomo 内核维护

`MihomoViewModel` 聚合配置、文件、下载和关联应用进程服务。该模块不运行 Mihomo，也不管理代理规则。

- `MihomoConfigService` 保存内核路径、关联应用、GitHub Releases URL 和 asset 文件名前缀。
- `MihomoProcessService` 检查关联应用、请求退出，并等待对应进程终止。
- `MihomoDownloadService` 查询用户配置仓库的最新 prerelease，下载匹配的 `.gz`，在 asset 提供 SHA-256 digest 时校验后解压。
- `MihomoFileService` 对现有内核创建 `.bak`，再暂存并原子替换或恢复。

文件服务只接受用户 home 下的普通文件，拒绝 symlink、`.app` bundle 内路径和不可写位置，并验证替换文件是 arm64 Mach-O。GitHub asset 没有 digest 时目前不会进行内容哈希验证，这是现有完整性边界。

## 持久化与导入导出

- 应用场景：`~/Library/Application Support/Kairos/scenes.json`。
- DNS 场景：`~/Library/Application Support/Kairos/dnsScenes.json`。
- 日志：`~/Library/Application Support/Kairos/Logs/`，按日写入并执行大小和保留期清理。
- Mihomo 配置和 API Key：`UserDefaults`；API Key 当前没有使用 Keychain。
- `.kairos` 设置文件：JSON envelope，当前格式版本为 2，包含两类场景、Mihomo 配置和全部 API Key。

场景存储使用原子写入，并可从旧版 `UserDefaults` 迁移。设置导入先解析，再由设置页面经用户确认后落盘。导出文件包含明文凭据，应视为敏感文件。

## 更新与分发

`ApplicationUpdateController` 包装 Sparkle 2，根据构建注入的 stable、beta 或 alpha 通道决定允许的更新。appcast URL、EdDSA 公钥、签名 feed 和解压前验证开关位于 `App/Info.plist`。发布流水线、版本清单与 Homebrew/Appcast 更新见 `docs/development.md`。

## 当前已知风险与限制

- `SceneStorage` 和 `DNSSceneStorage` 在读取或解码失败时返回空数组。页面后续保存可能用空数组覆盖仍存在但损坏或暂时不可读的原文件；日志文字不等于数据已被隔离保护。
- `.kairos` 导入对高于当前值的 `version` 只告警，仍返回可应用的数据；目前没有拒绝未知未来 schema。
- API Key 明文保存在 `UserDefaults`，也会进入设置导出文件。
- XPC 协议由两个 target 重复维护，缺少自动一致性检查。
- `DNSHelper.getDNS(interface:)` 的当前实现读取全局 DNS dynamic store，并未按传入接口过滤。
- Mihomo 下载只在 GitHub asset 提供 digest 时验证内容哈希。

修复这些问题时应修改根因和契约，并为失败路径补充可执行验证；在修复落地前，文档和 UI 不应声称已经提供相应保障。
