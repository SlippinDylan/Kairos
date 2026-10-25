import AppKit
import SwiftUI

/// Keeps native popover chrome outside the SwiftUI layout and size constraints.
@MainActor
final class PopoverContentViewController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        hostingController = NSHostingController(rootView: rootView)
        // The popover owns sizing; SwiftUI must not constrain or resize its window.
        hostingController.sizingOptions = []
        // The child is already constrained to the native safe area below.
        hostingController.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = PopoverBackgroundView()
        addChild(hostingController)
        let content = hostingController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            content.topAnchor.constraint(equalTo: safeArea.topAnchor),
            content.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
    }
}

private final class PopoverBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
