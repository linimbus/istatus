import AppKit
import CoreText

/// A self-drawn status item view that renders every enabled module in one item.
///
/// `NSStatusBarButton` lets the system override custom title colors, which makes
/// user-selected colors unreliable. Drawing everything ourselves guarantees that
/// the chosen color is used in every menu bar state, and lets the item keep a
/// fixed width while numbers change.
///
/// Each module is a segment with its own icon/letter, value and warning color.
/// The icon/letter slot can be placed above, below, left or right of the value.
///
/// A status item is 22 pt tall, but the menu bar window is taller (24–30 pt) and
/// the item is vertically centered inside it. Drawing into that extra space lets
/// large text and icons use the full menu bar height instead of being clipped at
/// the item's bounds.
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

    private let mainSymbolName = "gauge.with.dots.needle.50percent"

    private var valueFontSize: CGFloat = 9
    private var iconPointSize: CGFloat = 8
    private var mainPointSize: CGFloat = 13
    private var effectiveMainPointSize: CGFloat = 13
    private var effectiveIconPointSize: CGFloat = 8
    private var effectiveLetterFontSize: CGFloat = 8.5
    private var valueGlyphHeight: CGFloat = 7

    private var valueFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: valueFontSize, weight: .medium)
    }

    private var letterFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: effectiveLetterFontSize, weight: .medium)
    }

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
    private var lastSizingSignature = ""
    private var cachedSymbols: [String: NSImage] = [:]
    private var inkHeightCache: [String: CGFloat] = [:]

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

    // MARK: - Layout geometry

    /// The status bar window is taller than the item view. Fall back to the view
    /// height while the item is not attached to its window yet (offscreen tests).
    private var layoutHeight: CGFloat {
        if let height = window?.frame.height, height > bounds.height + 0.5 {
            return height
        }
        return bounds.height
    }

    private var verticalPadding: CGFloat {
        max(0, (layoutHeight - bounds.height) / 2)
    }

    /// The full drawing band, including the menu bar space above and below the
    /// item's own bounds.
    private var contentBand: NSRect {
        NSRect(
            x: 0,
            y: -verticalPadding,
            width: bounds.width,
            height: layoutHeight
        )
    }

    // MARK: - Update

    func update(
        segments: [Segment],
        iconPosition: MenuBarIconPosition,
        mainIconVisible: Bool,
        mainTint: NSColor,
        fontSize: CGFloat,
        iconSize: CGFloat,
        mainIconSize: CGFloat,
        tooltip: String
    ) {
        let signature = segments
            .map { "\($0.symbolName ?? "")|\($0.letter ?? "")|\($0.value)|\($0.tint.description)" }
            .joined(separator: ";")
            + "|\(iconPosition.rawValue)|\(mainIconVisible)|\(mainTint.description)"
            + "|\(fontSize)|\(iconSize)|\(mainIconSize)"

        let changed = signature != lastSignature
        lastSignature = signature
        self.segments = segments
        self.iconPosition = iconPosition
        self.mainIconVisible = mainIconVisible
        self.mainTint = mainTint
        self.valueFontSize = fontSize
        self.iconPointSize = iconSize
        self.mainPointSize = mainIconSize

        let bandHeight = layoutHeight
        let sizingSignature = "\(iconPosition.rawValue)|\(fontSize)|\(iconSize)|\(mainIconSize)|\(mainIconVisible)|\(bandHeight)|"
            + segments.map { "\($0.symbolName ?? "")|\($0.letter ?? "")" }.joined(separator: ";")
        let sizingChanged = sizingSignature != lastSizingSignature
        if sizingChanged {
            lastSizingSignature = sizingSignature
            valueGlyphHeight = Self.glyphHeight(
                of: NSAttributedString(
                    string: "↓999M ↑999M",
                    attributes: [.font: valueFont]
                )
            )
            effectiveIconPointSize = fittedIconPointSize(band: bandHeight)
            effectiveLetterFontSize = fittedLetterFontSize(band: bandHeight)
            effectiveMainPointSize = fittedMainPointSize(band: bandHeight)
        }

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

        if changed || sizingChanged {
            needsDisplay = true
        }
    }

    // MARK: - Size fitting

    private func fittedIconPointSize(band: CGFloat) -> CGFloat {
        guard segments.contains(where: { $0.symbolName != nil }) else {
            return iconPointSize
        }

        let available: CGFloat
        switch iconPosition {
        case .top, .bottom:
            available = band - 1 - valueGlyphHeight - verticalGap
        case .left, .right:
            available = band - 1
        }
        guard available > 4 else { return 4 }

        var size = min(iconPointSize, 64)
        while size > 4, maximumSymbolInkHeight(at: size) > available {
            size -= 0.5
        }
        return size
    }

    private func fittedLetterFontSize(band: CGFloat) -> CGFloat {
        let requested = max(6, valueFontSize - 0.5)
        guard segments.contains(where: { ($0.letter ?? "").isEmpty == false }) else {
            return requested
        }

        let available: CGFloat
        switch iconPosition {
        case .top, .bottom:
            available = band - 1 - valueGlyphHeight - verticalGap
        case .left, .right:
            available = band - 1
        }
        guard available > 4 else { return 4 }

        var size = requested
        while size > 4, letterHeight(at: size) > available {
            size -= 0.5
        }
        return size
    }

    private func fittedMainPointSize(band: CGFloat) -> CGFloat {
        guard mainIconVisible else { return mainPointSize }

        var size = min(mainPointSize, 64)
        let available = max(4, band - 1)
        while size > 4, symbolInkHeight(named: mainSymbolName, pointSize: size) > available {
            size -= 0.5
        }
        return size
    }

    private func maximumSymbolInkHeight(at pointSize: CGFloat) -> CGFloat {
        var height: CGFloat = 0
        for segment in segments {
            guard let name = segment.symbolName else { continue }
            height = max(height, symbolInkHeight(named: name, pointSize: pointSize))
        }
        return height
    }

    private func letterHeight(at pointSize: CGFloat) -> CGFloat {
        Self.glyphHeight(
            of: NSAttributedString(
                string: "M",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: pointSize, weight: .medium)
                ]
            )
        )
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

        let band = contentBand
        var x = outerPadding
        var hasContent = false

        if mainIconVisible, let image = mainImage() {
            let rect = NSRect(
                x: x,
                y: band.midY - image.size.height / 2,
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
            draw(segment, in: NSRect(x: x, y: band.minY, width: width, height: band.height))
            x += width
            hasContent = true
        }
    }

    private func draw(_ segment: Segment, in rect: NSRect) {
        let value = attributedValue(segment)
        let lineSize = value.size()
        let slot = slotContent(for: segment)

        guard let slot else {
            draw(
                value,
                size: lineSize,
                at: NSPoint(
                    x: rect.midX - lineSize.width / 2,
                    y: rect.midY - lineSize.height / 2
                )
            )
            return
        }

        switch iconPosition {
        case .top:
            let contentHeight = valueGlyphHeight + verticalGap + slot.layoutHeight
            let y = rect.minY + max(0, (rect.height - contentHeight) / 2)
            draw(
                value,
                size: lineSize,
                at: NSPoint(
                    x: rect.midX - lineSize.width / 2,
                    y: y + valueGlyphHeight / 2 - lineSize.height / 2
                )
            )
            slot.draw(
                centeredAt: NSPoint(
                    x: rect.midX,
                    y: y + valueGlyphHeight + verticalGap + slot.layoutHeight / 2
                )
            )

        case .bottom:
            let contentHeight = valueGlyphHeight + verticalGap + slot.layoutHeight
            let y = rect.minY + max(0, (rect.height - contentHeight) / 2)
            slot.draw(
                centeredAt: NSPoint(x: rect.midX, y: y + slot.layoutHeight / 2)
            )
            draw(
                value,
                size: lineSize,
                at: NSPoint(
                    x: rect.midX - lineSize.width / 2,
                    y: y + slot.layoutHeight + verticalGap + valueGlyphHeight / 2 - lineSize.height / 2
                )
            )

        case .left:
            let slotSize = slot.drawSize
            let contentWidth = slotSize.width + inlineGap + lineSize.width
            let x = rect.minX + max(0, (rect.width - contentWidth) / 2)
            slot.draw(centeredAt: NSPoint(x: x + slotSize.width / 2, y: rect.midY))
            // The fixed-width value may start with spaces. Shift the box left by
            // that blank width so the visible gap after the icon stays constant.
            let leading = leadingSpaceWidth(of: segment.value, font: valueFont)
            draw(
                value,
                size: lineSize,
                at: NSPoint(
                    x: x + slotSize.width + inlineGap - leading,
                    y: rect.midY - lineSize.height / 2
                )
            )

        case .right:
            let slotSize = slot.drawSize
            let contentWidth = lineSize.width + inlineGap + slotSize.width
            let x = rect.minX + max(0, (rect.width - contentWidth) / 2)
            draw(
                value,
                size: lineSize,
                at: NSPoint(x: x, y: rect.midY - lineSize.height / 2)
            )
            slot.draw(
                centeredAt: NSPoint(
                    x: x + lineSize.width + inlineGap + slotSize.width / 2,
                    y: rect.midY
                )
            )
        }
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
            return max(valueWidth, slot.drawSize.width)
        case .left, .right:
            return slot.drawSize.width + inlineGap + valueWidth
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
        case text(NSAttributedString, layoutHeight: CGFloat)
        case image(NSImage, layoutHeight: CGFloat)

        var drawSize: NSSize {
            switch self {
            case .text(let text, _): return text.size()
            case .image(let image, _): return image.size
            }
        }

        var layoutHeight: CGFloat {
            switch self {
            case .text(_, let height): return height
            case .image(_, let height): return height
            }
        }

        func draw(centeredAt center: NSPoint) {
            switch self {
            case .text(let text, _):
                let size = text.size()
                text.draw(
                    in: NSRect(
                        x: center.x - size.width / 2,
                        y: center.y - size.height / 2,
                        width: size.width,
                        height: size.height
                    )
                )
            case .image(let image, _):
                image.draw(
                    in: NSRect(
                        x: center.x - image.size.width / 2,
                        y: center.y - image.size.height / 2,
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
                pointSize: effectiveIconPointSize,
                tint: segment.tint
            ) else {
                return nil
            }
            return .image(
                image,
                layoutHeight: symbolInkHeight(
                    named: symbolName,
                    pointSize: effectiveIconPointSize
                )
            )
        }

        if let letter = segment.letter, !letter.isEmpty {
            let text = NSAttributedString(
                string: letter,
                attributes: [
                    .font: letterFont,
                    .foregroundColor: segment.tint
                ]
            )
            return .text(text, layoutHeight: Self.glyphHeight(of: text))
        }

        return nil
    }

    private func mainImage() -> NSImage? {
        tintedSymbol(
            named: mainSymbolName,
            pointSize: effectiveMainPointSize,
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

    private func symbolInkHeight(named name: String, pointSize: CGFloat) -> CGFloat {
        let key = "\(name)|\(pointSize)"
        if let cached = inkHeightCache[key] {
            return cached
        }

        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            ) else {
            return pointSize
        }

        let ink = Self.inkHeight(of: base)
        inkHeightCache[key] = ink
        return ink
    }

    // MARK: - Metrics helpers

    private static func glyphHeight(of text: NSAttributedString) -> CGFloat {
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.height > 0 ? bounds.height : text.size().height
    }

    private static func inkHeight(of image: NSImage) -> CGFloat {
        let scale: CGFloat = 2
        let width = max(1, Int(ceil(image.size.width * scale)))
        let height = max(1, Int(ceil(image.size.height * scale)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            return image.size.height
        }

        let previousContext = NSGraphicsContext.current
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            NSColor.clear.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.current = previousContext

        guard let data = rep.bitmapData else { return image.size.height }
        var minY = height
        var maxY = -1
        for y in 0..<height {
            let row = y * rep.bytesPerRow
            for x in 0..<width {
                if data[row + x * 4 + 3] > 13 {
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxY >= minY else { return image.size.height }
        return CGFloat(maxY - minY + 1) / scale
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
