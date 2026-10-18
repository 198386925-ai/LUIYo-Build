import UIKit

/// Transparent hit-through host for the bottom search overlay.
private final class NativeSearchOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let target = super.hitTest(point, with: event)
        return target === self ? nil : target
    }
}

/// Full-screen search overlay. It keeps the current WebKit page visible and
/// follows the keyboard; the query is applied to the live page underneath.
final class SearchOverlayViewController: UIViewController, UITextFieldDelegate {
    var query = ""
    var placeholder = "搜索"
    var themeFont: UIFont? {
        didSet {
            if isViewLoaded { searchField.font = themeFont?.withSize(16) ?? .systemFont(ofSize: 16) }
        }
    }
    var onSearch: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onLayout: (() -> Void)?
    var backgroundImage: UIImage?

    let searchField = UITextField()

    override func loadView() { view = NativeSearchOverlayView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let effect: UIVisualEffect
        if #available(iOS 26.0, *) { effect = UIGlassEffect() }
        else { effect = UIBlurEffect(style: .systemMaterial) }
        let inputSurface = UIVisualEffectView(effect: effect)
        if #available(iOS 26.0, *) {
            inputSurface.cornerConfiguration = .uniformCorners(radius: .fixed(22))
        } else {
            inputSurface.layer.cornerRadius = 22
            inputSurface.clipsToBounds = true
        }

        searchField.placeholder = placeholder
        searchField.text = query
        searchField.font = themeFont?.withSize(16) ?? .systemFont(ofSize: 16)
        searchField.delegate = self
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.backgroundColor = .clear
        searchField.borderStyle = .none
        searchField.accessibilityIdentifier = "bottomSearchField"
        searchField.enablesReturnKeyAutomatically = false
        searchField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false

        let close = UIButton(type: .system)
        let symbol = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = nil
            configuration.cornerStyle = .capsule
            close.configuration = configuration
        } else {
            close.setImage(nil, for: .normal)
            close.backgroundColor = .tertiarySystemFill
            close.layer.cornerRadius = 22
        }
        let closeIcon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: symbol))
        closeIcon.contentMode = .scaleAspectFit
        closeIcon.tintColor = .label
        closeIcon.isUserInteractionEnabled = false
        closeIcon.isAccessibilityElement = false
        closeIcon.translatesAutoresizingMaskIntoConstraints = false
        close.addSubview(closeIcon)
        close.tintColor = .label
        close.accessibilityIdentifier = "bottomSearchClose"
        close.accessibilityLabel = "关闭搜索"
        close.addAction(UIAction { [weak self] _ in self?.closeSearch() }, for: .touchUpInside)

        for control in [inputSurface, close] {
            control.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(control)
        }
        for control in [icon, searchField] {
            control.translatesAutoresizingMaskIntoConstraints = false
            inputSurface.contentView.addSubview(control)
        }

        let keyboardBottom = inputSurface.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        keyboardBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            keyboardBottom,
            inputSurface.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            inputSurface.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            inputSurface.heightAnchor.constraint(equalToConstant: 44),
            close.leadingAnchor.constraint(equalTo: inputSurface.trailingAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            close.centerYAnchor.constraint(equalTo: inputSurface.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            closeIcon.widthAnchor.constraint(equalToConstant: 20),
            closeIcon.heightAnchor.constraint(equalToConstant: 20),
            closeIcon.centerXAnchor.constraint(equalTo: close.centerXAnchor),
            closeIcon.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: inputSurface.contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: inputSurface.contentView.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchField.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { closeSearch() }
    }

    private func closeSearch() {
        searchField.resignFirstResponder()
        let completion = onClose
        onClose = nil
        completion?()
    }

    @objc private func queryChanged() { onSearch?(searchField.text ?? "") }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSearch?(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
