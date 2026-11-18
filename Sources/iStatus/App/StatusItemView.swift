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

    /// Fonts are cached and only recreated when the user changes a size. Asking
    /// the system for a new UI font on every draw can return a bad font object
    /// after long uptimes; CoreText then throws "attempt to insert nil object"
    /// while building its attribute dictionary during menu-bar snapshot drawing.
    /// Reusing a descriptor created once also avoids repeated system-font lookups.
    private var valueFont = StatusItemView.monospacedFont(ofSize: 9)
    private var letterFont = StatusItemView.monospacedFont(ofSize: 8.5)

    private let outerPadding: CGFloat = 4
    private let segmentGap: CGFloat = 7
    private let inlineGap: CGFloat = 2.5
    private let verticalGap: CGFloat = 0.5

    private var segments: [Segment] = []
    private var preparedSegments: [PreparedSegment] = []
    private var iconPosition: MenuBarIconPosition = .top
    private var mainIconVisible = true
    private var mainTint: NSColor = .labelColor
    private var isPressed = false
    private var lastSignature = ""
    private var lastSizingSignature = ""
    private var cachedSymbols: [String: NSImage] = [:]
    private var inkHeightCache: [String: CGFloat] = [:]

    private struct TextRun {
        let text: NSAttributedString
        let size: NSSize
        let glyphHeight: CGFloat
    }

    private enum Slot {
        case text(TextRun)
        case image(NSImage, inkHeight: CGFloat)

        var width: CGFloat {
            switch self {
            case .text(let run): return run.size.width
            case .image(let image, _): return image.size.width
            }
        }

        var layoutHeight: CGFloat {
            switch self {
            case .text(let run): return run.glyphHeight
            case .image(_, let inkHeight): return inkHeight
            }
        }
    }

    private struct PreparedSegment {
        let value: TextRun
        let leadingWidth: CGFloat
        let slot: Slot?
        let cellWidth: CGFloat
    }

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
        self.iconPointSize = iconSize
        self.mainPointSize = mainIconSize

        let clampedFontSize = fontSize.isFinite ? min(max(fontSize, 4), 64) : 9
        if abs(valueFontSize - clampedFontSize) > 0.001 {
            valueFontSize = clampedFontSize
            valueFont = Self.monospacedFont(ofSize: clampedFontSize)
        }

        let bandHeight = layoutHeight
        let sizingSignature = "\(iconPosition.rawValue)|\(clampedFontSize)|\(iconSize)|\(mainIconSize)|\(mainIconVisible)|\(bandHeight)|"
            + segments.map { "\($0.symbolName ?? "")|\($0.letter ?? "")" }.joined(separator: ";")
        let sizingChanged = sizingSignature != lastSizingSignature
        if sizingChanged {
            lastSizingSignature = sizingSignature
            valueGlyphHeight = Self.glyphHeight(of: "↓999M ↑999M", font: valueFont)
            effectiveIconPointSize = fittedIconPointSize(band: bandHeight)
            let letterSize = fittedLetterFontSize(band: bandHeight)
            if abs(letterSize - effectiveLetterFontSize) > 0.001 {
                effectiveLetterFontSize = letterSize
                letterFont = Self.monospacedFont(ofSize: letterSize)
            }
            effectiveMainPointSize = fittedMainPointSize(band: bandHeight)
        }

        if changed || sizingChanged {
            rebuildPreparedSegments()
            needsDisplay = true
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
            of: "M",
            font: Self.monospacedFont(ofSize: pointSize)
        )
    }

    // MARK: - Preparing text

    /// Measure all text once while preparing instead of inside draw. AppKit's
    /// delayed status-item snapshot calls draw from `cacheDisplay`; measuring
    /// text there is where CoreText used to throw for a bad font object.
    private func rebuildPreparedSegments() {
        preparedSegments = segments.map { segment in
            let value = makeTextRun(
                segment.value,
                font: valueFont,
                tint: segment.tint
            )
            let slot = makeSlot(for: segment)
            let leadingWidth = CGFloat(Self.leadingSpaceCount(of: segment.value))
                * valueFont.maximumAdvancement.width

            let cellWidth: CGFloat
            if let slot {
                switch iconPosition {
                case .top, .bottom:
                    cellWidth = max(value.size.width, slot.width)
                case .left, .right:
                    cellWidth = slot.width + inlineGap + value.size.width
                }
            } else {
                cellWidth = value.size.width
            }

            return PreparedSegment(
                value: value,
                leadingWidth: leadingWidth,
                slot: slot,
                cellWidth: cellWidth
            )
        }
    }

    private func makeTextRun(_ text: String, font: NSFont, tint: NSColor) -> TextRun {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: tint
            ]
        )
        // Measure once while preparing, not while AppKit is taking its delayed
        // status-item snapshot. That snapshot is where CoreText used to throw.
        let size = attributed.size()
        let glyphHeight = Self.glyphHeight(of: text, font: font)
        return TextRun(text: attributed, size: size, glyphHeight: glyphHeight)
    }

    private func makeSlot(for segment: Segment) -> Slot? {
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
                inkHeight: symbolInkHeight(
                    named: symbolName,
                    pointSize: effectiveIconPointSize
                )
            )
        }

        if let letter = segment.letter, !letter.isEmpty {
            let run = makeTextRun(letter, font: letterFont, tint: segment.tint)
            return .text(run)
        }

        return nil
    }

    private static func leadingSpaceCount(of string: String) -> Int {
        var count = 0
        for character in string {
            guard character == " " else { break }
            count += 1
        }
        return count
    }

    // MARK: - Width

    /// Width needed to render every segment without clipping. Values use fixed-width
    /// strings, so this only changes when the user changes modules or layout.
    var preferredWidth: CGFloat {
        guard mainIconVisible || !preparedSegments.isEmpty else { return 0 }

        var total = outerPadding * 2
        var hasContent = false

        if mainIconVisible, let image = mainImage() {
            total += image.size.width
            hasContent = true
        }

        for prepared in preparedSegments {
            if hasContent {
                total += segmentGap
            }
            total += prepared.cellWidth
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

        for prepared in preparedSegments {
            if hasContent {
                x += segmentGap
            }
            draw(prepared, in: NSRect(x: x, y: band.minY, width: prepared.cellWidth, height: band.height))
            x += prepared.cellWidth
            hasContent = true
        }
    }

    private func draw(_ prepared: PreparedSegment, in rect: NSRect) {
        let value = prepared.value

        guard let slot = prepared.slot else {
            drawRun(value, centeredAtX: rect.midX, centerY: rect.midY)
            return
        }

        switch iconPosition {
        case .top:
            let contentHeight = value.glyphHeight + verticalGap + slot.layoutHeight
            let y = rect.minY + max(0, (rect.height - contentHeight) / 2)
            drawRun(
                value,
                centeredAtX: rect.midX,
                centerY: y + value.glyphHeight / 2
            )
            drawSlot(
                slot,
                centeredAt: NSPoint(
                    x: rect.midX,
                    y: y + value.glyphHeight + verticalGap + slot.layoutHeight / 2
                )
            )

        case .bottom:
            let contentHeight = value.glyphHeight + verticalGap + slot.layoutHeight
            let y = rect.minY + max(0, (rect.height - contentHeight) / 2)
            drawSlot(
                slot,
                centeredAt: NSPoint(x: rect.midX, y: y + slot.layoutHeight / 2)
            )
            drawRun(
                value,
                centeredAtX: rect.midX,
                centerY: y + slot.layoutHeight + verticalGap + value.glyphHeight / 2
            )

        case .left:
            let contentWidth = slot.width + inlineGap + value.size.width
            let x = rect.minX + max(0, (rect.width - contentWidth) / 2)
            drawSlot(
                slot,
                centeredAt: NSPoint(x: x + slot.width / 2, y: rect.midY)
            )
            // Fixed-width values can start with blank cells. Shift the advance
            // origin left by that blank width so the visible gap stays constant.
            drawRun(
                value,
                atX: x + slot.width + inlineGap - prepared.leadingWidth,
                centerY: rect.midY
            )

        case .right:
            let contentWidth = value.size.width + inlineGap + slot.width
            let x = rect.minX + max(0, (rect.width - contentWidth) / 2)
            drawRun(value, atX: x, centerY: rect.midY)
            drawSlot(
                slot,
                centeredAt: NSPoint(
                    x: x + value.size.width + inlineGap + slot.width / 2,
                    y: rect.midY
                )
            )
        }
    }

    private func drawSlot(_ slot: Slot, centeredAt center: NSPoint) {
        switch slot {
        case .text(let run):
            drawRun(run, centeredAtX: center.x, centerY: center.y)
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

    private func drawRun(_ run: TextRun, centeredAtX centerX: CGFloat, centerY: CGFloat) {
        drawRun(run, atX: centerX - run.size.width / 2, centerY: centerY)
    }

    private func drawRun(_ run: TextRun, atX x: CGFloat, centerY: CGFloat) {
        run.text.draw(
            in: NSRect(
                x: x,
                y: centerY - run.size.height / 2,
                width: run.size.width,
                height: run.size.height
            )
        )
    }

    // MARK: - Fonts and symbols

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

    private static let monospacedDescriptor: NSFontDescriptor = {
        NSFont.monospacedSystemFont(ofSize: 9, weight: .medium).fontDescriptor
    }()

    private static func monospacedFont(ofSize size: CGFloat) -> NSFont {
        let clamped = size.isFinite ? min(max(size, 4), 64) : 9
        if let font = NSFont(descriptor: monospacedDescriptor, size: clamped) {
            return font
        }
        // Never build attributed strings with a nil/broken font. Menlo is a
        // stable monospaced fallback; systemFont is the last resort.
        return NSFont(name: "Menlo", size: clamped)
            ?? NSFont.systemFont(ofSize: clamped, weight: .medium)
    }

    private static func glyphHeight(of string: String, font: NSFont) -> CGFloat {
        let attributed = NSAttributedString(
            string: string,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        if bounds.height > 0 {
            return bounds.height
        }
        return font.ascender - font.descender + font.leading
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
        // Do not measure text here: appearance changes can arrive while AppKit is
        // taking a status-item snapshot. The next sampling tick rebuilds with the
        // new tint colors.
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
