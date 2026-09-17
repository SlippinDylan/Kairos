//
//  MihomoFileService.swift
//  Kairos
//
//  Created by SlippinDylan on 2025/12/30.
//
import Foundation

/// Mihomo 文件操作服务
///
/// ## 架构说明
/// - 状态检查：使用普通 FileManager（无需特权）
/// - 备份、替换和恢复仅支持用户主目录内可写的普通文件
/// - 新文件在目标目录完成 staging 后通过原子替换提交
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
        let kernelURL = try validatedWritableKernelURL(kernelPath)
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
            throw MihomoError.fileOperationFailed("备份内核失败: \(error.localizedDescription)")
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
        let sourceURL = try validatedRegularFileURL(newKernelPath, mustBeWritable: false)
        let kernelURL = try validatedWritableKernelURL(kernelPath)
        let backupURL = URL(fileURLWithPath: kernelURL.path + ".bak")
        let stagingURL = uniqueStagingURL(for: kernelURL)

        try validateArm64MachO(at: sourceURL)
        if !fileManager.fileExists(atPath: backupURL.path) {
            try backupKernel(kernelPath: kernelURL.path)
        } else {
            _ = try validatedRegularFileURL(backupURL.path, mustBeWritable: false)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try setExecutablePermissions(at: stagingURL)
            try verifyMatchingFileSize(source: sourceURL, copy: stagingURL)
            try validateArm64MachO(at: stagingURL)
            _ = try fileManager.replaceItemAt(kernelURL, withItemAt: stagingURL)
            AppLogger.info("内核文件原子替换成功")
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            AppLogger.error("内核替换失败: \(error.localizedDescription)")
            if let mihomoError = error as? MihomoError {
                throw mihomoError
            }
            throw MihomoError.fileOperationFailed("替换内核失败: \(error.localizedDescription)")
        }
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
        let validatedBackupURL = try validatedRegularFileURL(backupURL.path, mustBeWritable: false)
        try validateArm64MachO(at: validatedBackupURL)
        let stagingURL = uniqueStagingURL(for: kernelURL)

        do {
            try fileManager.copyItem(at: validatedBackupURL, to: stagingURL)
            try setExecutablePermissions(at: stagingURL)
            try verifyMatchingFileSize(source: validatedBackupURL, copy: stagingURL)
            if fileManager.fileExists(atPath: kernelURL.path) {
                _ = try fileManager.replaceItemAt(kernelURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: kernelURL)
            }
            AppLogger.info("内核文件恢复成功")
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            AppLogger.error("恢复内核失败: \(error.localizedDescription)")
            if let mihomoError = error as? MihomoError {
                throw mihomoError
            }
            throw MihomoError.fileOperationFailed("恢复内核失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有辅助方法

    private func validatedWritableKernelURL(_ path: String) throws -> URL {
        let url = try validatedKernelDestinationURL(path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw MihomoError.kernelFileNotFound
        }
        return try validatedRegularFileURL(url.path, mustBeWritable: true)
    }

    private func validatedKernelDestinationURL(_ path: String) throws -> URL {
        guard !path.isEmpty else {
            throw MihomoError.kernelPathNotConfigured
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
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
            _ = try validatedRegularFileURL(resolvedURL.path, mustBeWritable: true)
        }
        return resolvedURL
    }

    private func validatedRegularFileURL(_ path: String, mustBeWritable: Bool) throws -> URL {
        let expandedPath = NSString(string: path).expandingTildeInPath
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
        if mustBeWritable, !fileManager.isWritableFile(atPath: resolvedURL.path) {
            throw MihomoError.permissionDenied
        }
        return resolvedURL
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
            throw MihomoError.fileOperationFailed("文件完整性验证失败")
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
            throw MihomoError.fileOperationFailed("所选文件不是 arm64 Mach-O 可执行文件")
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
            throw MihomoError.fileOperationFailed("设置文件权限失败: \(error.localizedDescription)")
        }
    }
}
