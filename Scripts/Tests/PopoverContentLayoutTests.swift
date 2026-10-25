import SwiftUI
import AppKit
import Observation

enum AppLogger { static func warning(_ message: String) {} }
enum DesignSystem {
    enum Window {
        static let width: CGFloat = 540
        static let minimumHeight: CGFloat = 720
    }
}

@MainActor @Observable private final class LayoutState {
    var size = CGSize(width: 540, height: 720)
}

private struct LayoutContent: View {
    let state: LayoutState
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 38).padding(12)
            ScrollView { Color.clear.frame(height: 1000).padding(16) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: state.size.width, height: state.size.height)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }
}

// Keep native layout active without displaying the diagnostic windows or activating the app.
@MainActor private final class InvisiblePopover: NSPopover {
    override func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        super.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        contentViewController?.view.window?.alphaValue = 0
    }
}
@MainActor private final class RecordingApplication: NSApplication {
    override func activate() {}
}

@main @MainActor struct PopoverContentLayoutTests {
    static func main() {
        RecordingApplication.shared.setActivationPolicy(.prohibited)
        let state = LayoutState()
        let controller = PopoverContentViewController(rootView: LayoutContent(state: state))
        let anchorWindow = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 24, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        anchorWindow.alphaValue = 0
        anchorWindow.orderFront(nil)
        guard let anchor = anchorWindow.contentView else { preconditionFailure("Missing anchor view") }
        let popover = InvisiblePopover()
        let coordinator = WindowCoordinator.forPreview(popover: popover)
        coordinator.configurePopover(contentViewController: controller, anchor: anchor)
        coordinator.showMainWindow()
        pump()
        checkLayout(controller, coordinator: coordinator, expected: state.size)
        for size in [CGSize(width: 704, height: 660), CGSize(width: 540, height: 164), CGSize(width: 540, height: 720)] {
            state.size = size
            coordinator.setContentSize(size)
            pump()
            checkLayout(controller, coordinator: coordinator, expected: size)
        }
        coordinator.hideMainWindow()
        coordinator.showMainWindow()
        pump()
        checkLayout(controller, coordinator: coordinator, expected: state.size)
        coordinator.hideMainWindow()
        anchorWindow.orderOut(nil)
        print("Native popover layout checks passed: initial, expanded result, compact tool, return, reopen")
    }

    private static func checkLayout(_ controller: NSViewController, coordinator: WindowCoordinator, expected: CGSize) {
        guard let content = controller.children.first?.view else { preconditionFailure("Missing hosted content") }
        let safeFrame = controller.view.safeAreaLayoutGuide.frame
        precondition(abs(safeFrame.width - expected.width) < 1 && abs(safeFrame.height - expected.height) < 1,
                     "Native safe area must retain requested content size: \(safeFrame), expected \(expected)")
        precondition(content.frame == safeFrame, "Hosted content must stay inside the native safe area")
        precondition(coordinator.contentWidth == expected.width && coordinator.contentHeight == expected.height,
                     "SwiftUI must receive the safe content dimensions")
    }
    private static func pump() {
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
}
