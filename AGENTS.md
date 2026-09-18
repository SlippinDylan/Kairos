# Kairos Agent Guide

## 项目概述

Kairos 是面向 macOS 26+、Apple Silicon 的原生菜单栏网络工具。主应用使用 SwiftUI 与 AppKit，负责网络场景自动化、DNS 与 IP 工具、Mihomo 内核文件维护；独立的 `SMAppService` LaunchDaemon 通过 XPC 执行需要 root 权限的 DNS 和系统维护操作。Sparkle 2 提供应用更新。

本文件是仓库地图和工作契约，不是实现手册。详细架构见 `docs/architecture.md`，开发、验证和发布流程见 `docs/development.md`。

## 开始工作

1. 先检查工作树，保留用户已有改动，不清理或回退无关内容。
2. 阅读与任务相关的源码和文档，确认现有职责、数据流及安全边界后再修改。
3. 采用现有设计和命名；只在当前需求需要时引入新抽象或兼容层。
4. 修改 Xcode 工程、签名、Helper、持久化格式或发布自动化前，先阅读对应文档及 CI 配置。

## 仓库地图

- `App/KairosApp.swift`、`App/AppDelegate.swift`：应用入口、生命周期、菜单栏与主窗口。
- `App/Views/`：SwiftUI 页面与组件；`ContentView.swift` 是六个主页面的导航容器。
- `App/ViewModels/`：页面状态与异步操作编排。
- `App/Services/`：网络监控、DNS、IP 数据源、Mihomo、持久化和设置导入导出。
- `App/Services/NetworkMonitor/`：网关读取、场景匹配和应用控制的拆分服务。
- `App/UseCases/IPQuality/`：IP 质量检测的领域用例。
- `App/Models/`：可持久化模型和网络结果模型。
- `App/Managers/`、`App/Coordinators/`：应用级系统服务与 UI 流程协调。
- `App/Utils/`：日志、校验、超时和设计系统等共享能力。
- `KairosHelper/`：特权 LaunchDaemon、XPC 服务和固定的 root 操作。
- `Kairos.xcodeproj/`：`Kairos` app 与 `KairosHelper` 两个 target；CI 和 Xcode 使用自动生成的 `Kairos` scheme，仓库未提交 `.xcscheme`。
- `.github/workflows/`、`.github/scripts/`：CI、发布、分发元数据和通知自动化。
- `Config/Release/manifest.json`：是否发版和当前发布版本的唯一请求入口。
- `Scripts/create-dmg.sh`：可复现的拖放式 DMG 打包脚本。
- `README.md`、`docs/README.*.md`：面向用户的产品说明及翻译。

## 架构硬边界

- `NetworkMonitor` 是应用级唯一网络编排器；不要在页面内创建第二个监控实例。
- 视图负责呈现和用户交互，跨页面状态放 ViewModel、Manager 或 Coordinator，IO 与系统调用放 Service。
- 网络场景只有在已启用规则的网关 IP 和 MAC 都匹配时生效；DNS 场景不是代理配置，Kairos 不管理代理规则。
- root 操作只能经 `DNSManager` 与 `KairosHelper` 的受限 XPC 接口执行；不要在主应用新增提权 shell、泛化命令执行或任意路径删除能力。
- `App/Services/DNSHelperProtocol.swift` 与 `KairosHelper/DNSHelperProtocol.swift` 是跨 target 契约。修改 selector、参数或返回值时必须同步两端，并复核 reciprocal code-signing requirement。
- Mihomo 功能只维护用户选择的、位于 home 目录下且不在 `.app` bundle 内的可写 arm64 Mach-O 文件；不要扩展到受保护路径或代理配置管理。
- 持久化模型、`.kairos` 导出结构和 XPC 协议属于兼容性边界。改变字段语义、格式版本或迁移策略前先说明影响并等待确认。
- API Key 当前保存在 `UserDefaults`，设置导出也包含明文 Key。不得在日志、测试夹具、文档或提交内容中写入真实凭据。
- 更新通道、Sparkle 公钥、签名设置、bundle identifier、Helper plist 和 release manifest 共同构成发布契约，不要局部修改其中一项后假设其余仍成立。

## 常用命令

```bash
# CI 的轻量自动化检查
bash -n Scripts/create-dmg.sh
Scripts/create-dmg.sh --help >/dev/null
node .github/scripts/release-manifest.mjs validate
node .github/scripts/sync-version.mjs --check
node --test .github/scripts/*.test.mjs

# 与 CI 一致的无签名 Release 编译；产物留在仓库 build/ 下
xcodebuild build \
  -project Kairos.xcodeproj \
  -scheme Kairos \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData-Release \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

本地运行需要在 Xcode 中选择开发团队并构建 `Kairos` scheme。当前工程没有 XCTest target；不要声称执行过应用单元测试。完整命令和发布流程见 `docs/development.md`。

## 完成标准

- 需求行为及相关异常路径已实现，改动符合既有职责边界。
- 执行与改动风险相称的最小验证；Swift 或工程配置变更至少编译相关 target，自动化变更运行对应 Node 测试。
- 涉及 Helper 时同时验证 app、Helper、嵌入路径、LaunchDaemon plist 和签名/XPC 契约。
- 涉及持久化或导入导出时验证空数据、旧数据、损坏数据和未来版本行为，不以 silent fallback 掩盖失败。
- 涉及 UI 时不主动启动应用或截图；除非用户明确要求，视觉结果交由用户验收。
- 结束前运行 `git diff --check` 并检查 diff，不包含密钥、调试输出、生成物或无关改动。
- 行为、架构或发布流程变化导致文档失效时，同步更新唯一权威文档。

## 文档规则

- 对外及项目文档使用中文；代码注释使用英文，并只解释约束、原因或非显而易见的决策。
- 源码和自动化是实现事实来源；文档记录稳定边界、公共契约、风险和工作流程，不复制易漂移的代码细节。
- 根 `AGENTS.md` 目标保持在约 100 行，软上限 150 行；细节下沉到 `docs/`，局部规则需要时放在更近的 `AGENTS.md`。
- 同一事实只维护一个权威来源。重复出现的 Agent 错误优先通过类型、测试、lint 或 CI 固化，再补充必要说明。

## 开发产物与清理

- 仓库内 `build/`、`DerivedData/`、`.build/`、测试结果和明确生成的临时文件可在明确清理请求下删除；删除前先确认归属并统计空间。
- 不删除源码、Git 数据、工程配置、签名材料、用户设置、场景 JSON、日志或用途不明的文件。
- 扫描或清理 `/tmp`、`/private/tmp`、`/private/var/folders` 及仓库外 DerivedData 必须得到用户明确授权，并仅处理能归属于 Kairos 且可重新生成的内容。
- 未经明确要求，不提交、推送、创建 Release、修改 tap/appcast，或将 `Config/Release/manifest.json` 的 `release` 改为 `true`。

## 文档导航

- `docs/architecture.md`：运行时组件、数据流、安全边界、持久化和当前风险。
- `docs/development.md`：环境、构建验证、CI、发布与安全清理。
- `README.md`：用户可见能力、权限、安装和平台要求。
- `CHANGELOG.md`：已发布行为变化与发布说明来源。
