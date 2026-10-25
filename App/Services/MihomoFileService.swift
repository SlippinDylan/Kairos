//
//  MihomoFileService.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//
import Darwin
import Foundation

/// Mihomo 文件操作服务
///
/// ## 架构说明
/// - 状态检查：使用普通 FileManager（无需特权）
/// - 备份、替换和恢复仅支持用户主目录内、父目录可写的普通文件
/// - 新文件在目标目录完成 staging 和签名后通过原子交换提交
/// - 所有方法均以参数形式接收路径，不自行读取持久化配置，
///   避免与调用方（ViewModel）内存中尚未保存的编辑状态不一致
final class MihomoFileService {
    private let fileManager = FileManager.default

    // MARK: - 状态检查

    /// 检查关联应用的安装状态
    /// - Parameter appBundlePath: 关联应用的 Bundle 路径
    func checkHostAppInstallation(appBundlePath: String) -> HostAppInstallStatus {
        AppLogger.debug("检查关联应用安装状态")

        guard !appBundlePath.isEmpty else {
            AppLogger.debug("尚未关联应用")
            return .notConfigured
        }

        if fileManager.fileExists(atPath: appBundlePath) {
            AppLogger.info("关联应用已安装: \(appBundlePath)")
            return .installed
        } else {
            AppLogger.info("关联应用未找到: \(appBundlePath)")
            return .notInstalled
        }
    }

    /// 获取内核状态
    /// - Parameter kernelPath: 内核文件路径
    func getKernelStatus(kernelPath: String) -> KernelStatus {
        AppLogger.debug("获取内核状态")
        let kernelPath = expandedFilePath(kernelPath)
        let backupPath = kernelPath.isEmpty ? "" : kernelPath + ".bak"

        let kernelExists = !kernelPath.isEmpty && fileManager.fileExists(atPath: kernelPath)
        let backupExists = !backupPath.isEmpty && fileManager.fileExists(atPath: backupPath)

        AppLogger.info("内核状态: 内核存在=\(kernelExists), 备份存在=\(backupExists)")
        return KernelStatus(
            kernelExists: kernelExists,
            backupExists: backupExists,
            kernelPath: kernelPath,
            backupPath: backupPath
        )
    }

    // MARK: - 内核操作

    /// 备份内核文件
    ///
    /// - Parameter kernelPath: 内核文件路径
    /// - Throws: MihomoError
    ///
    func backupKernel(kernelPath: String) throws {
        AppLogger.debug("开始备份内核文件")
        let kernelURL = try validatedExistingKernelURL(kernelPath)
        let backupURL = URL(fileURLWithPath: kernelURL.path + ".bak")

        if fileManager.fileExists(atPath: backupURL.path) {
            AppLogger.warning("备份内核失败: 备份文件已存在")
            throw MihomoError.backupAlreadyExists
        }

        let stagingURL = uniqueStagingURL(for: backupURL)
        do {
            try fileManager.copyItem(at: kernelURL, to: stagingURL)
            try preserveFilePermissions(from: kernelURL, to: stagingURL)
            try verifyMatchingFileSize(source: kernelURL, copy: stagingURL)
            try fileManager.moveItem(at: stagingURL, to: backupURL)
            AppLogger.info("内核文件备份成功")
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            AppLogger.error("备份内核失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed(
                L10n.format("备份内核失败: %@", error.localizedDescription)
            )
        }
    }

    /// 通过同目录 staging 原子替换内核文件
    ///
    /// - Parameters:
    ///   - newKernelPath: 新内核文件路径
    ///   - kernelPath: 当前生效的内核文件路径
    /// - Throws: MihomoError
    ///
    @MainActor
    func replaceKernel(with newKernelPath: String, kernelPath: String) async throws {
        AppLogger.debug("开始原子替换内核文件: \(newKernelPath)")
        let sourceURL = try validatedRegularFileURL(newKernelPath)
        let kernelURL = try validatedExistingKernelURL(kernelPath)
        let backupURL = URL(fileURLWithPath: kernelURL.path + ".bak")

        try validateArm64MachO(at: sourceURL)
        if !fileManager.fileExists(atPath: backupURL.path) {
            try backupKernel(kernelPath: kernelURL.path)
        } else {
            _ = try validatedRegularFileURL(backupURL.path)
        }

        try installKernel(from: sourceURL, at: kernelURL)
        AppLogger.info("内核文件原子替换成功")
    }

