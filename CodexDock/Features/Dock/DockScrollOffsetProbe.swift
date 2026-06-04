import SwiftUI

#if os(iOS)
import UIKit
#endif

struct DockScrollOffsetProbe: View {
    var body: some View {
        ZStack {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: DockScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named(DockScrollCoordinateSpace.name)).minY
                    )
            }

            #if os(iOS)
            if PerformanceProbe.isEnabled {
                DockScrollOffsetObserver()
            }
            #endif
        }
        .onPreferenceChange(DockScrollOffsetPreferenceKey.self) { offsetY in
            guard PerformanceProbe.isEnabled else {
                return
            }
            PerformanceProbe.dockSwiftUIScrollOffsetChanged(offsetY: Double(-offsetY))
        }
    }
}

enum DockScrollCoordinateSpace {
    static let name = "dock-scroll"
}

private struct DockScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if os(iOS)
private struct DockScrollOffsetObserver: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = ProbeView(frame: .zero)
        view.coordinator = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(from: uiView)
        }
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            coordinator?.scheduleAttachmentAttempts(from: self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.scheduleAttachmentAttempts(from: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var attachmentAttempts = 0

        deinit {
            observation?.invalidate()
        }

        func scheduleAttachmentAttempts(from view: UIView) {
            attach(from: view)
            for delay in [0.05, 0.2, 0.6, 1.2, 2.5, 5.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                    guard let self, let view else {
                        return
                    }
                    self.attach(from: view)
                }
            }
        }

        func attach(from view: UIView) {
            attachmentAttempts += 1
            guard let scrollView = observedScrollView(for: view),
                  self.scrollView !== scrollView else {
                return
            }
            observation?.invalidate()
            self.scrollView = scrollView
            PerformanceProbe.dockScrollObserverAttached(
                attempt: attachmentAttempts,
                offsetY: Double(scrollView.contentOffset.y),
                contentHeight: Double(scrollView.contentSize.height),
                boundsHeight: Double(scrollView.bounds.height),
                adjustedTopInset: Double(scrollView.adjustedContentInset.top),
                adjustedBottomInset: Double(scrollView.adjustedContentInset.bottom)
            )
            observation = scrollView.observe(\.contentOffset, options: [.new]) { scrollView, _ in
                Task { @MainActor in
                    PerformanceProbe.dockScrollOffsetChanged(
                        offsetY: Double(scrollView.contentOffset.y),
                        contentHeight: Double(scrollView.contentSize.height),
                        boundsHeight: Double(scrollView.bounds.height)
                    )
                }
            }
        }

        private func observedScrollView(for view: UIView) -> UIScrollView? {
            let enclosing = enclosingScrollView(for: view)
            let largestScrollable = view.window.map { window in
                scrollViews(in: window)
                    .filter { isScrollable($0) }
                    .max { lhs, rhs in
                        lhs.contentSize.height < rhs.contentSize.height
                    }
            } ?? nil
            return largestScrollable ?? enclosing
        }

        private func isScrollable(_ scrollView: UIScrollView) -> Bool {
            let scrollableHeight = scrollView.contentSize.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
            return scrollableHeight > 24
        }

        private func enclosingScrollView(for view: UIView) -> UIScrollView? {
            var current = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                current = candidate.superview
            }
            return nil
        }

        private func scrollViews(in view: UIView) -> [UIScrollView] {
            var matches: [UIScrollView] = []
            if let scrollView = view as? UIScrollView {
                matches.append(scrollView)
            }
            for subview in view.subviews {
                matches.append(contentsOf: scrollViews(in: subview))
            }
            return matches
        }
    }
}
#endif
