import AppKit

/// A self-drawn status item view.
///
/// `NSStatusBarButton` lets the system override custom title colors, which makes
/// user-selected colors unreliable. Drawing the icon and text ourselves guarantees
/// that the chosen color is used in every menu bar state, and keeps the item width
/// fixed so changing numbers never shift the menu bar.
final class StatusItemView: NSView {
    var itemTag: Int = 0
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var symbolPointSize: CGFloat = 11 {
        didSet {
            cachedSymbol = nil
            cachedSymbolKey = nil
            needsDisplay = true
        }
    }

    private let valueFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    private let letterFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)

    private var title = NSAttributedString()
    private var symbolName: String?
    private var tint: NSColor = .labelColor
    private var cachedSymbol: NSImage?
    private var cachedSymbolKey: String?
    private var isPressed = false

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func update(
        symbolName: String?,
        prefix: String?,
        value: String,
        tint: NSColor,
        tooltip: String
    ) {
        let newTitle = NSMutableAttributedString()
        if let prefix, !prefix.isEmpty {
            newTitle.append(
                NSAttributedString(
                    string: prefix,
                    attributes: [
                        .font: letterFont,
                        .foregroundColor: tint
                    ]
                )
            )
        }
        newTitle.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: valueFont,
                    .foregroundColor: tint
                ]
            )
        )

        let titleChanged = title.string != newTitle.string
        let tintChanged = !self.tint.isEqual(tint)
        let symbolChanged = self.symbolName != symbolName

        title = newTitle
        self.tint = tint
        self.symbolName = symbolName

        if self.toolTip != tooltip {
            self.toolTip = tooltip
            setAccessibilityHelp(tooltip)
        }

        if titleChanged || tintChanged || symbolChanged {
            if tintChanged || symbolChanged {
                cachedSymbol = nil
                cachedSymbolKey = nil
            }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPressed {
            NSColor.labelColor.withAlphaComponent(0.13).setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 2, dy: 3),
                xRadius: 4,
                yRadius: 4
            ).fill()
        }

        let symbol = symbolImage()
        let iconSide = symbolPointSize + 2
        let iconSize = symbol == nil ? .zero : NSSize(width: iconSide, height: iconSide)
        let titleSize = title.length > 0 ? title.size() : .zero
        let gap: CGFloat = symbol != nil && title.length > 0 ? 3 : 0
        let contentWidth = iconSize.width + gap + titleSize.width
        var x = max(0, (bounds.width - contentWidth) / 2)

        if let symbol {
            let iconRect = NSRect(
                x: x,
                y: (bounds.height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            symbol.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            x += iconSize.width + gap
        }

        if title.length > 0 {
            title.draw(
                in: NSRect(
                    x: x,
                    y: (bounds.height - titleSize.height) / 2,
                    width: titleSize.width,
                    height: titleSize.height
                )
            )
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cachedSymbol = nil
        cachedSymbolKey = nil
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

    private func symbolImage() -> NSImage? {
        guard let symbolName else { return nil }
        let key = "\(symbolName)|\(symbolPointSize)|\(tint.description)"
        if let cachedSymbol, cachedSymbolKey == key {
            return cachedSymbol
        }

        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
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
        cachedSymbol = tinted
        cachedSymbolKey = key
        return tinted
    }
}