    /// 从备份原子恢复内核文件
    ///
    /// - Parameter kernelPath: 当前生效的内核文件路径
    /// - Throws: MihomoError
    @MainActor
    func restoreKernel(kernelPath: String) async throws {
        AppLogger.debug("开始恢复内核文件")
        let kernelURL = try validatedKernelDestinationURL(kernelPath)
        let backupURL = URL(fileURLWithPath: kernelURL.path + ".bak")
        guard fileManager.fileExists(atPath: backupURL.path) else {
            AppLogger.error("恢复内核失败: 备份文件不存在")
            throw MihomoError.backupNotFound
        }
        let validatedBackupURL = try validatedRegularFileURL(backupURL.path)
        try validateArm64MachO(at: validatedBackupURL)
        try installKernel(from: validatedBackupURL, at: kernelURL)
        AppLogger.info("内核文件恢复成功")
    }

    // MARK: - 私有辅助方法

    private func installKernel(from sourceURL: URL, at kernelURL: URL) throws {
        let stagingURL = uniqueStagingURL(for: kernelURL)
        var stagingContainsOriginal = false

        defer {
            if !stagingContainsOriginal && fileManager.fileExists(atPath: stagingURL.path) {
                do {
                    try fileManager.removeItem(at: stagingURL)
                } catch {
                    AppLogger.warning("清理暂存内核失败: \(error.localizedDescription)")
                }
            }
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try setExecutablePermissions(at: stagingURL)
            try verifyMatchingFileSize(source: sourceURL, copy: stagingURL)
            try validateArm64MachO(at: stagingURL)
            try removeQuarantine(at: stagingURL)
            try runCodeSign(["--force", "--sign", "-"], at: stagingURL)
            try runCodeSign(["--verify", "--verbose=2"], at: stagingURL)
            try validateMihomoVersion(at: stagingURL)

            if fileManager.fileExists(atPath: kernelURL.path) {
                // Atomic swap retains the original inode for rollback, including its owner and mode.
                try swapFiles(stagingURL, kernelURL)
                stagingContainsOriginal = true
                do {
                    try removeQuarantine(at: kernelURL)
                    try runCodeSign(["--verify", "--verbose=2"], at: kernelURL)
                    try validateMihomoVersion(at: kernelURL)
                } catch {
                    let verificationError = error
                    do {
                        try swapFiles(stagingURL, kernelURL)
                        stagingContainsOriginal = false
                    } catch {
                        throw MihomoError.fileOperationFailed(
                            "内核验证失败且回滚失败，原文件保留在 \(stagingURL.path): \(error.localizedDescription)"
                        )
                    }
                    throw verificationError
                }

                do {
                    try fileManager.removeItem(at: stagingURL)
                    stagingContainsOriginal = false
                } catch {
                    AppLogger.warning("替换成功，但清理旧内核失败: \(stagingURL.path): \(error.localizedDescription)")
                }
            } else {
                try fileManager.moveItem(at: stagingURL, to: kernelURL)
                do {
                    try removeQuarantine(at: kernelURL)
                    try runCodeSign(["--verify", "--verbose=2"], at: kernelURL)
                    try validateMihomoVersion(at: kernelURL)
                } catch {
                    try fileManager.removeItem(at: kernelURL)
                    throw error
                }
            }
        } catch {
            AppLogger.error("内核安装失败: \(error.localizedDescription)")
            if let mihomoError = error as? MihomoError {
                throw mihomoError
            }
            throw MihomoError.fileOperationFailed(error.localizedDescription)
        }
    }

