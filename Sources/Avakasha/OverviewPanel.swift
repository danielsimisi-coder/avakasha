import Cocoa
import AvakashaCore

/// One step on the overview's "What can go" card: a Free up space row, its size and verdict.
struct OverviewStep: Equatable { let id: String; let title: String; let bytes: Int64; let safety: CleanupSafety }

/// A whole-row click target: dot, title, size and a chevron; Return or Space activates it with VoiceOver and the keyboard.
final class StepRowView: NSView {
    var onClick: (() -> Void)?
    init(_ step: OverviewStep) {
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: step.title); title.font = Type.body; title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let size = NSTextField(labelWithString: bytes(step.bytes)); size.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); size.textColor = .secondaryLabelColor
        let advice = NSTextField(labelWithString: LocationTexts.safetyTitle(step.safety)); advice.font = Type.caption; advice.textColor = .secondaryLabelColor; advice.lineBreakMode = .byTruncatingTail
        advice.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        let chevron = NSImageView(image: symbol(userInterfaceLayoutDirection == .rightToLeft ? "chevron.left" : "chevron.right", 11) ?? NSImage()); chevron.contentTintColor = .tertiaryLabelColor; chevron.setAccessibilityElement(false)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [LocationTexts.safetyDot(step.safety), title, spacer, advice, size, chevron]); stack.spacing = 8; stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor, constant: 4), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)])
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel(step.title + ", " + bytes(step.bytes) + ", " + LocationTexts.safetyTitle(step.safety))
    }
    required init?(coder: NSCoder) { nil }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// Home screen: how full each drive is, what can go, what this session moved to Trash, and where to start. Reads volume attributes only;
/// "What can go" shows what Free up space measured, and measures nothing by itself.
/// The page heading and the promise sentence live in the window header, so the panel starts straight at the drives.
final class OverviewPanel: NSView {
    private let column = NSStackView()
    private let volumesStack = NSStackView()
    private let sectionSession: NSTextField
    /// "What can go": a headline, up to five steps, and one button (check now, or show all).
    private let stepsHeadline = NSTextField(wrappingLabelWithString: "")
    private let stepsStack = NSStackView()
    let stepsButton = NSButton()
    private(set) var stepIDs: [String] = []
    var onStep: ((String) -> Void)?
    var onOpenTrash: (() -> Void)?
    let openTrashButton = NSButton()
    private let sessionRow = NSStackView()
    private let sessionLabel = NSTextField(wrappingLabelWithString: "")
    /// One line on screen, in the label colour because it is a safety statement; the full explanation opens from the ⓘ.
    private let caveat = NSTextField(labelWithString: L("Trash is not free space until you empty it in Finder.", "הפח אינו מקום פנוי עד שמרוקנים אותו ב־Finder."))
    private let caveatInfo = InfoButton(L("More about free space", "עוד על מקום פנוי"), L("Free space is what you can still write. Trash is not free until you empty it in Finder, and APFS clones or snapshots can change what a move frees.", "מקום פנוי הוא מה שעדיין אפשר לכתוב. הפח אינו פנוי עד שמרוקנים אותו ב־Finder, ושכפולי APFS או תמונות מצב עשויים לשנות מה שהעברה מפנה."))
    let mapHomeButton = NSButton()
    let mapDriveButton = NSButton()
    let freeUpButton = NSButton()
    /// "Continue: ~/last folder"; hidden until a folder was reviewed once, and always in the read-only demo.
    let continueButton = NSButton()
    var onMapHome: (() -> Void)?
    var onMapDrive: (() -> Void)?
    var onFreeUp: (() -> Void)?
    var onContinue: (() -> Void)?
    private(set) var volumes: [VolumeInfo] = []

