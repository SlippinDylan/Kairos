# Kairos 开发与发布

## 环境

- macOS 26 Tahoe 或更高版本
- Xcode 26 或更高版本；CI 当前固定使用 Xcode 26.6
- Apple Silicon；app 与 Helper 均只构建 `arm64`
- Node.js，用于仓库内零依赖的发布与通知自动化测试

工程包含 `Kairos` app 和 `KairosHelper` command-line tool 两个 target。CI 和 Xcode 使用仓库内共享的 `Kairos` scheme。Swift Package Manager 锁定 Sparkle 2；`Package.resolved` 必须提交。

## 本地开发

打开 `Kairos.xcodeproj`，选择 `Kairos` scheme 和 My Mac。app 与 Helper 的 Debug 和 Release 都保留原团队配置；Debug 使用 Manual 与本地临时签名（Sign to Run Locally），无需登录 Apple ID 或安装开发证书；Release 的签名设置及 CI 证书覆盖方式保持独立。

- `⌘⇧K`：清理构建产物；签名及 scheme 配置仍会保留。
- `⌘R`：使用 Debug 构建并运行应用，适合查看菜单栏气泡与调试 UI。
- `⌘⇧R`：Xcode 默认的 Profile 操作，会打开 Instruments；共享 scheme 同样使用 Debug，因此不需要开发证书。其性能数据不代表优化后的 Release 性能。
- Archive：继续使用 Release，需要有效的开发证书与团队配置。

临时签名没有 Apple Team ID，无法通过 app 与 Helper 的 reciprocal XPC trust requirement，因此本地 Debug 不能完整验证网关 MAC 获取、DNS 修改及深度清理等特权功能。不要为本地预览放宽 XPC 校验。需要验证这些功能时，应使用同一有效团队证书签名的 app 与 Helper。

只验证编译和嵌入结构时，可执行 CI 同款无签名构建：

