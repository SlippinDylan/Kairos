//
//  View+ScrollView.swift
//  Kairos
//
//  Created by SlippinDylan on 2026/01/07.
//  SwiftUI scroll view with AppKit overlay-scroller configuration
//

import SwiftUI
import AppKit

/// A SwiftUI scroll view that always uses AppKit overlay scrollers.
///
/// Keeping SwiftUI's `ScrollView` as the layout container lets it participate
/// in window safe-area layout. The background configurator only adjusts the
/// enclosing `NSScrollView`, preventing legacy scrollers from shifting content.
///
/// Usage:
/// ```swift
/// KairosScrollView {
///     VStack(alignment: .leading, spacing: 24) {
///         // Content
///     }
///     .padding()
/// }
/// ```
struct KairosScrollView<Content: View>: View {
    private let showsVerticalScroller: Bool
    private let showsHorizontalScroller: Bool
    private let content: Content

    init(
        showsVerticalScroller: Bool = true,
        showsHorizontalScroller: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.showsVerticalScroller = showsVerticalScroller
        self.showsHorizontalScroller = showsHorizontalScroller
        self.content = content()
    }

    private var axes: Axis.Set {
        var axes: Axis.Set = []
        if showsVerticalScroller {
            axes.insert(.vertical)
        }
        if showsHorizontalScroller {
            axes.insert(.horizontal)
        }
        return axes
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsVerticalScroller || showsHorizontalScroller) {
            content
                .frame(
                    maxWidth: showsVerticalScroller ? .infinity : nil,
                    maxHeight: showsHorizontalScroller ? .infinity : nil
                )
        }
        .background {
            OverlayScrollerConfigurator(
                showsVerticalScroller: showsVerticalScroller,
                showsHorizontalScroller: showsHorizontalScroller
            )
        }
    }
}

private struct OverlayScrollerConfigurator: NSViewRepresentable {
    let showsVerticalScroller: Bool
    let showsHorizontalScroller: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureEnclosingScrollView(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureEnclosingScrollView(from: nsView)
    }

    private func configureEnclosingScrollView(from view: NSView) {
        DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }

            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = showsVerticalScroller
            scrollView.hasHorizontalScroller = showsHorizontalScroller
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.verticalScrollElasticity = .automatic
            scrollView.horizontalScrollElasticity = .automatic
            scrollView.usesPredominantAxisScrolling = false
        }
    }
}
