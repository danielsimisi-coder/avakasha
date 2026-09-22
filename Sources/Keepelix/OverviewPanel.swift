import Cocoa
import KeepelixCore

/// Home screen: how full each disk is, what this session moved to Trash, and where to start. Reads volume attributes only.
final class OverviewPanel: NSView {
    private let column = NSStackView()
    private let volumesStack = NSStackView()
    private let sessionLabel = NSTextField(wrappingLabelWithString: "")
    private let caveat = NSTextField(wrappingLabelWithString: L("Free space is what you can still write. Trash is not free until you empty it in Finder, and APFS clones or snapshots can change what a move frees.", "מקום פנוי הוא מה שעדיין אפשר לכתוב. הפח אינו פנוי עד שמרוקנים אותו ב־Finder, ושכפולי APFS או תמונות מצב עשויים לשנות מה שהעברה מפנה."))
    let mapHomeButton = NSButton()
    let mapDriveButton = NSButton()
    let trashButton = NSButton()
    var onMapHome: (() -> Void)?
    var onMapDrive: (() -> Void)?
    var onOpenTrash: (() -> Void)?
    private(set) var volumes: [VolumeInfo] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
            let v = NSTextField(labelWithString: text); v.font = .systemFont(ofSize: size, weight: weight); v.textColor = secondary ? .secondaryLabelColor : .labelColor; return v
        }
        let title = label(L("Your Mac", "המק שלך"), 17, .medium)
        let subtitle = label(L("Disks now, this session, and where to start.", "הכוננים עכשיו, ההפעלה הזו, ומאיפה להתחיל."), 12, .regular, secondary: true)
        volumesStack.orientation = .vertical; volumesStack.alignment = .leading; volumesStack.spacing = 14
        sessionLabel.font = .systemFont(ofSize: 12); sessionLabel.textColor = .secondaryLabelColor
        caveat.font = .systemFont(ofSize: 11); caveat.textColor = .tertiaryLabelColor
        for (button, en, he, symbol, action) in [(mapHomeButton, "Map home folder", "מפה את תיקיית הבית", "house", #selector(mapHome)),
                                                  (mapDriveButton, "Map a folder or drive…", "מפה תיקייה או כונן…", "externaldrive", #selector(mapDrive)),
                                                  (trashButton, "Trash in Finder", "הפח ב־Finder", "trash", #selector(openTrash))] {
            button.title = L(en, he); button.bezelStyle = .rounded; button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 13, weight: .medium); button.target = self; button.action = action; button.setAccessibilityLabel(L(en, he))
        }
        let actions = NSStackView(views: [mapHomeButton, mapDriveButton, trashButton]); actions.spacing = 10
        let sectionDisks = label(L("DISKS", "כוננים"), 10, .semibold, secondary: true)
        let sectionSession = label(L("THIS SESSION", "ההפעלה הזו"), 10, .semibold, secondary: true)
        let sectionStart = label(L("START", "התחלה"), 10, .semibold, secondary: true)
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 10
        for v in [title, subtitle, sectionDisks, volumesStack, sectionSession, sessionLabel, sectionStart, actions, caveat] { column.addArrangedSubview(v) }
        column.setCustomSpacing(22, after: subtitle); column.setCustomSpacing(22, after: volumesStack); column.setCustomSpacing(22, after: sessionLabel); column.setCustomSpacing(26, after: actions)
        column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28), column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28),
                                     column.topAnchor.constraint(equalTo: topAnchor, constant: 28), column.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
                                     volumesStack.widthAnchor.constraint(equalTo: column.widthAnchor), caveat.widthAnchor.constraint(equalTo: column.widthAnchor), sessionLabel.widthAnchor.constraint(equalTo: column.widthAnchor)])
        column.widthAnchor.constraint(equalTo: widthAnchor, constant: -56).withPriority(.defaultHigh).isActive = true
        setAccessibilityLabel(L("Overview", "סקירה כללית"))
        update(sessionMoved: 0)
    }
    required init?(coder: NSCoder) { nil }

    /// Re-reads the volumes and the session number; cheap, so call it whenever the overview is shown.
    func update(sessionMoved: Int64) {
        volumes = Volumes.mounted()
        volumesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for volume in volumes {
            let name = NSTextField(labelWithString: volume.name + (volume.isStartup ? " · " + L("startup disk", "דיסק ההפעלה") : (volume.isRemovable ? " · " + L("external", "חיצוני") : "")))
            name.font = .systemFont(ofSize: 13, weight: .medium)
            let numbers = NSTextField(labelWithString: L("Used ", "בשימוש ") + bytes(volume.used) + L(" of ", " מתוך ") + bytes(volume.total) + " · " + L("free ", "פנוי ") + bytes(volume.available))
            numbers.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); numbers.textColor = .secondaryLabelColor
            let bar = ShareBar(); bar.fraction = volume.usedFraction; bar.heightAnchor.constraint(equalToConstant: 12).isActive = true
            bar.setAccessibilityLabel(volume.name + " " + L("used", "בשימוש"))
            let row = NSStackView(views: [name, numbers, bar]); row.orientation = .vertical; row.alignment = .leading; row.spacing = 4
            volumesStack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: volumesStack.widthAnchor).isActive = true; bar.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }
        if volumes.isEmpty { volumesStack.addArrangedSubview(NSTextField(labelWithString: L("No volume information available.", "אין מידע על כוננים."))) }
        sessionLabel.stringValue = sessionMoved > 0
            ? L("Moved to Trash this session: ", "הועבר לפח בהפעלה זו: ") + bytes(sessionMoved) + " · " + L("empty Trash in Finder when you are sure.", "רוקן את הפח ב־Finder כשאתה בטוח.")
            : L("Nothing moved to Trash yet. Choose a location in the sidebar, or map a drive to see what fills it.", "עדיין לא הועבר דבר לפח. בחר מיקום בסרגל הצדדי, או מפה כונן כדי לראות מה ממלא אותו.")
    }
    @objc private func mapHome() { onMapHome?() }
    @objc private func mapDrive() { onMapDrive?() }
    @objc private func openTrash() { onOpenTrash?() }
}

private extension NSLayoutConstraint {
    func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint { priority = p; return self }
}
