import AppKit
import SwiftUI

extension View {
    func dismissOnOutsideClick(isEnabled: Bool = true) -> some View {
        modifier(SheetOutsideDismissalModifier(isEnabled: isEnabled))
    }
}

private struct SheetOutsideDismissalModifier: ViewModifier {
    let isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .background {
                SheetOutsideClickMonitor(isEnabled: isEnabled) { dismiss() }
            }
            .onExitCommand {
                if isEnabled { dismiss() }
            }
    }
}

private struct SheetOutsideClickMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> SheetOutsideClickView {
        SheetOutsideClickView(isEnabled: isEnabled, onDismiss: onDismiss)
    }

    func updateNSView(_ view: SheetOutsideClickView, context: Context) {
        view.isEnabled = isEnabled
        view.onDismiss = onDismiss
    }

    static func dismantleNSView(_ view: SheetOutsideClickView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class SheetOutsideClickView: NSView {
    var isEnabled: Bool
    var onDismiss: () -> Void
    private var monitor: Any?

    init(isEnabled: Bool, onDismiss: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.onDismiss = onDismiss
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let sheet = self.window, let eventWindow = event.window else { return event }
            let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
            guard Self.shouldDismiss(sheet: sheet, eventWindow: eventWindow, screenPoint: point, isEnabled: self.isEnabled) else {
                return event
            }
            self.onDismiss()
            // Consume the click so it cannot activate controls behind the sheet.
            return nil
        }
    }

    static func shouldDismiss(sheet: NSWindow, eventWindow: NSWindow, screenPoint: NSPoint, isEnabled: Bool) -> Bool {
        guard isEnabled, let parent = sheet.sheetParent,
              sheet.attachedSheet == nil,
              eventWindow === sheet || eventWindow === parent else { return false }
        return parent.frame.contains(screenPoint) && !sheet.frame.contains(screenPoint)
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
