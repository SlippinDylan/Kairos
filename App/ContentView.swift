import SwiftUI

struct ContentView: View {
    @Environment(WindowCoordinator.self) private var windowCoordinator

    var body: some View {
        selectedContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .buttonBorderShape(.capsule)
            .overlay(alignment: .top) { ToastOverlay().padding(.top, 8) }
            .onExitCommand { windowCoordinator.hideMainWindow() }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch windowCoordinator.selectedTab {
        case 6:
            NetworkMonitorView(sceneType: .dnsControl)
        case 1:
            NetworkToolsView()
        case 4:
            SettingsView()
        case 5:
            AboutView()
                .safeAreaInset(edge: .top, spacing: 0) { PopoverNavigationBar { EmptyView() } }
        default:
            NetworkMonitorView(sceneType: .appControl)
        }
    }
}

#Preview {
    ContentView()
        .environment(NetworkMonitor())
        .environment(MihomoViewModel())
        .environment(SettingsViewModel())
        .environment(NetworkToolsViewModel())
        .environment(WindowCoordinator.forPreview())
}
