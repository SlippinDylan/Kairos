import AppKit
import Observation

/// Owns the retained menu-bar interface and its presentation state.
@MainActor
@Observable
final class WindowCoordinator: NSObject, NSPopoverDelegate {
    static let shared = WindowCoordinator(popover: NSPopover())

    /// Indices 2 and 3 belong to retired standalone modules.
    var selectedTab = 0 {
        didSet {
            if selectedTab != oldValue {
                requestedWidth = DesignSystem.Window.width
                requestedHeight = DesignSystem.Window.minimumHeight
                updateContentSize()
            }
        }
    }
    private(set) var contentWidth = DesignSystem.Window.width
    private(set) var contentHeight = DesignSystem.Window.minimumHeight
    private(set) var maximumContentWidth: CGFloat?
    private(set) var maximumContentHeight = DesignSystem.Window.minimumHeight
    private(set) var maximumDetailHeight = DesignSystem.Window.minimumHeight * 0.6

    @ObservationIgnored private let popover: NSPopover
    @ObservationIgnored private weak var anchor: NSView?
    @ObservationIgnored private var pendingVisibility: Bool?
    @ObservationIgnored private var requestedWidth = DesignSystem.Window.width
    @ObservationIgnored private var requestedHeight = DesignSystem.Window.minimumHeight
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var isTrackingMenu = false

    private init(popover: NSPopover) {
        self.popover = popover
        super.init()
        popover.behavior = .applicationDefined
        // Extend the SwiftUI surface into the native arrow while content respects the safe area.
        popover.hasFullSizeContent = true
        popover.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(anchorScreenDidChange), name: NSWindow.didChangeScreenNotification, object: nil)
    }

    static func forPreview() -> WindowCoordinator {
        WindowCoordinator(popover: NSPopover())
    }

    static func forPreview(popover: NSPopover) -> WindowCoordinator {
        WindowCoordinator(popover: popover)
    }

    func configurePopover(contentViewController: NSViewController, anchor: NSView) {
        // Retain this controller across close/show cycles so SwiftUI drafts and routes survive.
        contentViewController.view.setFrameSize(CGSize(width: contentWidth, height: contentHeight))
        popover.contentViewController = contentViewController
        self.anchor = anchor
        updateContentSize()
        if let pendingVisibility {
            self.pendingVisibility = nil
            if pendingVisibility { showMainWindow() }
        }
    }

    func requestShow(tab: Int) { showMainWindow(tab: tab) }
    func requestHide() { hideMainWindow() }

    func toggleMainWindow() {
        if popover.isShown { hideMainWindow() } else { showMainWindow() }
    }

    func showMainWindow(tab: Int? = nil) {
        if let tab {
            guard [0, 1, 4, 5, 6].contains(tab) else {
                AppLogger.warning("尝试切换到无效的 Tab 索引: \(tab)")
                return
            }
            selectedTab = tab
        }
        guard let anchor else {
            pendingVisibility = true
            return
        }
        updateContentSize()
        guard !popover.isShown else { return }
        NSApp.activate()
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startMonitoring()
    }

    func hideMainWindow() {
        pendingVisibility = false
        popover.close()
        stopMonitoring()
    }

    func setContentSize(_ size: CGSize) {
        requestedWidth = size.width
        requestedHeight = size.height
        updateContentSize()
    }

    func resetContentSize() {
        setContentSize(CGSize(width: DesignSystem.Window.width, height: DesignSystem.Window.minimumHeight))
    }

    private var nativeChromeSize: CGSize {
        let insets = popover.contentViewController?.view.safeAreaInsets ?? NSEdgeInsets()
        return CGSize(width: insets.left + insets.right, height: insets.top + insets.bottom)
    }

    func constrainedContentSize(_ requested: CGSize) -> CGSize {
        let chrome = nativeChromeSize
        let nativeSize = Self.constrainedSize(
            requested: CGSize(width: requested.width + chrome.width, height: requested.height + chrome.height),
            visibleFrame: anchor?.window?.screen?.visibleFrame
        )
        return CGSize(width: max(1, nativeSize.width - chrome.width), height: max(1, nativeSize.height - chrome.height))
    }

    static func constrainedSize(requested: CGSize, visibleFrame: CGRect?) -> CGSize {
        guard let visibleFrame else { return requested }
        // Leave room for the native arrow and shadow beneath the menu bar.
        return CGSize(width: min(requested.width, max(1, visibleFrame.width - 24)),
                      height: min(requested.height, max(1, visibleFrame.height - 24)))
    }

    static func detailHeightLimit(visibleFrame: CGRect?, chromeHeight: CGFloat) -> CGFloat {
        let screenHeight = visibleFrame?.height ?? DesignSystem.Window.minimumHeight
        return max(1, screenHeight * 0.6 - chromeHeight)
    }

    private func updateContentSize() {
        let visibleFrame = anchor?.window?.screen?.visibleFrame
        let chrome = nativeChromeSize
        let maximumWidth = visibleFrame.map { max(1, $0.width - 24 - chrome.width) }
        if maximumContentWidth != maximumWidth { maximumContentWidth = maximumWidth }
        let maximumHeight = visibleFrame.map { max(1, $0.height - 24 - chrome.height) } ?? DesignSystem.Window.minimumHeight
        if maximumContentHeight != maximumHeight { maximumContentHeight = maximumHeight }
        let detailHeight = Self.detailHeightLimit(visibleFrame: visibleFrame, chromeHeight: chrome.height)
        if maximumDetailHeight != detailHeight { maximumDetailHeight = detailHeight }
        let size = constrainedContentSize(CGSize(width: requestedWidth, height: requestedHeight))
        let nativeSize = CGSize(width: size.width + chrome.width, height: size.height + chrome.height)
        if contentWidth != size.width { contentWidth = size.width }
        if contentHeight != size.height { contentHeight = size.height }
        if popover.contentSize != nativeSize {
            // Internal navigation commits one size without interpolating an already replaced page.
            let animates = popover.animates
            popover.animates = false
            popover.contentSize = nativeSize
            popover.animates = animates
        }
    }

    func popoverWillShow(_ notification: Notification) {
        // Native safe-area insets become available once AppKit attaches the content view.
        updateContentSize()
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoring()
    }

    private func startMonitoring() {
        stopMonitoring()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.hasSystemDialog { return event }
            if event.type == .keyDown {
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "q" {
                    self.hideMainWindow()
                    return nil
                }
                // Let text input handle Escape before SwiftUI receives an exit command.
                return event
            }
            let point = NSEvent.mouseLocation
            if self.containsScreenPoint(point) { return event }
            self.hideMainWindow()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.hasSystemDialog else { return }
                self.hideMainWindow()
            }
        }
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) { isTrackingMenu = true }
    @objc private func menuDidEndTracking(_ notification: Notification) { isTrackingMenu = false }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        updateContentSize()
    }

    @objc private func anchorScreenDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === anchor?.window else { return }
        updateContentSize()
    }

    private var hasSystemDialog: Bool {
        isTrackingMenu || NSApp.modalWindow != nil || NSApp.windows.contains {
            $0.isVisible && ($0 is NSSavePanel || $0.attachedSheet != nil)
        }
    }

    private func containsScreenPoint(_ point: CGPoint) -> Bool {
        if let window = popover.contentViewController?.view.window, window.frame.contains(point) { return true }
        if let anchor, let window = anchor.window {
            return window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(point)
        }
        return false
    }

    private func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}
