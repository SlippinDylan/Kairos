import SwiftUI
import AppKit
import Observation

enum DesignSystem {
    enum Window { static let width: CGFloat = 540 }
    enum Input { static let height: CGFloat = 36; static let actionHeight: CGFloat = 28 }
    enum Spacing { static let standard: CGFloat = 16; static let small: CGFloat = 8; static let medium: CGFloat = 12 }
    enum CornerRadius { static let medium: CGFloat = 6; static let large: CGFloat = 12 }
}
enum L10n { static func string(_ value: String) -> String { value } }
enum AppLogger { static func warning(_ value: String) {} }
struct ToastOverlay: View { var body: some View { EmptyView() } }

@MainActor @Observable final class HarnessState {
    var error: String?
    var text = "1.1.1.1"
    var showsLargeResult = false
    var usesFullCard = false
    var showsWideResult = false
    var pinsInput = false
    var hostWindowSize = CGSize(width: 540, height: 720)
    var maximumContentHeight: CGFloat = 720
    var requestedHeight: CGFloat = 156
    var didReturn = false
    @ObservationIgnored var inputAppearances = 0
    @ObservationIgnored var inputRect = CGRect.zero
    @ObservationIgnored var errorRect = CGRect.zero
    @ObservationIgnored var fullRect = CGRect.zero
    @ObservationIgnored var wideRect = CGRect.zero
}
struct Harness: View {
    @Bindable var state: HarnessState
    var body: some View {
        NetworkToolSheet(
            title: "IP", width: state.hostWindowSize.width,
            preventsClosing: false, fitsContent: true, padsContent: !state.usesFullCard && !state.pinsInput,
            maximumContentHeight: state.maximumContentHeight,
            onClose: { state.didReturn = true },
            onSizeChange: { state.requestedHeight = $0.height }
        ) {
            if state.pinsInput {
                ActionTextField(placeholder: "IP", text: $state.text, actionTitle: "Query", loadingTitle: nil, isLoading: false, isActionDisabled: false, onClear: {}, action: {})
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("toolHarness")) } action: { state.inputRect = $0 }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 22)
            }
        } content: {
            if state.pinsInput {
                Color.clear.frame(height: 1000)
            } else if state.showsWideResult {
                Color.clear.frame(width: 640, height: 80)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("toolHarness")) } action: { state.wideRect = $0 }
                    .padding(16)
            } else if state.usesFullCard {
                Button("Start") {}
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("toolHarness")) } action: { state.fullRect = $0 }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ActionTextField(placeholder: "IP", text: $state.text, actionTitle: "Query", loadingTitle: nil, isLoading: false, isActionDisabled: false, onClear: {}, action: {})
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("toolHarness")) } action: { state.inputRect = $0 }
                        .onAppear { state.inputAppearances += 1 }
                    if let error = state.error {
                        Text(error).foregroundStyle(.red)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("toolHarness")) } action: { state.errorRect = $0 }
                    }
                    if state.showsLargeResult { Color.clear.frame(height: 1000) }
                }
            }
        }
        .frame(width: state.hostWindowSize.width, height: state.requestedHeight, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "toolHarness")
    }
}
@main @MainActor struct NetworkToolSheetSizingTests {
    static func main() {
        let app = NSApplication.shared
        // Keep the regression window off-screen and never activate the app.
        app.setActivationPolicy(.prohibited)
        let state = HarnessState()
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 540, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Harness(state: state))
        window.orderFront(nil)
        pump()
        let initialHeight = state.requestedHeight
        precondition(abs(initialHeight - 156) < 1, "Compact input must not reserve an extra header-sized footer")
        precondition(state.inputAppearances == 1, "Initial measurement must not recreate the input subtree")
        let initialInput = state.inputRect
        let initialBottom = initialHeight - initialInput.maxY
        state.error = "Query failed: request timed out."
        pump()
        let errorHeight = state.requestedHeight
        let errorInput = state.inputRect
        let errorBottom = errorHeight - state.errorRect.maxY
        precondition(errorHeight > initialHeight, "Error must expand the inline tool page")
        precondition(abs(initialInput.minY - errorInput.minY) < 1, "Top padding must stay unchanged")
        precondition(abs(initialBottom - errorBottom) < 1, "Bottom padding must stay unchanged")
        precondition(abs(initialInput.minX - errorInput.minX) < 1, "Horizontal padding must stay unchanged")
        state.error = nil
        pump()
        precondition(abs(state.requestedHeight - initialHeight) < 1, "Clearing error must restore compact height")
        state.showsLargeResult = true
        pump()
        precondition(abs(state.requestedHeight - 720) < 1, "Large results must stop at the supplied total page limit, without a default-window cap")
        precondition(state.inputAppearances == 1, "Expanding to scrollable results must preserve the input subtree")
        state.showsLargeResult = false
        pump()
        precondition(abs(state.requestedHeight - initialHeight) < 1, "Removing results must restore compact height")
        precondition(state.inputAppearances == 1, "Collapsing results must preserve the input subtree")
        state.usesFullCard = true
        pump()
        precondition(abs(state.requestedHeight - 156) < 1, "Full-card action must stay compact below its back header")
        precondition(abs(state.fullRect.minX - 16) < 1 && abs(state.fullRect.minY - 60) < 1, "Full-card action must keep the shared outer margin: \(state.fullRect)")
        precondition(abs(state.fullRect.width - 508) < 1 && abs(state.fullRect.height - 80) < 1, "Full-card action must cover the tool content")
        precondition(abs(state.requestedHeight - state.fullRect.maxY - 16) < 1, "Full-card action must retain only the 16pt bottom clearance")
        state.showsWideResult = true
        state.hostWindowSize.width = 704
        window.setContentSize(NSSize(width: 704, height: 720))
        pump()
        precondition(abs(state.wideRect.minX - 32) < 1 && abs(state.wideRect.minY - 76) < 1, "Result content must retain its 16pt inner horizontal margin")
        precondition(abs(state.wideRect.width - 640) < 1, "Result table must fit without horizontal clipping")
        state.showsWideResult = false
        state.hostWindowSize.width = 540
        window.setContentSize(NSSize(width: 540, height: 720))
        pump()
        precondition(abs(state.fullRect.width - 508) < 1, "Starting again must restore compact content width")
        state.usesFullCard = false
        state.showsLargeResult = true
        state.maximumContentHeight = 300
        pump()
        precondition(abs(state.requestedHeight - 300) < 1, "Small screens must limit the entire detail page and scroll the content")
        state.pinsInput = true
        pump()
        let pinnedInput = state.inputRect
        guard let root = window.contentView, let scrollView = findScrollView(in: root),
              let scroller = scrollView.verticalScroller else { fatalError("Missing native detail scroller") }
        precondition(scrollView.scrollerStyle == .overlay, "Native scroller must overlay rather than consume content width")
        precondition(abs(scrollView.bounds.width - 540) < 1, "Scroll viewport must span the entire page width")
        precondition(abs(scrollView.contentView.frame.width - 540) < 1, "Scrollbar must not narrow the content viewport")
        precondition(abs(scroller.frame.maxX - scrollView.bounds.maxX) < 1, "Scrollbar must sit on the far right page edge")
        let nativeWidth = NSScroller.scrollerWidth(for: scroller.controlSize, scrollerStyle: .overlay)
        precondition(abs(scroller.frame.width - nativeWidth) < 1, "AppKit must own the scrollbar width")
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pump()
        precondition(scrollView.contentView.bounds.minY > 0, "Result area must scroll")
        precondition(abs(state.inputRect.minY - pinnedInput.minY) < 1, "IP input must stay fixed while results scroll")
        precondition(abs(state.requestedHeight - 300) < 1, "Pinned input and header must be included in the same total height limit")
        precondition(window.attachedSheet == nil, "Tools must render inside the existing popover, without a sheet")
        print("Inline tool sizing checks passed: compact=\(initialHeight), error=\(errorHeight), limited=\(state.requestedHeight)")
        window.orderOut(nil)
    }
    static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScrollView(in: child) { return scroll }
        }
        return nil
    }
    static func pump() {
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
}
