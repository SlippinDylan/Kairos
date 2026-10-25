# Changelog

All notable changes to Kairos releases are recorded here.

## [Unreleased]

## [0.9.0] - 2026-10-25

### 调整

- 主界面改为菜单栏气泡，应用控制与 DNS 控制分别展示，工具和场景编辑在同一气泡内进入详情页。
- 网络工具按系统维护和网络检测分组，Mihomo 配置与日志入口移入设置。
- 更新应用图标、界面控件，以及各语言 README 的截图与功能说明。

### 修复

- Helper 仅在当前网络位置按 BSD 名称定位已启用的 DNS 服务，拒绝歧义目标，避免修改其他网络位置。
- IPWHOIS 带 Key 时改用官方 Pro 接口，并正确编码凭据中的特殊字符。
- 切换网络或规则后停止旧 DNS 计划的后续写入；应用退出等待超时后继续接收实际退出回执。
- 保留所选应用的完整路径，导入时重新读取本机关联应用身份，Mihomo 维护等待全部关联实例退出。
- 内核下载兼容没有标题的 GitHub Release。
- 损坏的 Mihomo 配置明确报错并保留原数据；导入前校验场景字段，避免无效规则覆盖现有配置。
- 应用控制按真实 Bundle ID 匹配，只恢复实际由 Kairos 关闭的应用；DNS 配置使用 BSD 接口名称。
- 内核下载显示真实字节进度，总大小未知时使用不定进度；同步五语 IPinfo 接口说明。
- 本地 Debug 保留团队配置并使用临时签名，Release 恢复原签名团队。
- 修复本地化目录与 Xcode 自动更新冲突的问题，并补齐新增按钮译文。
- 修复日志轮转后向失效文件句柄写入的问题，以及切换模块后深度清理可重复执行的问题。
- 修复 IP 质量与 DNS 测试取消、重试时旧任务干扰新任务的问题。
- 支持波浪线形式的内核路径，修复内核维护结果丢失和跨操作串用的问题。
- Escape 先交由输入法和输入响应链处理，避免取消候选时收起整个界面。
- 修复 DNS 失败样本被计作零延迟、IP 质量缺失评分却显示极低风险的问题，并校验公网 IP 接口返回的地址。
- 内核操作结果绑定目标文件；API Key 保存时同步规范内存和本地值；工具详情展开与收起时保留输入控件。
- 修复多语言与缺失来源类型导致的 IP 分类错误，兼容 ipapi.is 的 VPN 真值响应，并修复等待关联应用退出时取消与注册的竞态。
- 显示器配置变化时重新计算菜单栏气泡尺寸，将离线 Swift 回归接入 macOS CI。
- IP 查询兼容 ipapi.is 的匿名精简响应并使用已配置的 Key；缺失字段保留未知，没有坐标时不显示地图。
- 场景读取和保存失败明确报错，迁移成功后才删除旧数据；导入校验格式与重复 ID，并在文件提交失败时恢复原配置。
- 补齐 IP 查询无位置响应、质量检测基础资料与风险来源，纠正商业类型和评分范围，统一处理服务商限流。
- DNS 匹配与已应用状态分离，配置变更可重新应用，系统 DNS 变化及时刷新概览。
- 修复域名解析超时与取消、内核下载同名重命名、关联应用同名误匹配，以及回归检查对中文翻译资源的错误依赖。

## [0.8.1] - 2026-10-22

### 修复

- 修复普通进程无法读取 ARP 表时网关 MAC 显示为空的问题，改由特权 Helper 读取当前网关及对应接口的 MAC。
- Helper 安装、修复或状态变化后自动刷新网络信息，并避免过期的异步结果覆盖当前网络状态。
- 修复 Mihomo 内核解压超过 50 MiB 时被截断、导致代码签名失败的问题；完整解压并校验 gzip 的 CRC32 与长度。
- 修复菜单栏显示请求等待、窗口关闭后重开与前置逻辑，左键复用主窗口，右键选择模块后显示对应页面，保持 Dock 图标隐藏。

## [0.8.0] - 2026-09-24

### 修复

- Mihomo 内核替换支持用户主目录内、目标目录可写但原文件由 root 持有的情况。
- 替换和恢复前对新内核处理隔离属性并完成 ad hoc 签名；提交后验证，失败时恢复原文件。

## [0.7.0] - 2026-09-19

### 调整

- 将网络控制页和 Mihomo 状态区改为带图标的紧凑概要卡片。
- 重组设置页分类，并将关于页面移入设置。
- 统一主页面标题栏、设置分类栏和日志工具栏的视觉层级。
- 精简 DNS 测试与 IP 质量检测的进度信息，并让卡片背景以流光渐变显示进度。
- 将 IP 查询、DNS 测试和 IP 质量检测结果统一改为窗口级弹窗展示。

## [0.6.0] - 2026-09-19

### 调整

- 左键点击菜单栏图标直接显示并前置主窗口，右键点击才显示功能菜单。
- `Command-Q` 仅关闭主窗口并保留菜单栏进程；只有菜单中的退出操作会终止 Kairos。
- 主窗口保持单一实例，所有入口都会复用并前置现有窗口。

## [0.5.0] - 2026-09-19

### 新增

- 支持跟随系统、English、简体中文和繁體中文界面语言。
- 可在设置的通用区域选择应用语言，并立即重启应用语言配置。

## [0.4.0] - 2026-09-18

### 调整

- 精简菜单栏，只保留带图标的网络控制、网络工具、Mihomo 和退出入口。
- 移除页面导航快捷键，仅保留退出应用的 `Command-Q`。
- 统一由发布清单生成 app 与 Helper 的 Xcode 版本和更新频道配置。

## [0.3.0-beta.1] - 2026-09-17

### Added

- Added Feishu notifications when CI starts and when a release enters the packaging stage.

### Changed

- Improved privileged Helper registration, update recovery, and approval guidance.
- Made Mihomo kernel replacement atomic and verified downloaded assets against published SHA-256 digests.

### Security

- Derived reciprocal app and Helper trust requirements from the active signing team.
- Tightened privileged Helper input validation.

## [0.2.0-beta.1] - 2026-09-17

### Added

- Added Sparkle 2 signed automatic updates with manual checks from the menu bar and About page.
- Added signed appcast generation and channel-specific Homebrew Cask publishing through the shared personal tap.

### Distribution

- Keeps privileged DNS Helper registration and upgrades under Kairos control rather than Sparkle.
- Rejects appcast and Cask downgrades and retries concurrent shared-tap updates safely.

## [0.1.0-beta.1] - 2026-09-16

### Added

- Added automatic network-scene detection and switching based on Wi-Fi names, IP ranges, and DNS characteristics.
- Added DNS configuration management, custom DNS scenes, and DNS performance testing.
- Added multi-source IP information lookup with geographic details and map visualization.
- Added proxy-risk, data-center, VPN, Tor, spam-source, and streaming-access detection.
- Added Mihomo kernel version management, kernel replacement, and menu-bar icon configuration.
- Added application launch and termination actions triggered by network-scene changes.
- Added privileged Helper installation, version validation, and removal for DNS operations.
- Added version-gated release automation and Feishu notifications for repository activity.
- Added native Liquid Glass controls and surfaces for macOS 26.

### Distribution

- Supports macOS 26.0 or later on Apple Silicon (`arm64`).
- Registers the privileged DNS Helper as an `SMAppService` LaunchDaemon with reciprocal XPC code-signing requirements.
- Signed with an Apple Development certificate and distributed as a non-notarized DMG.
- Runs CI for every push and pull request; only an explicit release request that passes main-branch CI can publish.
