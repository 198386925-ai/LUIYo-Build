import UIKit

/// How UIKit should paint a card surface reported by the HTML.
enum CardMaterialMode {
    /// iOS 26+: Liquid Glass; older systems fall back to system blur.
    case liquid
    case blur
}

/// Renders the material behind HTML cards.
///
/// The bundled page publishes document-space rectangles plus a small spec for
/// every surface; this layer mirrors them with UIKit effect views inside the
/// same scrolling coordinate space, so both move together with momentum and
/// rubber-banding. The HTML never paints blur or glass itself.
final class CardMaterialLayer {
    private weak var scrollView: UIScrollView?
    private let container = UIView()

    private var surfaces: [String: UIVisualEffectView] = [:]
    private var hosts: [String: UIView] = [:]
    private var frames: [String: CGRect] = [:]
    private var specs: [String: [String: Any]] = [:]
    private var order: [String] = []
    private var symbols: [String: UIImageView] = [:]
    private var segments: [String: UISegmentedControl] = [:]
    private var selectedPills: [String: UIView] = [:]
    private var licenseButtons: [String: UIButton] = [:]
    private var glassButtons: [String: UIButton] = [:]
    private var toggles: [String: UIControl] = [:]
    private var segmentStyles: [String: UIUserInterfaceStyle] = [:]

    // MARK: - Inputs owned by the shell

