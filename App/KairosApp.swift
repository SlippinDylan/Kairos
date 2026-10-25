import SwiftUI

@main
struct KairosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppKit owns the retained popover; no standalone window is created at launch.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {}
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .appTermination) {
                    Button(L10n.string("关闭")) {
                        WindowCoordinator.shared.hideMainWindow()
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
            }
    }
}
