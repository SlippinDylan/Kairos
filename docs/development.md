# Kairos 开发与发布

## 环境

- macOS 26 Tahoe 或更高版本
- Xcode 26 或更高版本；CI 当前固定使用 Xcode 26.6
- Apple Silicon；app 与 Helper 均只构建 `arm64`
- Node.js，用于仓库内零依赖的发布与通知自动化测试

工程包含 `Kairos` app 和 `KairosHelper` command-line tool 两个 target。CI 和 Xcode 使用从 target 自动生成的 `Kairos` scheme，仓库没有提交 `.xcscheme`。Swift Package Manager 锁定 Sparkle 2；`Package.resolved` 必须提交。

## 本地开发

需要运行或调试应用时，打开 `Kairos.xcodeproj`，选择本机开发团队后构建 `Kairos` scheme。签名身份会影响 app 与 Helper 的 reciprocal XPC trust requirement；不要使用一端签名、一端未签名的产物判断 Helper 行为。

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
Scripts/create-dmg.sh --help >/dev/null
node .github/scripts/release-manifest.mjs validate
node .github/scripts/sync-localization.mjs --check
node .github/scripts/sync-version.mjs --check
node --test .github/scripts/*.test.mjs
```

当前仓库没有 XCTest target。Swift 行为变更以相关 target 编译和必要的手动功能验证为主；不要把 Node 自动化测试描述为应用逻辑测试。

本地化资源由 `App/Localizable.xcstrings` 和 `App/InfoPlist.xcstrings` 提供。修改 `.github/scripts/sync-localization.mjs` 中的受支持字符串后运行同名脚本更新主 Catalog；CI 使用 `--check` 验证生成结果，并由 Node 测试确保 English、简体中文和繁體中文都有完整译文。

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
3. macOS job 校验 app、arm64 主程序、Helper、LaunchDaemon plist、最低系统版本和 Sparkle 配置。
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

仓库内常见可再生产物：

- `build/`
- `DerivedData/`
- `.build/`
- `*.xcresult`、`*.dSYM`、临时 DMG 挂载或打包目录

只有在明确收到清理请求后才删除，并遵循：

1. 先解析精确路径，确认属于 Kairos 或本次构建。
2. 删除前统计每个目标和总占用。
3. 只删除可重新生成且不承载用户数据的内容。
4. 删除后重新统计并报告实际释放空间。

不要把以下内容当作开发缓存：源码、`.git/`、`Kairos.xcodeproj/`、`Config/`、`Package.resolved`、签名材料，以及 `~/Library/Application Support/Kairos/` 下的场景、日志和用户设置。

仓库外的 `/tmp`、`/private/tmp`、`/private/var/folders`、Xcode DerivedData、SwiftPM cache 可能被其他项目或系统共享。只有用户明确要求全盘审计时才检查；删除范围必须能可靠归属于 Kairos，无法确认用途的条目保留。
