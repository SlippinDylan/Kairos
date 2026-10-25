//
//  MihomoViewModel.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//

import Foundation
import Observation

/// Mihomo 管理视图模型
@MainActor
@Observable
final class MihomoViewModel {

    // MARK: - Published Properties

    // 状态
    var hostAppInstallStatus: HostAppInstallStatus = .unknown
    var kernelStatus: KernelStatus?
    var isHostAppRunning = false

    // 配置
    private(set) var configuration: Result<MihomoConfig, Error>

    var config: MihomoConfig? {
        if case .success(let config) = configuration { return config }
        return nil
    }

    var configurationError: String? {
        if case .failure(let error) = configuration { return error.localizedDescription }
        return nil
    }

    // 加载状态
    var isLoading = false
    var isRefreshing = false

    // 内核下载状态
    var isDownloading = false
    var downloadProgress: Double?
    private var activeDownloadID: UUID?
    var downloadStatusText: String = ""

    struct OperationResult {
        let message: String
        let isError: Bool
        let kernelPath: String
    }

    private(set) var operationResults: [KernelTool: OperationResult] = [:]
    private(set) var activeTool: KernelTool?

    func operationResult(for tool: KernelTool) -> OperationResult? {
        guard let config, let result = operationResults[tool], result.kernelPath == config.kernelPath else {
            return nil
        }
        return result
    }

    // MARK: - Services

    private let fileService = MihomoFileService()
    private let downloadService = MihomoDownloadService()
    private let processService = MihomoProcessService()
    private let configService: MihomoConfigService

    // MARK: - Initialization

    convenience init() {
        self.init(configService: MihomoConfigService())
    }

    init(configService: MihomoConfigService) {
        self.configService = configService
        configuration = Result { try configService.loadConfig() }
        refreshStatus()
    }

    // MARK: - 配置管理

    /// 加载配置
    func loadConfig() {
        configuration = Result { try configService.loadConfig() }
        if case .failure = configuration {
            hostAppInstallStatus = .unknown
            kernelStatus = nil
            isHostAppRunning = false
        }
    }

    // MARK: - 状态刷新

    /// 刷新所有状态
    func refreshStatus() {
        guard !isRefreshing else { return }
        loadConfig()
        guard let snapshot = config else { return }

        isRefreshing = true
        AppLogger.debug("刷新 Mihomo 状态")

        hostAppInstallStatus = fileService.checkHostAppInstallation(appBundlePath: snapshot.appBundlePath)
        kernelStatus = fileService.getKernelStatus(kernelPath: snapshot.kernelPath)
        isHostAppRunning = processService.isHostAppRunning(
            bundleIdentifier: snapshot.appBundleIdentifier,
            displayName: snapshot.appDisplayName
        )

        isRefreshing = false
        AppLogger.info("Mihomo 状态刷新完成")
    }

    // MARK: - 内核操作

    /// 备份内核
    ///
    /// 与替换/恢复内核使用同一套"软确认"策略：关联应用未配置则跳过检查，
    /// 已配置且正在运行则弹窗请求退出，而不是像旧版那样直接硬性拒绝操作。
    func backupKernel() {
        guard !isLoading, !isDownloading else { return }
        guard let snapshot = config else { reportConfigurationFailure(); return }
        operationResults[.backup] = nil
        activeTool = .backup
        AppLogger.debug("开始备份内核操作")
        isLoading = true

        // 在启动异步流程前拍下配置快照，避免用户在操作进行期间于界面上
        // 修改内核路径/关联应用，导致同一次操作里读到两份不一致的配置。

        Task {
            defer {
                isLoading = false
                activeTool = nil
            }
            do {
                let canProceed = try await ensureHostAppQuitIfRunning(
                    bundleIdentifier: snapshot.appBundleIdentifier,
                    displayName: snapshot.appDisplayName
                )
                guard canProceed else {
                    return
                }

                try fileService.backupKernel(kernelPath: snapshot.kernelPath)
                refreshStatus()

                operationResults[.backup] = OperationResult(message: L10n.string("内核备份成功"), isError: false, kernelPath: snapshot.kernelPath)
                Toast.success(L10n.string("内核备份成功"))
                AppLogger.info("内核备份操作完成")
            } catch {
                handleError(error, for: .backup, kernelPath: snapshot.kernelPath)
            }
        }
    }

    /// 替换内核（从 GitHub 自动下载最新预发布版本）
    ///
    /// ## 流程
    /// 1. 检查内核文件路径是否已配置
    /// 2. 检查关联应用是否运行（运行则请求退出）
    /// 3. 从 GitHub 获取最新预发布版本并下载、替换
    func replaceKernel() {
        guard !isLoading, !isDownloading else { return }
        guard let snapshot = config else { reportConfigurationFailure(); return }
        operationResults[.replace] = nil
        guard !snapshot.kernelPath.isEmpty else {
            Toast.error(L10n.string("请前往设置的服务组配置内核文件路径"))
            return
        }

        AppLogger.info("开始下载并替换内核")
        activeTool = .replace
        isDownloading = true
        let downloadID = UUID()
        activeDownloadID = downloadID
        downloadProgress = nil
        downloadStatusText = L10n.string("正在获取版本信息...")

        // 拍下快照：下载耗时可能长达数秒，期间界面上的内核路径/下载源等
        // 字段仍可编辑，必须固定用同一份配置贯穿整个流程，不能中途改读。

        Task {
            defer {
                activeTool = nil
                activeDownloadID = nil
            }
            do {
                let canProceed = try await ensureHostAppQuitIfRunning(
                    bundleIdentifier: snapshot.appBundleIdentifier,
                    displayName: snapshot.appDisplayName,
                    onWaiting: { self.downloadStatusText = L10n.string("等待应用退出...") }
                )
                guard canProceed else {
                    isDownloading = false
                    downloadStatusText = ""
                    return
                }

                try await downloadAndReplaceKernel(config: snapshot, downloadID: downloadID)
                downloadService.cleanupTemporaryFiles()
                refreshStatus()

                isDownloading = false
                downloadProgress = nil
                downloadStatusText = ""
                operationResults[.replace] = OperationResult(message: L10n.string("内核替换成功"), isError: false, kernelPath: snapshot.kernelPath)
                Toast.success(L10n.string("内核替换成功"))
                AppLogger.info("内核替换操作完成")
            } catch {
                isDownloading = false
                downloadProgress = nil
                downloadStatusText = ""
                downloadService.cleanupTemporaryFiles()
                handleError(error, for: .replace, kernelPath: snapshot.kernelPath)
            }
        }
    }

