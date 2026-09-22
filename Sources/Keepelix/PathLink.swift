import Cocoa

/// A path shown as a quiet link: underline and hand cursor on hover, click reveals it in Finder.
final class PathLink: NSTextField {
    var onOpen: (() -> Void)?
    private(set) var hovered = false
    private var tracking: NSTrackingArea?

    convenience init() {
        self.init(labelWithString: "")
        font = .monospacedSystemFont(ofSize: 11, weight: .regular); textColor = .secondaryLabelColor; lineBreakMode = .byTruncatingMiddle
        setAccessibilityRole(.link)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func resetCursorRects() { if !stringValue.isEmpty { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)), !stringValue.isEmpty { onOpen?() } else { super.mouseUp(with: event) }
    }
    func setHovered(_ on: Bool) {
        hovered = on && !stringValue.isEmpty
        let text = stringValue
        attributedStringValue = NSAttributedString(string: text, attributes: [.font: font ?? .systemFont(ofSize: 11), .foregroundColor: hovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor, .underlineStyle: hovered ? NSUnderlineStyle.single.rawValue : 0])
        window?.invalidateCursorRects(for: self)
    }
    var isUnderlined: Bool { (attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0 }
    override var stringValue: String { didSet { if hovered { setHovered(true) } else { attributedStringValue = NSAttributedString(string: stringValue, attributes: [.font: font ?? .systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]) }; window?.invalidateCursorRects(for: self) } }
}
