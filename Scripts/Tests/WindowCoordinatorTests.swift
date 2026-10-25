import AppKit

// Keep presentation checks independent of app startup, network IO, and visible UI.
enum AppLogger { static func warning(_ message: String) {} }
enum DesignSystem {
    enum Window {
        static let width: CGFloat = 540
        static let minimumHeight: CGFloat = 720
    }
}

@main @MainActor
struct WindowCoordinatorTests {
    private static var checks = 0

    static func main() {
        let app = RecordingApplication.shared
        precondition(app is RecordingApplication)
        app.setActivationPolicy(.prohibited)
        let popover = RecordingPopover()
        let coordinator = WindowCoordinator.forPreview(popover: popover)
        let anchor = NSView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        let controller = NSViewController()
        controller.view = NSView()

        coordinator.requestShow(tab: 4)
        expect(!popover.isShown, "show waits until the menu-bar anchor is configured")
        coordinator.requestShow(tab: 1)
        coordinator.configurePopover(contentViewController: controller, anchor: anchor)
        expect(popover.isShown && popover.showCount == 1, "pending show opens exactly one popover")
        expect(coordinator.selectedTab == 1, "latest requested tab is selected")
        expect(popover.lastAnchor === anchor && popover.lastEdge == .minY, "native arrow is anchored below the status item")
        expect(popover.behavior == .applicationDefined, "outside dismissal is controlled without discarding state")
        coordinator.showMainWindow()
        expect(popover.showCount == 1, "repeated show reuses the same presentation")
        coordinator.toggleMainWindow()
        expect(!popover.isShown, "second menu-bar click hides the popover")
        expect(popover.contentViewController === controller && coordinator.selectedTab == 1, "hiding retains the hosting controller and current module")
        coordinator.toggleMainWindow()
        expect(popover.isShown && popover.showCount == 2, "reopening reuses the retained popover")
        coordinator.setContentSize(CGSize(width: 704, height: 632))
        expect(popover.contentSize == CGSize(width: 704, height: 632), "result dimensions update the native popover")
        expect(coordinator.maximumContentWidth == nil, "unattached previews have no screen width constraint")
        popover.contentSize = .zero
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: app)
        expect(popover.contentSize == CGSize(width: 704, height: 632), "display changes reapply the current requested dimensions")
        expect(coordinator.selectedTab == 1 && popover.contentViewController === controller, "display changes preserve navigation and hosted state")
        coordinator.hideMainWindow()
        coordinator.showMainWindow()
        expect(coordinator.contentWidth == 704 && coordinator.contentHeight == 632, "hide and reopen retain result dimensions")
        expect(popover.contentViewController === controller, "result reopening never replaces content")
        coordinator.setContentSize(CGSize(width: 540, height: 136))
        expect(popover.contentSize == CGSize(width: 540, height: 136), "new detection returns to compact sizing")
        coordinator.requestShow(tab: 5)
        expect(coordinator.selectedTab == 5 && coordinator.contentHeight == 720, "navigation restores ordinary page dimensions")
        coordinator.requestShow(tab: 6)
        expect(coordinator.selectedTab == 6, "DNS remains a top-level module")
        coordinator.requestShow(tab: 2)
        coordinator.requestShow(tab: 3)
        coordinator.requestShow(tab: 7)
        expect(coordinator.selectedTab == 6, "retired and invalid modules are rejected")

        let hiddenPopover = RecordingPopover()
        let hidden = WindowCoordinator.forPreview(popover: hiddenPopover)
        hidden.requestShow(tab: 0)
        hidden.requestHide()
        hidden.configurePopover(contentViewController: NSViewController(), anchor: anchor)
        expect(!hiddenPopover.isShown, "login hide supersedes pending show")
        hidden.requestShow(tab: 4)
        expect(hiddenPopover.isShown, "explicit navigation shows an initially hidden interface")
        hidden.hideMainWindow()
        coordinator.hideMainWindow()

        let screen = CGRect(x: 0, y: 0, width: 600, height: 500)
        expect(WindowCoordinator.constrainedSize(requested: CGSize(width: 704, height: 720), visibleFrame: screen) == CGSize(width: 576, height: 476), "small screens cap both dimensions including arrow space")
        expect(WindowCoordinator.constrainedSize(requested: CGSize(width: 540, height: 136), visibleFrame: screen) == CGSize(width: 540, height: 136), "compact content keeps its requested size")
        expect(WindowCoordinator.constrainedSize(requested: CGSize(width: 704, height: 632), visibleFrame: nil) == CGSize(width: 704, height: 632), "unattached previews keep deterministic sizing")
        expect(app.activationPolicy() == .prohibited, "presentation does not change the activation policy")
        print("WindowCoordinator: \(checks) checks passed")
    }

    private static func expect(_ condition: Bool, _ name: String) {
        precondition(condition, "FAIL: \(name)")
        checks += 1
    }
}

@MainActor private final class RecordingApplication: NSApplication {
    override func activate() {}
}

@MainActor private final class RecordingPopover: NSPopover {
    private var recordedShown = false
    var showCount = 0
    weak var lastAnchor: NSView?
    var lastEdge: NSRectEdge?
    override var isShown: Bool { recordedShown }
    override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        recordedShown = true
        showCount += 1
        lastAnchor = positioningView
        lastEdge = preferredEdge
    }
    override func close() { recordedShown = false }
}