    var materialMode: CardMaterialMode = .liquid
    var tintColor: UIColor = .secondarySystemGroupedBackground
    var themeFont: UIFont?
    var interfaceStyle: UIUserInterfaceStyle = .unspecified
    /// A native toggle was flipped; the shell forwards it to the page.
    var onToggleChanged: ((String, Bool) -> Void)?

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.accessibilityElementsHidden = true
        scrollView.insertSubview(container, at: 0)
    }

    // MARK: - Read-only access for diagnostics

    var allSpecs: [String: [String: Any]] { specs }
    var allSegments: [String: UISegmentedControl] { segments }
    var allSelectedPills: [String: UIView] { selectedPills }

    func surface(forKey key: String) -> UIVisualEffectView? { surfaces[key] }
    func spec(forKey key: String) -> [String: Any]? { specs[key] }

    var containsHomeControl: Bool { specs.values.contains { ($0["homeControl"] as? Bool) == true } }
    var nodeSpecCount: Int { specs.values.filter { ($0["key"] as? String)?.hasPrefix("node:") == true }.count }
    var homeControlCount: Int { specs.values.filter { ($0["homeControl"] as? Bool) == true }.count }

    // MARK: - Rect sync

    func updateRects(_ rects: [[String: Any]]) {
        var nextFrames: [String: CGRect] = [:]
        var nextSpecs: [String: [String: Any]] = [:]
        var nextOrder: [String] = []
        for (index, item) in rects.enumerated() {
            let key = (item["key"] as? String) ?? "legacy:\(index)"
            let x = (item["x"] as? NSNumber)?.doubleValue ?? 0
            let y = (item["y"] as? NSNumber)?.doubleValue ?? 0
            let width = (item["width"] as? NSNumber)?.doubleValue ?? 0
            let height = (item["height"] as? NSNumber)?.doubleValue ?? 0
            guard x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else { continue }
            // Incoming coordinates are DOCUMENT coordinates, never viewport ones.
            nextFrames[key] = CGRect(x: x, y: y, width: width, height: height)
            nextSpecs[key] = item
            nextOrder.append(key)
        }
        for key in Array(surfaces.keys) where nextFrames[key] == nil { discard(key) }
        frames = nextFrames
        specs = nextSpecs
        order = nextOrder
        render()
    }

    /// Drops every host so the next rect sync rebuilds a clean layer stack.
    func clear() {
        for key in Array(surfaces.keys) { discard(key) }
        frames.removeAll()
        specs.removeAll()
        order.removeAll()
    }

    private func discard(_ key: String) {
        surfaces.removeValue(forKey: key)?.removeFromSuperview()
        hosts.removeValue(forKey: key)?.removeFromSuperview()
        symbols.removeValue(forKey: key)?.removeFromSuperview()
        segments.removeValue(forKey: key)
        licenseButtons.removeValue(forKey: key)?.removeFromSuperview()
        glassButtons.removeValue(forKey: key)?.removeFromSuperview()
        selectedPills.removeValue(forKey: key)?.removeFromSuperview()
        toggles.removeValue(forKey: key)?.removeFromSuperview()
        segmentStyles.removeValue(forKey: key)
    }

    // MARK: - Rendering

    func render() {
        guard let scroll = scrollView else { return }
        // This pass only manages visibility. It never moves a card with an
        // asynchronously sampled scroll offset.
        container.frame = CGRect(
            origin: .zero,
            size: CGSize(width: max(scroll.contentSize.width, scroll.bounds.width),
                         height: max(scroll.contentSize.height, scroll.bounds.height))
        )
        let visible = scroll.bounds.insetBy(dx: 0, dy: -scroll.bounds.height)
        UIView.performWithoutAnimation {
            for key in order {
                guard let frame = frames[key], let spec = specs[key] else { continue }
                let clip = CGRect(
                    x: (spec["clipX"] as? NSNumber)?.doubleValue ?? Double(frame.minX),
                    y: (spec["clipY"] as? NSNumber)?.doubleValue ?? Double(frame.minY),
                    width: (spec["clipWidth"] as? NSNumber)?.doubleValue ?? Double(frame.width),
                    height: (spec["clipHeight"] as? NSNumber)?.doubleValue ?? Double(frame.height)
                ).intersection(frame)
                guard !clip.isNull, clip.width > 0, clip.height > 0, clip.intersects(visible) else {
                    hosts[key]?.isHidden = true
                    continue
                }
                let surface: UIVisualEffectView
                if let existing = surfaces[key] {
                    surface = existing
                } else {
                    surface = UIVisualEffectView(effect: effect(for: spec))
                    surface.isUserInteractionEnabled = false
                    surface.clipsToBounds = true
                    let host = UIView()
                    host.isUserInteractionEnabled = false
                    host.clipsToBounds = true
                    container.addSubview(host)
                    host.addSubview(surface)
                    hosts[key] = host
                    surfaces[key] = surface
                }
                hosts[key]?.isHidden = false
                hosts[key]?.frame = clip
                // Clip only animated fold overflow; let UIKit render the glass edge.
                let cropped = clip.minX > frame.minX + 0.5 || clip.minY > frame.minY + 0.5
                    || clip.maxX < frame.maxX - 0.5 || clip.maxY < frame.maxY - 0.5
                surface.frame = CGRect(x: frame.minX - clip.minX, y: frame.minY - clip.minY,
                                       width: frame.width, height: frame.height)
                let requested = CGFloat((spec["radius"] as? NSNumber)?.doubleValue ?? 24)
                // CSS uses 999px for pills; CALayer needs the actual finite radius.
                surface.layer.cornerRadius = min(max(0, requested), min(frame.width, frame.height) / 2)
                if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
                    surface.cornerConfiguration = .uniformCorners(radius: .fixed(Double(surface.layer.cornerRadius)))
                    surface.clipsToBounds = false
                } else {
                    surface.clipsToBounds = true
                }
                hosts[key]?.clipsToBounds = cropped
                hosts[key]?.layer.cornerRadius = 0
                applyTint(to: surface, spec: spec)
                configureSymbol(in: surface, key: key, spec: spec)
                if spec["ruleSurface"] as? Bool == true, let host = hosts[key] {
                    host.layer.cornerRadius = cropped ? 0 : surface.layer.cornerRadius
                    host.clipsToBounds = true
                }
                if spec["licenseButton"] as? Bool == true { configureLicenseButton(in: surface, key: key, spec: spec) }
                if spec["glassButton"] as? Bool == true { configureGlassButton(in: surface, key: key, spec: spec) }
                removeExtraLayerShadows(surface.layer)
                if let host = hosts[key] { removeExtraLayerShadows(host.layer) }
                configureSegment(in: surface, key: key, spec: spec)
            }
        }
    }

    /// Re-applies the effect after a material-mode switch.
    func refreshEffects() {
        UIView.performWithoutAnimation {
            for (key, surface) in surfaces {
                let spec = specs[key] ?? [:]
                // Buttons draw their own glass via UIButton.Configuration; a
                // stacked surface effect would double the material.
                if (spec["glassButton"] as? Bool) == true || (spec["licenseButton"] as? Bool) == true { continue }
                surface.effect = effect(for: spec)
            }
            refreshTint()
        }
    }

    func refreshTint() {
        for (key, surface) in surfaces { applyTint(to: surface, spec: specs[key] ?? [:]) }
    }

    private func effect(for spec: [String: Any]) -> UIVisualEffect {
        if (spec["forceLiquid"] as? Bool) == true, #available(iOS 26.0, *) { return UIGlassEffect() }
        switch materialMode {
        case .liquid:
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect(style: .regular)
                let hex = tintColor.nativeHex.uppercased()
                if !["#FFFFFF", "#1C1C1E"].contains(hex) { glass.tintColor = tintColor.withAlphaComponent(0.12) }
                return glass
            }
            return UIBlurEffect(style: .systemMaterial)
        case .blur:
            return UIBlurEffect(style: .systemMaterial)
        }
    }

    private func applyTint(to surface: UIVisualEffectView, spec: [String: Any]) {
        // Glass supplies its own fill/refraction. A painted fill conceals it.
        if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
            surface.contentView.backgroundColor = .clear
        } else {
            surface.contentView.backgroundColor = tintColor.withAlphaComponent(0.24)
        }
    }

    // MARK: - Sub-controls

    private func configureSymbol(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        guard let name = spec["systemIcon"] as? String, !name.isEmpty else {
            symbols.removeValue(forKey: key)?.removeFromSuperview()
            return
        }
        let icon: UIImageView
        if let existing = symbols[key] {
            icon = existing
        } else {
            icon = UIImageView()
            icon.isUserInteractionEnabled = false
            icon.isAccessibilityElement = false
            icon.contentMode = .scaleAspectFit
            surface.contentView.addSubview(icon)
            symbols[key] = icon
        }
        if name.hasPrefix("icon-"),
           let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Web"),
           let custom = UIImage(contentsOfFile: url.path) {
            icon.image = custom.withRenderingMode(.alwaysOriginal)
            icon.tintColor = nil
        } else {
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
            icon.tintColor = .label
        }
        let x = CGFloat((spec["iconX"] as? NSNumber)?.doubleValue ?? 0)
        let y = CGFloat((spec["iconY"] as? NSNumber)?.doubleValue ?? 0)
        let width = CGFloat((spec["iconWidth"] as? NSNumber)?.doubleValue ?? 28)
        let height = CGFloat((spec["iconHeight"] as? NSNumber)?.doubleValue ?? 28)
        icon.frame = CGRect(x: x + (width - 20) / 2, y: y + (height - 20) / 2, width: 20, height: 20)
    }

    private func configureSegment(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        guard let kind = spec["segment"] as? String else { return }
        let titles = kind == "category" ? ["原版微信", "LiquidUI"]
            : (kind == "appearance" ? ["跟随系统", "浅色", "深色"]
                : kind == "search" ? ["关闭", "合并", "分开"] : ["液态玻璃", "原生磨砂"])
        let segment: UISegmentedControl
        if let existing = segments[key] {
            segment = existing
        } else {
            segment = UISegmentedControl(items: titles)
            // WebKit retains the transparent hit targets, file import handlers,
            // accessibility labels and scrolling gestures. UIKit draws the control.
            segment.isUserInteractionEnabled = false
            segment.selectedSegmentTintColor = .secondarySystemGroupedBackground
            let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            segment.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .normal)
            segment.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .selected)
            let pill = UIView()
            pill.isUserInteractionEnabled = false
            pill.accessibilityElementsHidden = true
            surface.contentView.addSubview(pill)
            selectedPills[key] = pill
            surface.contentView.addSubview(segment)
            segments[key] = segment
        }
        segment.backgroundColor = .clear
        // All pickers share one translucent track and selected capsule.
        // Clear the built-in background so UIKit doesn't stack a darker pill.
        if segmentStyles[key] != interfaceStyle {
            let clear = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
            segment.setBackgroundImage(clear, for: .normal, barMetrics: .default)
            segment.setBackgroundImage(clear, for: .selected, barMetrics: .default)
            segment.setBackgroundImage(clear, for: [.selected, .highlighted], barMetrics: .default)
            segment.setDividerImage(clear, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
            segmentStyles[key] = interfaceStyle
        }
        let selectedColor = UIColor.white
        segment.selectedSegmentTintColor = .clear
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let font = themeFont?.withSize(12) ?? UIFont.systemFont(ofSize: 12, weight: .semibold)
        segment.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.label], for: .normal)
        selectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let selectedText = red * 0.2126 + green * 0.7152 + blue * 0.0722 > 0.5
            ? UIColor(red: 32.0 / 255, green: 40.0 / 255, blue: 50.0 / 255, alpha: 1)
            : UIColor(red: 242.0 / 255, green: 242.0 / 255, blue: 247.0 / 255, alpha: 1)
        segment.setTitleTextAttributes([.font: font, .foregroundColor: selectedText], for: .selected)
        segment.frame = surface.bounds
        segment.layer.cornerRadius = surface.bounds.height / 2
        segment.clipsToBounds = true
        let selected = (spec["selected"] as? NSNumber)?.intValue ?? 0
        if segment.selectedSegmentIndex != selected { segment.selectedSegmentIndex = selected }
        guard let pill = selectedPills[key], surface.bounds.width > 4, surface.bounds.height > 4 else { return }
        let track = surface.bounds.insetBy(dx: 2, dy: 2)
        let width = track.width / CGFloat(segment.numberOfSegments)
        UIView.performWithoutAnimation {
            pill.frame = CGRect(x: track.minX + CGFloat(selected) * width, y: track.minY,
                                width: width, height: track.height)
            pill.backgroundColor = selectedColor
            pill.layer.cornerRadius = track.height / 2
            pill.layer.cornerCurve = .continuous
            pill.layer.borderWidth = 0
            pill.layer.shadowColor = UIColor.black.cgColor
            pill.layer.shadowOpacity = kind == "category" ? 0.065 : 0
            pill.layer.shadowRadius = 1
            pill.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        }
    }

    private func configureLicenseButton(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        let button = licenseButtons[key] ?? UIButton(type: .system)
        if licenseButtons[key] == nil {
            button.isUserInteractionEnabled = false
            button.accessibilityElementsHidden = true
            surface.contentView.addSubview(button)
            licenseButtons[key] = button
        }
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *), materialMode == .liquid {
            configuration = .prominentGlass()
        } else {
            configuration = .plain()
            configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
        }
        configuration.title = spec["licenseTitle"] as? String ?? "激活"
        configuration.baseBackgroundColor = UIColor(nativeHex: "#6968E8")
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        let font = themeFont?.withSize(13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = font
            return result
        }
        button.configuration = configuration
        button.tintColor = UIColor(nativeHex: "#6968E8")
        var btnFrame = surface.bounds
        // Ensure minimum width for horizontal text (prevent vertical wrapping)
        if btnFrame.width < 44 {
            btnFrame.size.width = 44
        }
        button.frame = btnFrame
        surface.effect = nil
        surface.contentView.backgroundColor = .clear
        surface.clipsToBounds = false
    }

    /// Draws the theme row action buttons (恢复 / 导入字体) with the system
    /// Liquid Glass material on iOS 26+. WebKit keeps the transparent hit
    /// target and its tap handlers; UIKit paints the capsule and its label.
    private func configureGlassButton(in surface: UIVisualEffectView, key: String, spec: [String: Any]) {
        let button = glassButtons[key] ?? UIButton(type: .system)
        if glassButtons[key] == nil {
            button.isUserInteractionEnabled = false
            button.accessibilityElementsHidden = true
            surface.contentView.addSubview(button)
            glassButtons[key] = button
        }
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .plain()
            configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
            configuration.background.backgroundColor = tintColor.withAlphaComponent(0.24)
        }
        configuration.title = spec["buttonTitle"] as? String ?? "恢复"
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .capsule
        // Prevent vertical text wrapping: single line, clip, small insets
        configuration.titleLineBreakMode = .byClipping
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        let font = themeFont?.withSize(10) ?? UIFont.systemFont(ofSize: 10, weight: .semibold)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = font
            return result
        }
        button.configuration = configuration
        button.frame = surface.bounds
        surface.effect = nil
        surface.contentView.backgroundColor = .clear
        surface.clipsToBounds = false
    }

    // MARK: - Native theme toggles

    /// Positions the theme switches the HTML declares (custom colours, bar
    /// shrink). The control is a stock UISwitch; the page's own checkbox stays
    /// invisible and only forwards layout.
    func updateToggles(_ rows: [[String: Any]]) {
        var visible = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, row["visible"] as? Bool == true else { continue }
            visible.insert(id)
            let control: UIControl
            if let existing = toggles[id] {
                control = existing
            } else {
                let nativeSwitch = UISwitch(frame: CGRect(x: 0, y: 0, width: 51, height: 31))
                nativeSwitch.addAction(UIAction { [weak self] _ in
                    self?.onToggleChanged?(id, nativeSwitch.isOn)
                }, for: .valueChanged)
                control = nativeSwitch
                toggles[id] = control
                scrollView?.addSubview(control)
            }
            control.isHidden = false
            control.isEnabled = !(row["disabled"] as? Bool ?? false)
            control.accessibilityLabel = id == "minimizeBottomBar" ? "滚动时缩小底栏" : "启用自定义颜色"
            let rowFrame = CGRect(x: (row["x"] as? NSNumber)?.doubleValue ?? 0,
                                  y: (row["y"] as? NSNumber)?.doubleValue ?? 0,
                                  width: 44, height: 26)
            if let nativeSwitch = control as? UISwitch {
                nativeSwitch.setOn(row["on"] as? Bool ?? false, animated: false)
                // Center the stock 51x31 switch on the checkbox rect the page reports.
                // Shift left slightly for visual balance (user feedback).
                nativeSwitch.frame = CGRect(
                    x: rowFrame.midX - nativeSwitch.bounds.width / 2 - 12,
                    y: rowFrame.midY - nativeSwitch.bounds.height / 2,
                    width: nativeSwitch.bounds.width,
                    height: nativeSwitch.bounds.height)
            } else {
                control.frame = rowFrame
                LUIYoSetThemeSwitch(control, row["on"] as? Bool ?? false)
            }
        }
        for (id, control) in toggles where !visible.contains(id) { control.isHidden = true }
    }

    func hideAllToggles() {
        for control in toggles.values { control.isHidden = true }
    }
}
