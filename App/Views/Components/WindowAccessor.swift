import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onResolve: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowResolvingView {
        WindowResolvingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: WindowResolvingView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindowIfAvailable()
    }
}

final class WindowResolvingView: NSView {
    var onResolve: @MainActor (NSWindow) -> Void

    init(onResolve: @escaping @MainActor (NSWindow) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfAvailable()
    }

    func resolveWindowIfAvailable() {
        guard let window else { return }
        onResolve(window)
    }
}
