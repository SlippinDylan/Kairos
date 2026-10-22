import AppKit

// Keep these checks independent of app startup, logging, and visible UI.
enum AppLogger {
    static func warning(_ message: String) {}
}

@main
@MainActor
struct WindowCoordinatorTests {
    private static var checks = 0

    static func main() {
        let application = RecordingApplication.shared
        precondition(application is RecordingApplication)
        _ = application.setActivationPolicy(.accessory)

        let pending = WindowCoordinator.forPreview()
        var openCount = 0
        pending.showMainWindow(tab: 2)
        pending.registerOpenWindowAction { openCount += 1 }
        expect(openCount == 1, "a pending show opens a missing window")
        pending.showMainWindow(tab: 1)
        expect(openCount == 1, "repeated clicks do not open duplicate windows")
        let first = RecordingWindow()
        pending.mainWindowDidAppear(first)
        expect(first.presentCount == 1 && pending.selectedTab == 1, "opening uses the latest requested module")
        expect(first.frontCount == 1, "presentation orders the window even before activation completes")
        pending.showMainWindow()
        expect(first.presentCount == 2 && pending.selectedTab == 1, "left click reuses the window and preserves its module")

        first.minimized = true
        pending.showMainWindow(tab: 0)
        expect(!first.minimized && first.restoreCount == 1, "show restores a minimized window")
        expect(pending.selectedTab == 0, "right-click navigation selects the requested module")

        first.close()
        pending.showMainWindow(tab: 2)
        expect(openCount == 2, "closing clears the window even while another owner retains it")
        pending.hideMainWindow()
        let replacement = RecordingWindow()
        pending.mainWindowDidAppear(replacement)
        expect(replacement.presentCount == 0 && replacement.hideCount == 1, "hide cancels presentation of an opening window")
        pending.showMainWindow()
        expect(replacement.presentCount == 1, "a hidden window can be shown again")

        let login = WindowCoordinator.forPreview()
        login.requestHide()
        login.showMainWindow(tab: 2)
        let loginWindow = RecordingWindow()
        login.mainWindowDidAppear(loginWindow)
        expect(loginWindow.presentCount == 1 && loginWindow.hideCount == 0, "an explicit click supersedes the pending login hide")

        let hidden = WindowCoordinator.forPreview()
        hidden.requestHide()
        let hiddenWindow = RecordingWindow()
        hidden.mainWindowDidAppear(hiddenWindow)
        expect(hiddenWindow.hideCount == 1 && hiddenWindow.presentCount == 0, "login launch keeps the initial window hidden")
        hidden.requestShow(tab: 1)
        expect(hiddenWindow.presentCount == 1, "requestShow handles an already registered window immediately")

        let initial = WindowCoordinator.forPreview()
        initial.requestShow(tab: 0)
        let initialWindow = RecordingWindow()
        initial.mainWindowDidAppear(initialWindow)
        var initialOpenCount = 0
        initial.registerOpenWindowAction { initialOpenCount += 1 }
        expect(initialOpenCount == 0 && initialWindow.presentCount == 1, "resolving the initial window before registering the opener avoids duplication")
        replacement.close()
        initial.showMainWindow()
        expect(initialOpenCount == 0 && initialWindow.presentCount == 2, "another window closing cannot clear the main-window reference")

        let synchronous = WindowCoordinator.forPreview()
        let synchronousWindow = RecordingWindow()
        synchronous.registerOpenWindowAction { [weak synchronous] in
            synchronous?.mainWindowDidAppear(synchronousWindow)
        }
        synchronous.showMainWindow(tab: 2)
        expect(synchronousWindow.presentCount == 1, "synchronous window registration processes the show exactly once")
        expect(application.activationPolicy() == .accessory, "show never adds a Dock icon")
        print("WindowCoordinator: \(checks) checks passed")
    }

    private static func expect(_ condition: Bool, _ name: String) {
        guard condition else { fatalError("FAIL: \(name)") }
        checks += 1
    }
}

@MainActor
private final class RecordingApplication: NSApplication {
    override func activate() {}
}

@MainActor
private final class RecordingWindow: NSWindow {
    var presentCount = 0
    var frontCount = 0
    var hideCount = 0
    var restoreCount = 0
    var minimized = false

    init() {
        super.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }

    override var isMiniaturized: Bool { minimized }
    override func makeKeyAndOrderFront(_ sender: Any?) { presentCount += 1 }
    override func orderFrontRegardless() { frontCount += 1 }
    override func orderOut(_ sender: Any?) { hideCount += 1 }
    override func deminiaturize(_ sender: Any?) {
        minimized = false
        restoreCount += 1
    }
}
