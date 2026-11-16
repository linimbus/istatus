import AppKit

/// A self-drawn status item view that renders every enabled module in one item.
///
/// `NSStatusBarButton` lets the system override custom title colors, which makes
/// user-selected colors unreliable. Drawing everything ourselves guarantees that
/// the chosen color is used in every menu bar state, and lets the item keep a
/// fixed width while numbers change.
///
/// Each module is a segment with its own icon/letter, value and warning color.
/// The icon/letter slot can be placed above, below, left or right of the value.
final class StatusItemView: NSView {
    struct Segment {
        let symbolName: String?
        let letter: String?
        let value: String
        let tint: NSColor
        let accessibilityLabel: String
    }

    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private let valueFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
    private let letterFont = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
    private let mainPointSize: CGFloat = 13
    private let modulePointSize: CGFloat = 8

    private let outerPadding: CGFloat = 4
    private let segmentGap: CGFloat = 7
    private let inlineGap: CGFloat = 2.5
    private let verticalGap: CGFloat = 0.5

    private var segments: [Segment] = []
    private var iconPosition: MenuBarIconPosition = .top
    private var mainIconVisible = true
    private var mainTint: NSColor = .labelColor
    private var isPressed = false
    private var lastSignature = ""
    private var cachedSymbols: [String: NSImage] = [:]

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAccessibility()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("iStatus 系统状态")
    }

    // MARK: - Update

    func update(
        segments: [Segment],
        iconPosition: MenuBarIconPosition,
        mainIconVisible: Bool,
        mainTint: NSColor,
        tooltip: String
    ) {
        let signature = segments
            .map { "\($0.symbolName ?? "")|\($0.letter ?? "")|\($0.value)|\($0.tint.description)" }
            .joined(separator: ";")
            + "|\(iconPosition.rawValue)|\(mainIconVisible)|\(mainTint.description)"

        let changed = signature != lastSignature
        lastSignature = signature
        self.segments = segments
        self.iconPosition = iconPosition
        self.mainIconVisible = mainIconVisible
        self.mainTint = mainTint

        if self.toolTip != tooltip {
            self.toolTip = tooltip
            setAccessibilityHelp(tooltip)
        }

        let valueText = segments
            .map { "\($0.accessibilityLabel) \($0.value.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "，")
        if (accessibilityValue() as? String) != valueText {
            setAccessibilityValue(valueText)
        }

        if changed {
            needsDisplay = true
        }
    }

    /// Width needed to render every segment without clipping. Values use fixed-width
    /// strings, so this only changes when the user changes modules or layout.
    var preferredWidth: CGFloat {
        guard mainIconVisible || !segments.isEmpty else { return 0 }

        var total = outerPadding * 2
        var hasContent = false

        if mainIconVisible, let image = mainImage() {
            total += image.size.width
            hasContent = true
        }

        for segment in segments {
            if hasContent {
                total += segmentGap
            }
            total += cellWidth(for: segment)
            hasContent = true
        }

        return hasContent ? ceil(total) : 0
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isPressed {
            NSColor.labelColor.withAlphaComponent(0.13).setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 3),
                xRadius: 4,
                yRadius: 4
            ).fill()
        }

        var x = outerPadding
        var hasContent = false

        if mainIconVisible, let image = mainImage() {
            let rect = NSRect(
                x: x,
                y: (bounds.height - image.size.height) / 2,
                width: image.size.width,
                height: image.size.height
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            x += image.size.width
            hasContent = true
        }

        for segment in segments {
            if hasContent {
                x += segmentGap
            }
            let width = cellWidth(for: segment)
            draw(segment, in: NSRect(x: x, y: 0, width: width, height: bounds.height))
            x += width
            hasContent = true
        }
    }

    private func draw(_ segment: Segment, in rect: NSRect) {
        let value = attributedValue(segment)
        let valueSize = value.size()
        let slot = slotContent(for: segment)
        let slotSize = slot?.size ?? .zero

        guard let slot else {
            draw(value, size: valueSize, centeredIn: rect)
            return
        }

        switch iconPosition {
        case .top:
            // Slot above, value below.
            let contentHeight = slotSize.height + verticalGap + valueSize.height
            let y = rect.minY + max(0, (rect.height - contentHeight) / 2)
            draw(
                value,
                size: valueSize,
                at: NSPoint(x: rect.midX - valueSize.width / 2, y: y)
            )
            slot.draw(
                at: NSPoint(
                    x: rect.midX - slotSize.width / 2,
                    y: y + valueSize.height + verticalGap
                )
            )

        case .bottom:
            // Slot below, value above.
            let contentHeight = slotSize.height + verticalGap + valueSize.height
            let y = rect.minY + max(0, (rect.height - contentHeight) / 2)
            slot.draw(
                at: NSPoint(x: rect.midX - slotSize.width / 2, y: y)
            )
            draw(
                value,
                size: valueSize,
                at: NSPoint(
                    x: rect.midX - valueSize.width / 2,
                    y: y + slotSize.height + verticalGap
                )
            )

        case .left:
            let contentWidth = slotSize.width + inlineGap + valueSize.width
            let x = rect.minX + max(0, (rect.width - contentWidth) / 2)
            slot.draw(
                at: NSPoint(
                    x: x,
                    y: rect.midY - slotSize.height / 2
                )
            )
            // The fixed-width value may start with spaces. Shift the box left by
            // that blank width so the visible gap after the icon stays constant.
            let leading = leadingSpaceWidth(of: segment.value, font: valueFont)
            draw(
                value,
                size: valueSize,
                at: NSPoint(
                    x: x + slotSize.width + inlineGap - leading,
                    y: rect.midY - valueSize.height / 2
                )
            )

        case .right:
            let contentWidth = valueSize.width + inlineGap + slotSize.width
            let x = rect.minX + max(0, (rect.width - contentWidth) / 2)
            draw(
                value,
                size: valueSize,
                at: NSPoint(
                    x: x,
                    y: rect.midY - valueSize.height / 2
                )
            )
            slot.draw(
                at: NSPoint(
                    x: x + valueSize.width + inlineGap,
                    y: rect.midY - slotSize.height / 2
                )
            )
        }
    }

    private func draw(_ text: NSAttributedString, size: NSSize, centeredIn rect: NSRect) {
        draw(
            text,
            size: size,
            at: NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2
            )
        )
    }

    private func draw(_ text: NSAttributedString, size: NSSize, at origin: NSPoint) {
        text.draw(
            in: NSRect(
                x: origin.x,
                y: origin.y,
                width: size.width,
                height: size.height
            )
        )
    }

    // MARK: - Layout metrics

    private func cellWidth(for segment: Segment) -> CGFloat {
        let valueWidth = attributedValue(segment).size().width
        guard let slot = slotContent(for: segment) else {
            return valueWidth
        }

        switch iconPosition {
        case .top, .bottom:
            return max(valueWidth, slot.size.width)
        case .left, .right:
            return slot.size.width + inlineGap + valueWidth
        }
    }

    private func attributedValue(_ segment: Segment) -> NSAttributedString {
        NSAttributedString(
            string: segment.value,
            attributes: [
                .font: valueFont,
                .foregroundColor: segment.tint
            ]
        )
    }

    private func leadingSpaceWidth(of string: String, font: NSFont) -> CGFloat {
        var count = 0
        for character in string {
            guard character == " " else { break }
            count += 1
        }
        guard count > 0 else { return 0 }
        return String(repeating: " ", count: count)
            .size(withAttributes: [.font: font])
            .width
    }

    // MARK: - Slot content

    private enum SlotContent {
        case text(NSAttributedString)
        case image(NSImage)

        var size: NSSize {
            switch self {
            case .text(let text): return text.size()
            case .image(let image): return image.size
            }
        }

        func draw(at origin: NSPoint) {
            switch self {
            case .text(let text):
                text.draw(
                    in: NSRect(
                        x: origin.x,
                        y: origin.y,
                        width: text.size().width,
                        height: text.size().height
                    )
                )
            case .image(let image):
                image.draw(
                    in: NSRect(
                        x: origin.x,
                        y: origin.y,
                        width: image.size.width,
                        height: image.size.height
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
        }
    }

    private func slotContent(for segment: Segment) -> SlotContent? {
        if let symbolName = segment.symbolName {
            guard let image = tintedSymbol(
                named: symbolName,
                pointSize: modulePointSize,
                tint: segment.tint
            ) else {
                return nil
            }
            return .image(image)
        }

        if let letter = segment.letter, !letter.isEmpty {
            return .text(
                NSAttributedString(
                    string: letter,
                    attributes: [
                        .font: letterFont,
                        .foregroundColor: segment.tint
                    ]
                )
            )
        }

        return nil
    }

    private func mainImage() -> NSImage? {
        tintedSymbol(
            named: "gauge.with.dots.needle.50percent",
            pointSize: mainPointSize,
            tint: mainTint
        )
    }

    private func tintedSymbol(named name: String, pointSize: CGFloat, tint: NSColor) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(tint.description)"
        if let cached = cachedSymbols[key] {
            return cached
        }

        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            ) else {
            return nil
        }

        let color = tint.usingColorSpace(.sRGB) ?? tint
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        cachedSymbols[key] = tinted
        return tinted
    }

    // MARK: - Interaction

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cachedSymbols.removeAll()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
            return
        }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        needsDisplay = true
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }
}
