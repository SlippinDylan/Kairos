import AppKit

@main
@MainActor
struct SheetOutsideDismissalTests {
    static func main() {
        _ = NSApplication.shared
        let parent = TestWindow(rect: NSRect(x: 100, y: 100, width: 540, height: 720))
        let sheet = TestWindow(rect: NSRect(x: 120, y: 200, width: 500, height: 500))
        let other = TestWindow(rect: parent.frame)
        sheet.testParent = parent
        var checks = 0
        func check(_ expected: Bool, _ window: NSWindow, _ point: NSPoint, enabled: Bool = true) {
            precondition(SheetOutsideClickView.shouldDismiss(sheet: sheet, eventWindow: window, screenPoint: point, isEnabled: enabled) == expected)
            checks += 1
        }
        check(true, parent, NSPoint(x: 110, y: 150))
        check(true, sheet, NSPoint(x: 110, y: 150))
        check(false, sheet, NSPoint(x: 200, y: 300))
        check(false, parent, NSPoint(x: 50, y: 50))
        check(false, other, NSPoint(x: 110, y: 150))
        check(false, parent, NSPoint(x: 110, y: 150), enabled: false)
        sheet.testChild = other
        check(false, parent, NSPoint(x: 110, y: 150))
        sheet.testChild = nil
        sheet.testParent = nil
        check(false, parent, NSPoint(x: 110, y: 150))
        print("Sheet outside dismissal: \(checks) checks passed")
    }
}

@MainActor
private final class TestWindow: NSWindow {
    var testParent: NSWindow?
    var testChild: NSWindow?
    override var sheetParent: NSWindow? { testParent }
    override var attachedSheet: NSWindow? { testChild }

    init(rect: NSRect) {
        super.init(contentRect: rect, styleMask: [], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }
}
