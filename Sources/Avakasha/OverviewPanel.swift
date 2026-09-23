import Cocoa
import AvakashaCore

/// Home screen: how full each drive is, what this session moved to Trash, and where to start. Reads volume attributes only.
/// The page heading and the promise sentence live in the window header, so the panel starts straight at the drives.
final class OverviewPanel: NSView {
    private let column = NSStackView()
    private let volumesStack = NSStackView()
    private let sectionSession: NSTextField
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
        sectionSession = section("THIS SESSION", "ההפעלה הזו")
        super.init(frame: frame)
        volumesStack.orientation = .vertical; volumesStack.alignment = .leading; volumesStack.spacing = 8
        sessionLabel.font = Type.subhead; sessionLabel.textColor = .secondaryLabelColor
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
        for v in [section("DRIVES", "כוננים"), volumesStack, sectionSession, sessionLabel, section("START", "התחלה"), actions, caveatRow] { column.addArrangedSubview(v) }
        column.setCustomSpacing(24, after: volumesStack); column.setCustomSpacing(24, after: sessionLabel); column.setCustomSpacing(24, after: actions)
        column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24), column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
                                     column.topAnchor.constraint(equalTo: topAnchor, constant: 8), column.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
                                     volumesStack.widthAnchor.constraint(equalTo: column.widthAnchor), sessionLabel.widthAnchor.constraint(equalTo: column.widthAnchor), caveatRow.widthAnchor.constraint(equalTo: column.widthAnchor)])
        column.widthAnchor.constraint(equalTo: widthAnchor, constant: -48).withPriority(.defaultHigh).isActive = true
        setAccessibilityLabel(L("Overview", "סקירה כללית"))
        update(sessionMoved: 0)
    }
    required init?(coder: NSCoder) { nil }

    /// Re-reads the volumes and the session number; cheap, so call it whenever the overview is shown.
    func update(sessionMoved: Int64) {
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
        sessionLabel.stringValue = L("Moved to Trash this session: ", "הועבר לפח בהפעלה זו: ") + bytes(sessionMoved) + " · " + L("empty Trash in Finder when you are sure.", "כשברור לך שאפשר, מרוקנים את הפח ב־Finder.")
        sectionSession.isHidden = sessionMoved <= 0; sessionLabel.isHidden = sessionMoved <= 0 // the header's promise sentence already covers "nothing moved yet"
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
}

private extension NSLayoutConstraint {
    func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint { priority = p; return self }
}