    override init(frame: NSRect) {
        func section(_ en: String, _ he: String) -> NSTextField { let v = NSTextField(labelWithString: L(en, he)); v.font = .systemFont(ofSize: 11, weight: .semibold); v.textColor = .secondaryLabelColor; return v }
        sectionSession = section("TRASH", "פח")
        super.init(frame: frame)
        volumesStack.orientation = .vertical; volumesStack.alignment = .leading; volumesStack.spacing = 8
        sessionLabel.font = Type.subhead; sessionLabel.textColor = .secondaryLabelColor
        stepsHeadline.font = Type.bodyMedium; stepsHeadline.textColor = .labelColor
        stepsStack.orientation = .vertical; stepsStack.alignment = .leading; stepsStack.spacing = 2
        stepsButton.bezelStyle = .rounded; stepsButton.font = Type.bodyMedium; stepsButton.imagePosition = .imageLeading; stepsButton.target = self; stepsButton.action = #selector(freeUp)
        openTrashButton.title = L("Open Trash", "פתח את הפח"); openTrashButton.bezelStyle = .rounded; openTrashButton.controlSize = .small; openTrashButton.font = Type.caption
        openTrashButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil); openTrashButton.imagePosition = .imageLeading; openTrashButton.target = self; openTrashButton.action = #selector(openTrash)
        caveat.font = Type.subhead; caveat.textColor = .labelColor; caveat.lineBreakMode = .byTruncatingTail; caveat.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (button, en, he, symbol, action) in [(continueButton, "Continue", "המשך", "arrow.counterclockwise", #selector(resume)),
                                                  (freeUpButton, "Free up space", "פינוי מקום", "sparkles", #selector(freeUp)),
                                                  (mapHomeButton, "Map home folder", "מפה את תיקיית הבית", "house", #selector(mapHome)),
                                                  (mapDriveButton, "Map a folder or drive…", "מפה תיקייה או כונן…", "externaldrive", #selector(mapDrive))] {
            button.title = L(en, he); button.bezelStyle = .rounded; button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.font = Type.bodyMedium; button.target = self; button.action = action; button.setAccessibilityLabel(L(en, he))
        }
        continueButton.isHidden = true; continueButton.lineBreakMode = .byTruncatingMiddle
        let actions = NSStackView(views: [continueButton, freeUpButton, mapHomeButton, mapDriveButton]); actions.spacing = 8
        let caveatRow = NSStackView(views: [caveat, caveatInfo]); caveatRow.spacing = 4; caveatRow.alignment = .centerY
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 8
        // A card like the drive cards: headline, the steps, the button.
        let stepsInner = NSStackView(views: [stepsHeadline, stepsStack, stepsButton]); stepsInner.orientation = .vertical; stepsInner.alignment = .leading; stepsInner.spacing = 8
        let stepsCard = NSView(); stepsCard.wantsLayer = true; stepsCard.layer?.cornerRadius = 10; stepsCard.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        stepsInner.translatesAutoresizingMaskIntoConstraints = false; stepsCard.addSubview(stepsInner)
        NSLayoutConstraint.activate([stepsInner.leadingAnchor.constraint(equalTo: stepsCard.leadingAnchor, constant: 16), stepsInner.trailingAnchor.constraint(equalTo: stepsCard.trailingAnchor, constant: -16),
                                     stepsInner.topAnchor.constraint(equalTo: stepsCard.topAnchor, constant: 12), stepsInner.bottomAnchor.constraint(equalTo: stepsCard.bottomAnchor, constant: -12),
                                     stepsHeadline.widthAnchor.constraint(equalTo: stepsInner.widthAnchor), stepsStack.widthAnchor.constraint(equalTo: stepsInner.widthAnchor)])
        stepsCard.setAccessibilityElement(true); stepsCard.setAccessibilityRole(.group); stepsCard.setAccessibilityLabel(L("What can go", "מה אפשר לפנות"))
        [sessionLabel, openTrashButton].forEach(sessionRow.addArrangedSubview); sessionRow.orientation = .vertical; sessionRow.alignment = .leading; sessionRow.spacing = 6
        for v in [section("DRIVES", "כוננים"), volumesStack, section("WHAT CAN GO", "מה אפשר לפנות"), stepsCard, sectionSession, sessionRow, section("START", "התחלה"), actions, caveatRow] { column.addArrangedSubview(v) }
        stepsCard.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        column.setCustomSpacing(24, after: volumesStack); column.setCustomSpacing(24, after: stepsCard); column.setCustomSpacing(24, after: sessionRow); column.setCustomSpacing(24, after: actions)
        column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
                                     column.topAnchor.constraint(equalTo: topAnchor, constant: 8), column.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
                                     volumesStack.widthAnchor.constraint(equalTo: column.widthAnchor), sessionLabel.widthAnchor.constraint(equalTo: column.widthAnchor), caveatRow.widthAnchor.constraint(equalTo: column.widthAnchor)])
        column.widthAnchor.constraint(equalTo: widthAnchor, constant: -48).withPriority(.defaultHigh).isActive = true
        setAccessibilityLabel(L("Overview", "סקירה כללית"))
        update(sessionMoved: 0)
        setSteps(measured: false, canGo: 0, other: 0, steps: [])
    }
    required init?(coder: NSCoder) { nil }

    /// Fills "What can go" from what Free up space measured. Before anything is measured it offers to check, and measures nothing itself.
    func setSteps(measured: Bool, canGo: Int64, other: Int64, steps: [OverviewStep]) {
        stepsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stepIDs = measured ? steps.map(\.id) : []
        if !measured {
            stepsHeadline.stringValue = L("See how much you can free: Avakasha measures known caches and app data, sizes only.", "כמה מקום אפשר לפנות? Avakasha מודדת מטמונים ונתוני אפליקציות מוכרים, גדלים בלבד.")
            stepsButton.title = L("Check what can go", "בדוק מה אפשר לפנות"); stepsButton.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            stepsStack.isHidden = true
        } else {
            var headline = L("Can go to Trash now: ", "אפשר להעביר לפח עכשיו: ") + bytes(canGo)
            if other > 0 { headline += "  ·  " + L("in apps, Terminal or to review: ", "דרך אפליקציות, Terminal או לסקירה: ") + bytes(other) }
            stepsHeadline.stringValue = headline
            stepsButton.title = L("Show all in Free up space", "הצג הכול בפינוי מקום"); stepsButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
            for step in steps {
                let row = StepRowView(step); row.onClick = { [weak self] in self?.onStep?(step.id) }
                stepsStack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stepsStack.widthAnchor).isActive = true
            }
            stepsStack.isHidden = steps.isEmpty
        }
        stepsButton.setAccessibilityLabel(stepsButton.title)
    }
    /// Re-reads the volumes and the session number; cheap, so call it whenever the overview is shown.
    /// `trash` is the Trash's size as Free up space last measured it, if it could.
    func update(sessionMoved: Int64, trash: Int64? = nil) {
        volumes = Volumes.mounted()
        volumesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for volume in volumes {
            let name = NSTextField(labelWithString: volume.name + (volume.isStartup ? " · " + L("startup disk", "דיסק האתחול") : (volume.isRemovable ? " · " + L("external", "חיצוני") : "")))
            name.font = Type.bodyMedium
            let numbers = NSTextField(labelWithString: L("Used ", "בשימוש ") + bytes(volume.used) + L(" of ", " מתוך ") + bytes(volume.total) + " · " + bytes(volume.available) + L(" free", " פנויים"))
            numbers.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); numbers.textColor = .secondaryLabelColor
            let bar = ShareBar(); bar.fraction = volume.usedFraction; bar.thickness = 6; bar.heightAnchor.constraint(equalToConstant: 10).isActive = true
            bar.setAccessibilityLabel(volume.name + " " + L("used", "בשימוש"))
            let inner = NSStackView(views: [name, bar, numbers]); inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 6
            // A plain layer-backed card pinned to its content, so its height follows the rows inside it.
            let card = NSView(); card.wantsLayer = true; card.layer?.cornerRadius = 10; card.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            inner.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(inner)
            NSLayoutConstraint.activate([inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
                                         inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 12), inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)])
            volumesStack.addArrangedSubview(card); card.widthAnchor.constraint(equalTo: volumesStack.widthAnchor).isActive = true
            bar.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }
        if volumes.isEmpty { volumesStack.addArrangedSubview(NSTextField(labelWithString: L("No drive information available.", "אין מידע על כוננים."))) }
        var lines: [String] = []
        if sessionMoved > 0 { lines.append(L("Moved to Trash this session: ", "הועבר לפח בהפעלה זו: ") + bytes(sessionMoved)) }
        if let trash = trash, trash > 0 { lines.append(L("In Trash now: ", "בפח עכשיו: ") + bytes(trash)) }
        lines.append(L("This space is freed only when you empty Trash in Finder, once you are sure.", "המקום הזה מתפנה רק כשמרוקנים את הפח ב־Finder, כשברור לך שאפשר."))
        sessionLabel.stringValue = lines.joined(separator: "\n")
        let show = sessionMoved > 0 || (trash ?? 0) > 0 // the header's promise sentence already covers "nothing moved yet"
        sectionSession.isHidden = !show; sessionRow.isHidden = !show
    }
    /// Shows "Continue: path" when there is a last folder to go back to; nil hides the button.
    func setContinue(_ path: String?) {
        continueButton.isHidden = path == nil
        continueButton.title = L("Continue: ", "המשך: ") + (path ?? ""); continueButton.toolTip = path
        continueButton.setAccessibilityLabel(L("Continue with the last folder", "המשך עם התיקייה האחרונה") + (path.map { " · " + $0 } ?? ""))
    }
    @objc private func mapHome() { onMapHome?() }
    @objc private func mapDrive() { onMapDrive?() }
    @objc private func freeUp() { onFreeUp?() }
    @objc private func resume() { onContinue?() }
    @objc private func openTrash() { onOpenTrash?() }
}

private extension NSLayoutConstraint {
    func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint { priority = p; return self }
}