    private func swapFiles(_ firstURL: URL, _ secondURL: URL) throws {
        guard renameatx_np(AT_FDCWD, firstURL.path, AT_FDCWD, secondURL.path, UInt32(RENAME_SWAP)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func removeQuarantine(at url: URL) throws {
        guard removexattr(url.path, "com.apple.quarantine", 0) == 0 || errno == ENOATTR else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func runCodeSign(_ arguments: [String], at url: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = arguments + [url.path]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        try task.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            throw MihomoError.fileOperationFailed("codesign: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func validateMihomoVersion(at url: URL) throws {
        let task = Process()
        task.executableURL = url
        task.arguments = ["-v"]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        try task.run()
        let deadline = Date().addingTimeInterval(5)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if task.isRunning {
            task.terminate()
            task.waitUntilExit()
            throw MihomoError.fileOperationFailed("Mihomo -v timed out")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard task.terminationStatus == 0,
              output.range(of: "mihomo|clash[ ._-]*meta", options: [.regularExpression, .caseInsensitive]) != nil else {
            throw MihomoError.fileOperationFailed("Mihomo -v: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func validatedExistingKernelURL(_ path: String) throws -> URL {
        let url = try validatedKernelDestinationURL(path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw MihomoError.kernelFileNotFound
        }
        return try validatedRegularFileURL(url.path)
    }

    private func validatedKernelDestinationURL(_ path: String) throws -> URL {
        guard !path.isEmpty else {
            throw MihomoError.kernelPathNotConfigured
        }

        let expandedPath = expandedFilePath(path)
        guard NSString(string: expandedPath).isAbsolutePath else {
            throw MihomoError.invalidFilePath
        }

        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath()
        guard url.path == resolvedURL.path else {
            throw MihomoError.invalidFilePath
        }

        let homeURL = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        guard resolvedURL.path.hasPrefix(homeURL.path + "/"),
              !resolvedURL.pathComponents.contains(where: {
                  $0.lowercased().hasSuffix(".app")
              }) else {
            throw MihomoError.permissionDenied
        }

        let parentURL = resolvedURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentURL.path) else {
            throw MihomoError.permissionDenied
        }

        if fileManager.fileExists(atPath: resolvedURL.path) {
            _ = try validatedRegularFileURL(resolvedURL.path)
        }
        return resolvedURL
    }

    private func validatedRegularFileURL(_ path: String) throws -> URL {
        let expandedPath = expandedFilePath(path)
        guard NSString(string: expandedPath).isAbsolutePath else {
            throw MihomoError.invalidFilePath
        }

        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        let resolvedURL = url.resolvingSymlinksInPath()
        guard url.path == resolvedURL.path,
              fileManager.fileExists(atPath: resolvedURL.path) else {
            throw MihomoError.invalidFilePath
        }

        let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              fileManager.isReadableFile(atPath: resolvedURL.path) else {
            throw MihomoError.invalidFilePath
        }
        return resolvedURL
    }

    private func expandedFilePath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private func uniqueStagingURL(for destinationURL: URL) -> URL {
        destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).kairos-\(UUID().uuidString).staging"
        )
    }

    private func verifyMatchingFileSize(source: URL, copy: URL) throws {
        let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let copySize = try copy.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard sourceSize > 0, sourceSize == copySize else {
            throw MihomoError.fileOperationFailed(L10n.string("文件完整性验证失败"))
        }
    }

    private func validateArm64MachO(at url: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        task.arguments = ["-archs", url.path]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        try task.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let architectures = output.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard task.terminationStatus == 0, architectures.contains("arm64") else {
            throw MihomoError.fileOperationFailed(
                L10n.string("所选文件不是 arm64 Mach-O 可执行文件")
            )
        }
    }

    /// 保持原文件权限
    ///
    /// - Parameters:
    ///   - source: 源文件 URL
    ///   - destination: 目标文件 URL
    /// - Throws: Error
    private func preserveFilePermissions(from source: URL, to destination: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        if let permissions = attributes[.posixPermissions] {
            try fileManager.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: destination.path
            )
        }
    }

    private func setExecutablePermissions(at url: URL) throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: UInt16(0o755))
        ]

        do {
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            AppLogger.error("设置文件权限失败: \(error.localizedDescription)")
            throw MihomoError.fileOperationFailed(
                L10n.format("设置文件权限失败: %@", error.localizedDescription)
            )
        }
    }
}
