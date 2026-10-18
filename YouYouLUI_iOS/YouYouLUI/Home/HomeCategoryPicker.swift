import SwiftUI
import UIKit

struct NativeHomeCategoryPicker: UIViewRepresentable {
    @Binding var selection: Int
    var theme: NativeHomeTheme
    var font: UIFont?
    var useBlur: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> NativeCategoryGlassView {
        let view = NativeCategoryGlassView()
        view.control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return view
    }

    func updateUIView(_ view: NativeCategoryGlassView, context: Context) {
        context.coordinator.parent = self
        view.update(theme: theme, font: font, useBlur: useBlur)
        view.setSelection(selection)
    }

    final class Coordinator: NSObject {
        var parent: NativeHomeCategoryPicker

        init(_ parent: NativeHomeCategoryPicker) { self.parent = parent }

        @objc func changed(_ control: UISegmentedControl) { parent.selection = control.selectedSegmentIndex }
    }
}

/// A solid selected pill sits above native glass; the control stays independently tappable.
final class NativeCategoryGlassView: UIView {
    let material = NativeMaterialView()
    let control = UISegmentedControl(items: ["原版微信", "LiquidUI"])
    private let selectedPill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        material.shapeRadius = -1
        material.isUserInteractionEnabled = false
        material.accessibilityElementsHidden = true
        addSubview(material)
        selectedPill.isUserInteractionEnabled = false
        selectedPill.accessibilityElementsHidden = true
        addSubview(selectedPill)
        // Never put an interactive control inside a noninteractive material view.
        addSubview(control)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(selectionChanged), for: .valueChanged)
        let transparent = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        control.backgroundColor = .clear
        control.setBackgroundImage(transparent, for: .normal, barMetrics: .default)
        control.setBackgroundImage(transparent, for: .selected, barMetrics: .default)
        control.setBackgroundImage(transparent, for: [.selected, .highlighted], barMetrics: .default)
        control.setDividerImage(transparent, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(theme: NativeHomeTheme, font: UIFont?, useBlur: Bool) {
        let signature = "\(useBlur)|\(theme.card)|\(theme.dark)"
        if material.materialSignature != signature {
            material.materialSignature = signature
            let tint = UIColor(nativeHex: theme.card)
            if #available(iOS 26.0, *), !useBlur {
                let effect = UIGlassEffect(style: .regular)
                if !["#FFFFFF", "#1C1C1E"].contains(theme.card.uppercased()) {
                    effect.tintColor = tint.withAlphaComponent(0.12)
                }
                material.effect = effect
                material.contentView.backgroundColor = .clear
            } else {
                material.effect = UIBlurEffect(style: .systemMaterial)
                material.contentView.backgroundColor = tint.withAlphaComponent(0.24)
            }
        }
        control.selectedSegmentTintColor = .clear
        selectedPill.backgroundColor = .white
        selectedPill.layer.borderWidth = 0
        selectedPill.layer.shadowColor = UIColor.black.cgColor
        selectedPill.layer.shadowOpacity = 0.065
        selectedPill.layer.shadowRadius = 1
        selectedPill.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        let textFont = font?.withSize(13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        control.setTitleTextAttributes([.font: textFont, .foregroundColor: UIColor.label], for: .normal)
        control.setTitleTextAttributes([.font: textFont, .foregroundColor: UIColor(nativeHex: "#202832")], for: .selected)
        material.setNeedsLayout()
        setNeedsLayout()
    }

    func setSelection(_ index: Int) {
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
        layoutSelectedPill()
    }

    @objc private func selectionChanged() { layoutSelectedPill() }

    private func layoutSelectedPill() {
        guard bounds.width > 4, bounds.height > 4 else { return }
        let track = bounds.insetBy(dx: 2, dy: 2)
        let width = track.width / CGFloat(control.numberOfSegments)
        let index = max(0, control.selectedSegmentIndex)
        UIView.performWithoutAnimation {
            selectedPill.frame = CGRect(x: track.minX + CGFloat(index) * width, y: track.minY,
                                        width: width, height: track.height)
            selectedPill.layer.cornerRadius = track.height / 2
            selectedPill.layer.cornerCurve = .continuous
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        control.frame = bounds.insetBy(dx: 2, dy: 2)
        layoutSelectedPill()
    }
}
