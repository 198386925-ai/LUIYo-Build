import SwiftUI
import UIKit

/// Registers the actual SwiftUI UIScrollView with the native tab controller so
/// the floating tab bar can minimize while the homepage scrolls.
struct NativeHomeScrollLink: UIViewRepresentable {
    var onAttach: (UIScrollView) -> Void

    func makeUIView(context: Context) -> NativeScrollProbe {
        let view = NativeScrollProbe()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.onAttach = onAttach
        return view
    }

    func updateUIView(_ view: NativeScrollProbe, context: Context) {
        view.onAttach = onAttach
        view.setNeedsLayout()
    }
}

final class NativeScrollProbe: UIView {
    var onAttach: ((UIScrollView) -> Void)?
    private weak var reported: UIScrollView?

    override func didMoveToWindow() { super.didMoveToWindow(); discover() }
    override func layoutSubviews() { super.layoutSubviews(); discover() }

    private func discover() {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                if reported !== scroll {
                    reported = scroll
                    DispatchQueue.main.async { [weak self, weak scroll] in
                        if let scroll { self?.onAttach?(scroll) }
                    }
                }
                return
            }
            ancestor = view.superview
        }
    }
}
