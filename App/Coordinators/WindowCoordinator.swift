//
//  WindowCoordinator.swift
//  Kairos
//
//  Created by SlippinDylan on 2026/01/03.
//

import AppKit
import Observation

/// Owns main-window presentation requests and the selected module.
@MainActor
@Observable
final class WindowCoordinator: NSObject {
    static let shared = WindowCoordinator()

    /// Selected module index (0–4).
    var selectedTab: Int = 0

    private enum PresentationRequest {
        case show
        case hide
    }

    @ObservationIgnored
    private var pendingRequest: PresentationRequest?

    @ObservationIgnored
    private var openMainWindow: (() -> Void)?

    @ObservationIgnored
    private var isOpeningMainWindow = false

    @ObservationIgnored
    private weak var mainWindow: NSWindow?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    static func forPreview() -> WindowCoordinator {
        WindowCoordinator()
    }

    func requestShow(tab: Int) {
        showMainWindow(tab: tab)
    }

    func requestHide() {
        hideMainWindow()
    }

    func registerOpenWindowAction(_ action: @escaping () -> Void) {
        openMainWindow = action
        processPendingRequestIfPossible()
    }

    func mainWindowDidAppear(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("main")
        mainWindow = window
        isOpeningMainWindow = false
        processPendingRequestIfPossible()
    }

    func showMainWindow(tab: Int? = nil) {
        if let tab {
            guard (0...4).contains(tab) else {
                AppLogger.warning("尝试切换到无效的 Tab 索引: \(tab)")
                return
            }
            selectedTab = tab
        }
        pendingRequest = .show
        processPendingRequestIfPossible()
    }

    func hideMainWindow() {
        pendingRequest = .hide
        processPendingRequestIfPossible()
    }

    private func processPendingRequestIfPossible() {
        guard let pendingRequest else { return }
        switch pendingRequest {
        case .hide:
            guard let mainWindow else { return }
            self.pendingRequest = nil
            mainWindow.orderOut(nil)
        case .show:
            if let mainWindow {
                self.pendingRequest = nil
                present(mainWindow)
            } else if !isOpeningMainWindow, let openMainWindow {
                // Set this before calling SwiftUI, which can register the window synchronously.
                isOpeningMainWindow = true
                openMainWindow()
            }
        }
    }

    private func present(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Accessory-app activation is asynchronous; honor the explicit click immediately.
        window.orderFrontRegardless()
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        mainWindow = nil
        isOpeningMainWindow = false
    }
}