```bash
xcodebuild build \
  -project Kairos.xcodeproj \
  -scheme Kairos \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData-Release \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

产物位于 `build/DerivedData-Release/Build/Products/Release/Kairos.app`。该构建不能验证真实 Helper 注册、macOS 批准或 XPC 签名互信。

## 自动化验证

CI 的轻量检查可在任意支持 Bash 和 Node.js 的环境执行：

```bash
bash -n Scripts/create-dmg.sh
bash -n Scripts/run-swift-regressions.sh
Scripts/create-dmg.sh --help >/dev/null
node .github/scripts/release-manifest.mjs validate
node .github/scripts/sync-localization.mjs --check
node .github/scripts/sync-version.mjs --check
node --test .github/scripts/*.test.mjs
```

当前仓库没有 XCTest target。Swift 行为变更由应用编译、独立 Swift 回归检查与必要的手动功能验证共同覆盖；不要把 Node 自动化测试描述为应用逻辑测试。

macOS CI 使用统一入口编译并运行离线逻辑回归，不启动 Kairos、不请求外部网络或执行提权操作。命令需要 macOS 26+、Apple Silicon 和 Xcode 26+；可指定一个或多个检查名称：

```bash
bash Scripts/run-swift-regressions.sh
bash Scripts/run-swift-regressions.sh --help
```

网关 MAC 读取器另有独立 Swift 回归检查，覆盖默认接口筛选、未解析或脱敏的 MAC、空表及损坏记录，无需 root：

```bash
bash Scripts/run-swift-regressions.sh GatewayInfoReader
```

编译后执行 `build/Tests/GatewayInfoReaderTests --read-current` 可只读查询当前网关。普通进程可能读到空 ARP 表，真实 MAC 获取需在 root 环境验证；此独立检查不能替代签名 app 与 LaunchDaemon 的 XPC、批准和升级验证。

DNS 服务定位回归使用临时网络配置文件，覆盖当前网络位置、停用服务、显示名称冲突和同接口多服务，不提交或应用系统配置。IP 请求回归使用离线响应，覆盖 IPWHOIS 免费与 Pro 地址及凭据编码：

```bash
bash Scripts/run-swift-regressions.sh DNSServiceResolver IPQuery
```

Mihomo gzip 解压器的独立 Swift 回归检查覆盖超过 50 MiB 的输出、截断数据、CRC32/长度损坏及 gzip 可选头部：

```bash
bash Scripts/run-swift-regressions.sh GzipDecompressor
```

测试只生成临时 gzip 样本，不操作用户实际内核或运行关联应用。

菜单栏界面协调器的独立 Swift 回归检查覆盖等待菜单栏锚点、显示与收起、保留 hosting controller 和结果尺寸、导航有效性及屏幕可用尺寸限制：

```bash
bash Scripts/run-swift-regressions.sh WindowCoordinator
```

测试使用拦截原生显示与关闭操作的 Popover，不显示真实界面。箭头定位、实际菜单点击、外部点击及文件选择交互仍需手动验收。

原生气泡布局回归检查验证首次打开、结果展开、紧凑工具、返回及重新打开后的内容尺寸和安全区；诊断窗口完全透明，不启动 Kairos 或网络服务：

```bash
bash Scripts/run-swift-regressions.sh PopoverContentLayout
```

设置草稿的独立 Swift 检查覆盖变更检测、保存前隔离、应用路径校验、解除关联和导入后重载；使用真实 API Key 管理器与独立的临时偏好域，覆盖保存时空白规范化、损坏配置阻止保存、重试保留草稿及内存、持久化、保存基线一致性，不接触实际凭据：

```bash
bash Scripts/run-swift-regressions.sh SettingsViewModel
```

工具详情尺寸的独立 Swift 回归检查使用屏幕外的 hosting view，覆盖紧凑输入、错误撑高、固定边距、结果宽度、固定 IP 输入框、屏幕高度限制，以及贴页面右侧且不占内容宽度的原生滚动条。同时以测试进程参数模拟系统“始终显示滚动条”，不修改用户设置；不创建 sheet，不发出网络请求：

```bash
bash Scripts/run-swift-regressions.sh NetworkToolSheetSizing
```

DNS 进度与色带动画的独立检查验证每轮进度单调增长、未完成时不报告 100%、网格铺满弹窗，以及全宽色场从左向右流动且循环边界连续：

```bash
bash Scripts/run-swift-regressions.sh DNSProgressAnimation
```

日志轮转检查覆盖多次轮转、大小上限及超大条目后的继续写入；内核路径检查在独立缓存目录中验证波浪线路径的状态读取与备份，不操作真实内核：

```bash
bash Scripts/run-swift-regressions.sh LogFileWriter MihomoKernelPath
```

Mihomo 退出等待检查覆盖先取消后注册、注册与取消并发、观察者清理及只结束一次；IP 数据检查使用离线响应样本覆盖分类优先级、展示语言隔离及 VPN 字段解析，不访问服务商：

```bash
bash Scripts/run-swift-regressions.sh MihomoTerminationWaitState IPDataSourceAggregation
```

IP 查询检查通过 `URLProtocol` 离线响应验证匿名/带 Key 请求、两种响应格式、缺失字段、坐标边界、损坏响应及 HTTP 错误，不访问实际 API 或用户凭据：

```bash
bash Scripts/run-swift-regressions.sh IPQuery
```

场景文件与导入检查覆盖迁移写入失败、损坏文件、旧版与未来版配置、重复 ID、场景字段校验与 MAC 规范化、本机关联应用身份解析，以及导入失败后的原文件恢复；DNS 状态检查覆盖匹配、应用成功、失败重试、跨网络或配置版本的计划失效、过期回调与系统解析器数据边界。异步 DNS 和流媒体检查通过注入任务与离线响应验证超时、取消、访问限制和真实错误传播；Mihomo 应用身份检查验证 Bundle ID 优先、多实例退出与拒绝退出，均不操作真实网络或进程：

```bash
bash Scripts/run-swift-regressions.sh ScenePersistence DNSSceneApplication AsyncDNSOperations StreamingDetection MihomoProcessIdentity
```

应用控制检查使用临时应用样本、进程替身和状态模型，覆盖精确身份匹配、只恢复实际关闭的应用、场景切换、逐应用恢复重试及超时后的退出通知。应用选择检查覆盖非标准目录、同名应用及旧格式兼容；下载检查注入字节回调和无标题 Release 响应，覆盖已知或未知长度、重试重置及结束后的迟到回调，不启动应用或下载文件：

```bash
bash Scripts/run-swift-regressions.sh AppControl SceneApplicationSelection MihomoDownloadProgress
```

上述离线逻辑检查均纳入 macOS CI。`PopoverContentLayout`、`NetworkToolSheetSizing` 和 `SheetOutsideDismissal` 需要 AppKit 窗口环境，按需通过同一脚本单独执行，不作为 CI 默认项；这些检查不能替代真实菜单栏、显示器切换和输入焦点的视觉验收。

本地化资源由 `App/Localizable.xcstrings` 和 `App/InfoPlist.xcstrings` 提供。修改 `.github/scripts/sync-localization.mjs` 中的受支持字符串后运行同名脚本更新主 Catalog；目录中的固定键标记为手动管理；CI 使用 `--check` 比较键和译文，忽略 Xcode 管理的提取元数据、排序和格式，新增未翻译的键仍会使检查失败。无法生成有效 Swift 标识符或会产生同名符号的运行时键，显式关闭该条目的符号生成，不影响字符串本地化。Node 测试覆盖 English、简体中文和繁體中文译文完整性及上述比较规则。

按改动选择最小验证：

- 纯文档：链接/路径检查、Markdown 基础检查、`git diff --check`。
- Swift、plist、entitlements 或 Xcode 工程：构建 `Kairos` scheme；Helper 改动还需检查嵌入产物和 LaunchDaemon plist。
- `.github/scripts/`、release manifest 或 workflow：运行全部 Node 测试、DMG shell 语法和 manifest 校验。
- 场景、存储或设置导入：覆盖首次启动、已有数据、损坏数据、旧版本和未知未来版本。
- UI：完成编译；仅在用户提供截图或明确要求时启动应用做视觉验收。
- DNS/Helper：真实功能验证会修改系统 DNS 或执行维护动作，只在用户明确要求且理解影响时进行。

## CI

`.github/workflows/pr-check.yml` 对 `main` 的 push、pull request 和手动触发运行：

1. Ubuntu job 始终校验 DMG 脚本、release manifest 和 Node 测试。
2. 只有非文档改动、手动运行或开启发布请求时，才在 `macos-26` 上执行无签名 Release 构建。
3. macOS job 先运行离线 Swift 回归，再校验 app、arm64 主程序、Helper、LaunchDaemon plist、最低系统版本和 Sparkle 配置。
4. 固定名称 `Build Check` 汇总轻量检查与可选 macOS job，供分支保护使用。

`README.md`、`LICENSE`、根 `AGENTS.md` 和 `docs/*` 的纯文档改动通常会跳过 macOS 编译，但不会跳过轻量自动化检查；当 release manifest 的 `release` 为 `true` 时，文档改动也会强制运行 macOS job。

## 发布流程

发布是两阶段流水线，不应从本地直接仿造或绕过：

1. 在 `Config/Release/manifest.json` 设置新版本，并运行 `node .github/scripts/sync-version.mjs` 更新受版本控制的 Xcode 配置；仅在有意发版时将 `release` 改为 `true`，且 `CHANGELOG.md` 必须存在完全匹配且非空的版本章节。
2. 该提交进入 `main`，并通过同一 commit 的 CI。
3. `.github/workflows/build-and-release.yml` 由成功的 main push CI 触发，拒绝版本倒退或重复发布，使用 Apple Development 证书构建 app 与 Helper。
4. 流水线从内到外重新签名 Sparkle 组件，验证签名、entitlements、Helper 内嵌 Info.plist、XPC trust requirement 和 artifact contract。
5. `Scripts/create-dmg.sh` 生成拖放式 DMG；验证挂载内容后先创建并检查 draft GitHub Release，再正式发布。
6. 发布完成后 dispatch `.github/workflows/publish-distribution-metadata.yml`，从不可变 Release 产物生成签名 appcast 和对应 stable/beta/alpha Homebrew Cask，并提交到共享 tap。

版本格式由 `.github/scripts/release-manifest.mjs` 定义，支持 stable、`-alpha.N` 和 `-beta.N`。`Config/Release/manifest.json` 是版本号和发布开关的唯一人工编辑入口；`Config/Generated/Version.xcconfig` 由同步脚本生成并提交，供 app 与 Helper 的普通 Xcode 构建读取，CI 使用 `--check` 阻止两者漂移。应用运行时只从 Bundle 读取版本信息。构建号仍由 Xcode 默认值或发布流水线的 GitHub run number 提供。

当前公开产物使用 Apple Development 证书签名但未公证。不要在文档或发布说明中声称已经 notarize。签名证书、密码、Sparkle 私钥和 tap token 只存在于 CI secret 或外部安全位置，禁止写入仓库、日志或 Memory。

## DMG 脚本

查看参数：

```bash
Scripts/create-dmg.sh --help
```

脚本输入必须是已构建的 `.app`，输出是可重新生成的 DMG。修改脚本后至少运行 `bash -n`、帮助命令和相关 CI 自动化；实际打包会调用 macOS 磁盘映像工具，应只在需要验证打包行为时执行。

## 开发产物与安全清理

清理请求语义、仓库内外范围、Kairos 归属判定、Agent 对话保护、开发安装边界和空间报告要求统一见 [Kairos 开发产物清理规则](development-cleanup.md)。

本文前述构建命令生成 `build/DerivedData-Release/`；`Scripts/create-dmg.sh` 生成调用者指定的 DMG，并在正常或异常退出时清理 `kairos-dmg.*` staging。实际输出路径仍以执行的命令和脚本参数为准。