    /// 从 GitHub 下载最新预发布内核并替换当前内核文件
    /// - Parameter config: 操作开始时拍下的配置快照（而非实时读取 `self.config`）
    private func downloadAndReplaceKernel(config: MihomoConfig, downloadID: UUID) async throws {
        downloadStatusText = L10n.string("正在下载内核...")
        let downloadedPath = try await downloadService.downloadLatestKernel(
            releasesURL: config.githubReleasesURL,
            filenameTemplate: config.kernelFilenameTemplate
        ) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.activeDownloadID == downloadID, self.isDownloading else { return }
                self.downloadProgress = progress
                if let progress, progress < 1.0 {
                    self.downloadStatusText = L10n.format("正在下载... %lld%%", Int(progress * 100))
                } else if progress != nil {
                    self.downloadStatusText = L10n.string("正在解压...")
                } else {
                    self.downloadStatusText = L10n.string("正在下载内核...")
                }
            }
        }

        AppLogger.info("内核下载完成: \(downloadedPath)")
        // The host can be relaunched during a long download; never replace its live kernel.
        guard !processService.isHostAppRunning(bundleIdentifier: config.appBundleIdentifier, displayName: config.appDisplayName) else {
            throw MihomoError.hostAppIsRunning(config.appDisplayName)
        }
        downloadStatusText = L10n.string("正在替换内核...")
        try await fileService.replaceKernel(with: downloadedPath, kernelPath: config.kernelPath)
    }

    /// 恢复内核
    func restoreKernel() {
        guard !isLoading, !isDownloading else { return }
        guard let snapshot = config else { reportConfigurationFailure(); return }
        operationResults[.restore] = nil
        activeTool = .restore
        AppLogger.debug("开始恢复内核操作")
        isLoading = true


        Task {
            defer {
                isLoading = false
                activeTool = nil
            }
            do {
                let canProceed = try await ensureHostAppQuitIfRunning(
                    bundleIdentifier: snapshot.appBundleIdentifier,
                    displayName: snapshot.appDisplayName
                )
                guard canProceed else {
                    return
                }

                try await fileService.restoreKernel(kernelPath: snapshot.kernelPath)
                refreshStatus()

                operationResults[.restore] = OperationResult(message: L10n.string("内核恢复成功"), isError: false, kernelPath: snapshot.kernelPath)
                Toast.success(L10n.string("内核恢复成功"))
                AppLogger.info("内核恢复操作完成")
            } catch {
                handleError(error, for: .restore, kernelPath: snapshot.kernelPath)
            }
        }
    }

    /// 若关联应用正在运行，弹窗请求用户退出并等待其退出
    ///
    /// - Parameters:
    ///   - bundleIdentifier: 关联应用的 Bundle Identifier（快照值，非实时读取）
    ///   - displayName: 关联应用的显示名称（快照值，非实时读取）
    ///   - onWaiting: 用户同意退出、开始等待前的回调（用于更新调用方特定的提示文案）
    /// - Returns: true 表示可以继续后续操作（未运行，或已确认退出并等到）；false 表示用户取消
    private func ensureHostAppQuitIfRunning(
        bundleIdentifier: String,
        displayName: String,
        onWaiting: (() -> Void)? = nil
    ) async throws -> Bool {
        guard processService.isHostAppRunning(bundleIdentifier: bundleIdentifier, displayName: displayName) else {
            return true
        }

        AppLogger.debug("关联应用正在运行，请求退出")
        let shouldContinue = try await processService.requestQuitHostApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
        guard shouldContinue else {
            AppLogger.info("用户取消退出关联应用，操作中止")
            return false
        }

        onWaiting?()
        try await processService.waitForHostAppToQuit(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
        return true
    }

    private func reportConfigurationFailure() {
        if case .failure(let error) = configuration {
            Toast.error(error.localizedDescription)
        }
    }

    /// 处理错误
    private func handleError(_ error: Error, for tool: KernelTool, kernelPath: String) {
        let message: String
        if let mihomoError = error as? MihomoError {
            message = mihomoError.errorDescription ?? L10n.string("未知错误")
        } else if error is CancellationError {
            message = L10n.string("操作已取消")
        } else {
            message = error.localizedDescription
        }
        operationResults[tool] = OperationResult(message: message, isError: true, kernelPath: kernelPath)
        Toast.error(message)
        AppLogger.error("操作失败: \(message)")
    }
}
