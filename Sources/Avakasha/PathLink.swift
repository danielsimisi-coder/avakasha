import Cocoa

/// A path shown as a quiet link: always underlined, accent colour and hand cursor on hover or keyboard focus, click, Return, Space
/// or a VoiceOver press reveals it in Finder.
final class PathLink: NSTextField {
    var onOpen: (() -> Void)?
    var onCopy: (() -> Void)?
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
    override func menu(for event: NSEvent) -> NSMenu? {
        guard !stringValue.isEmpty else { return nil }
        let menu = NSMenu()
        let copy = NSMenuItem(title: L("Copy path", "העתק נתיב"), action: #selector(copyPath), keyEquivalent: ""); copy.target = self; menu.addItem(copy)
        let open = NSMenuItem(title: L("Show in Finder", "הצג ב־Finder"), action: #selector(openPath), keyEquivalent: ""); open.target = self; menu.addItem(open)
        return menu
    }
    @objc private func copyPath() { onCopy?() }
    @objc private func openPath() { onOpen?() }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)), !stringValue.isEmpty { onOpen?() } else { super.mouseUp(with: event) }
    }
    // Keyboard and assistive access: the link takes focus with Tab, shows a focus ring, and opens on Return or Space.
    override var acceptsFirstResponder: Bool { !stringValue.isEmpty }
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); if ok { setHovered(true) }; return ok }
    override func resignFirstResponder() -> Bool { let ok = super.resignFirstResponder(); if ok { setHovered(false) }; return ok }
    override func drawFocusRingMask() { bounds.fill() }
    override var focusRingMaskBounds: NSRect { bounds }
    override func keyDown(with event: NSEvent) { if event.keyCode == 36 || event.keyCode == 49 { onOpen?() } else { super.keyDown(with: event) } }
    override func accessibilityPerformPress() -> Bool { guard !stringValue.isEmpty else { return false }; onOpen?(); return true }
    func setHovered(_ on: Bool) {
        hovered = on && !stringValue.isEmpty
        render()
        window?.invalidateCursorRects(for: self)
    }
    /// Underlined whenever there is a path; the colour changes on hover or focus, so the affordance never disappears.
    private func render() {
        let active = hovered || window?.firstResponder === self
        attributedStringValue = NSAttributedString(string: stringValue, attributes: [.font: font ?? .systemFont(ofSize: 11), .foregroundColor: active ? NSColor.controlAccentColor : NSColor.secondaryLabelColor, .underlineStyle: stringValue.isEmpty ? 0 : NSUnderlineStyle.single.rawValue])
    }
    var isUnderlined: Bool { (attributedStringValue.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0 }
    var isAccented: Bool { (attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == NSColor.controlAccentColor }
    override var stringValue: String { didSet { render(); window?.invalidateCursorRects(for: self) } }
}
