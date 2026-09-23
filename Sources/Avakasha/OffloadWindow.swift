import Cocoa
import AvakashaCore

/// "Offloaded folders": every folder moved to a drive, where its verified copy is, and a way to bring it back.
final class OffloadWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let showButton = NSButton(), bringBackButton = NSButton()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    var records: [OffloadRecord] = [] { didSet { table.reloadData(); updateButtons() } }
    var onShow: ((OffloadRecord) -> Void)?
    var onBringBack: ((OffloadRecord) -> Void)?

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 380), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = L("Offloaded Folders", "תיקיות שהועברו לכונן"); panel.minSize = NSSize(width: 620, height: 260); panel.isReleasedWhenClosed = false
        super.init(window: panel)
        for (id, title, width) in [("name", L("Folder", "תיקייה"), 220.0), ("size", L("Size", "גודל"), 80.0), ("drive", L("Drive", "כונן"), 140.0), ("date", L("Moved", "הועבר"), 110.0), ("status", L("Status", "מצב"), 160.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; table.addTableColumn(c)
        }
        table.style = .inset; table.rowHeight = 26; table.delegate = self; table.dataSource = self; table.setAccessibilityLabel(L("Offloaded folders", "תיקיות שהועברו לכונן"))
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        for (button, en, he, symbolName, action) in [(showButton, "Show on Drive", "הצג בכונן", "folder", #selector(show)), (bringBackButton, "Bring Back…", "החזר…", "arrow.uturn.backward", #selector(bringBack))] {
            button.title = L(en, he); button.bezelStyle = .rounded; button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil); button.imagePosition = .imageLeading; button.target = self; button.action = action
        }
        bringBackButton.toolTip = L("Copies the folder back from the drive, checking every file against the manifest. The copy on the drive stays.", "מעתיק את התיקייה בחזרה מהכונן ובודק כל קובץ מול המניפסט. העותק בכונן נשאר.")
        emptyLabel.stringValue = L("Nothing has been moved to a drive yet. In the storage map or Free up space, choose a folder and Move to Drive…", "עדיין לא הועבר דבר לכונן. במפת האחסון או בפינוי מקום בוחרים תיקייה ו״העבר לכונן…״")
        emptyLabel.textColor = .secondaryLabelColor; emptyLabel.font = Type.subhead
        let note = NSTextField(wrappingLabelWithString: L("Each copy on the drive has an “Avakasha manifest.json” listing every file with its SHA-256, so it can be checked with or without Avakasha.", "לכל עותק בכונן יש קובץ ״Avakasha manifest.json״ שמפרט כל קובץ עם ה־SHA-256 שלו, כך שאפשר לבדוק אותו עם Avakasha או בלעדיה."))
        note.font = Type.caption; note.textColor = .secondaryLabelColor
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [note, spacer, showButton, bringBackButton]); buttons.spacing = 8; buttons.alignment = .centerY
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let column = NSStackView(views: [emptyLabel, scroll, buttons]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 10
        column.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        column.translatesAutoresizingMaskIntoConstraints = false; panel.contentView?.addSubview(column)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: content.leadingAnchor), column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                         column.topAnchor.constraint(equalTo: content.topAnchor), column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                                         scroll.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32), buttons.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32),
                                         emptyLabel.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32)])
        }
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
        updateButtons()
    }
    required init?(coder: NSCoder) { nil }

    var selected: OffloadRecord? { table.selectedRow >= 0 && table.selectedRow < records.count ? records[table.selectedRow] : nil }
    func updateButtons() {
        emptyLabel.isHidden = !records.isEmpty
        showButton.isEnabled = selected?.isAvailable == true
        bringBackButton.isEnabled = selected.map { $0.isAvailable && $0.broughtBackTo == nil } ?? false
    }
    @objc private func show() { if let r = selected { onShow?(r) } }
    @objc private func bringBack() { if let r = selected { onBringBack?(r) } }

    static func status(of record: OffloadRecord) -> String {
        if let back = record.broughtBackTo { return L("Brought back to ", "הוחזר אל ") + (back as NSString).abbreviatingWithTildeInPath }
        return record.isAvailable ? L("On the drive, verified", "בכונן, נבדק") : L("Drive not connected", "הכונן לא מחובר")
    }
    func numberOfRows(in tableView: NSTableView) -> Int { records.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = records[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "size": text = bytes(r.bytes)
        case "drive": text = r.volumeName
        case "date": text = DateFormatter.localizedString(from: r.date, dateStyle: .medium, timeStyle: .none)
        case "status": text = Self.status(of: r)
        default: text = r.name
        }
        let v = NSTextField(labelWithString: text); v.lineBreakMode = .byTruncatingMiddle
        v.font = tableColumn?.identifier.rawValue == "name" ? Type.bodyMedium : Type.subhead
        if tableColumn?.identifier.rawValue == "name" { v.toolTip = r.originalPath } else if tableColumn?.identifier.rawValue == "status" { v.textColor = .secondaryLabelColor }
        return v
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
}
