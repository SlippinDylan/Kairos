import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let onShowTab: (Int?) -> Void
    private let onQuit: () -> Void

    init(onShowTab: @escaping (Int?) -> Void, onQuit: @escaping () -> Void) {
        self.onShowTab = onShowTab
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            preconditionFailure("NSStatusItem must provide a status bar button")
        }

        button.image = NSImage(systemSymbolName: "wifi.router", accessibilityDescription: "Kairos")
        button.image?.isTemplate = true
        button.toolTip = "Kairos"
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        addNavigationItem(title: "网络控制", systemImage: "globe", tab: 0)
        addNavigationItem(title: "网络工具", systemImage: "wrench.and.screwdriver", tab: 1)
        addNavigationItem(title: "Mihomo", systemImage: "shippingbox", tab: 2)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string("退出"),
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addNavigationItem(title: String, systemImage: String, tab: Int) {
        let item = NSMenuItem(
            title: L10n.string(title),
            action: #selector(showSelectedTab(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        item.representedObject = tab
        item.target = self
        menu.addItem(item)
    }

    @objc private func handleStatusItemClick() {
        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            onShowTab(nil)
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showSelectedTab(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Int else { return }
        onShowTab(tab)
    }

    @objc private func quitApplication() {
        onQuit()
    }
}
