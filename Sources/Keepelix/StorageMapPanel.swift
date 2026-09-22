import Cocoa
import KeepelixCore

/// A row in the storage map: a subfolder, or the loose files directly inside the current folder.
struct MapRow {
    let node: StorageNode?
    let title: String
    let bytes: Int64
    var isFolder: Bool { node != nil }
    /// Folders that can be entered in the map or handed to file review.
    var isOpenable: Bool { node.map { !$0.isPackage && !$0.isUnreadable } ?? false }
}

/// Horizontal bar showing a folder's share of its parent.
final class ShareBar: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true; setAccessibilityValue(String(Int((fraction * 100).rounded())) + "%") } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: bounds.midY - 4, width: bounds.width, height: 8)
        NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        let width = max(fraction > 0 ? 8 : 0, track.width * CGFloat(min(max(fraction, 0), 1)))
        let x = userInterfaceLayoutDirection == .rightToLeft ? track.width - width : 0
        NSColor.controlAccentColor.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: track.minY, width: width, height: 8), xRadius: 4, yRadius: 4).fill()
    }
}

final class MapTable: NSTableView {
    var onOpen: (() -> Void)?
    var onUp: (() -> Void)?
    var onReveal: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        if event.keyCode == 36 || event.keyCode == 76 || (command && event.keyCode == 125) { if !event.isARepeat { onOpen?() }; return }
        if command && event.keyCode == 126 { if !event.isARepeat { onUp?() }; return }
        if event.keyCode == 51 || event.keyCode == 117 { NSSound.beep(); return } // The map never moves files; review them first.
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0, index < numberOfRows else { return nil }
        if !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        let menu = NSMenu()
        let item = NSMenuItem(title: L("Reveal in Finder", "הצג ב־Finder"), action: #selector(revealRow(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = index; menu.addItem(item); return menu
    }
    @objc private func revealRow(_ sender: NSMenuItem) { if let index = sender.representedObject as? Int { onReveal?(index) } }
}

/// Folder-level view of where the space goes. Read-only: it measures, it never moves anything.
final class StorageMapPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let table = MapTable()
    let crumbs = NSPopUpButton()
    let openButton = NSButton()
    let reviewButton = NSButton()
    let detail = NSStackView()
    private let detailTitle = NSTextField(wrappingLabelWithString: "")
    private let detailSize = NSTextField(labelWithString: "")
    private let detailPath = NSTextField(wrappingLabelWithString: "")
    private let detailFacts = NSTextField(wrappingLabelWithString: "")
    private let detailNotes = NSTextField(wrappingLabelWithString: "")
    private let caveat = NSTextField(wrappingLabelWithString: L("Sizes are space allocated on disk. Hard links, APFS clones, snapshots and cloud placeholders mean moving files to Trash may free a different amount.", "הגדלים הם המקום שמוקצה בדיסק. קישורים קשיחים, שכפולי APFS, תמונות מצב וקבצי ענן שלא הורדו גורמים לכך שהעברה לפח עשויה לפנות כמות שונה."))
    private(set) var result: StorageMapResult?
    private(set) var current: StorageNode?
    private(set) var rows: [MapRow] = []
    var onReview: ((URL) -> Void)?
    var onSelectionChange: (() -> Void)?
    var onReveal: ((URL) -> Void)?
    /// Names loaded on request from WhatsApp's chat list; empty until the user asks.
    var chatNames: [String: ChatInfo] = [:] { didSet { table.reloadData() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        crumbs.target = self; crumbs.action = #selector(jumpToCrumb); crumbs.font = .systemFont(ofSize: 12)
        crumbs.setAccessibilityLabel(L("Folder path", "נתיב התיקייה"))
        for (button, en, he, symbol, action) in [(openButton, "Open folder", "פתח תיקייה", "arrow.down.right.square", #selector(openSelected)),
                                                  (reviewButton, "Review files here", "סקור קבצים כאן", "list.bullet.rectangle", #selector(reviewSelected))] {
            button.title = L(en, he); button.target = self; button.action = action; button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 13, weight: .medium); button.setAccessibilityLabel(L(en, he))
        }
        reviewButton.keyEquivalent = ""; reviewButton.toolTip = L("Show the files of this folder for review. Nothing is moved.", "הצג את קבצי התיקייה לסקירה. שום דבר לא מועבר.")
        openButton.toolTip = L("Return or ⌘↓ opens a folder in the map; ⌘↑ goes up.", "Return או ⌘↓ פותחים תיקייה במפה; ⌘↑ עולה רמה.")
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let toolbar = NSStackView(views: [crumbs, spacer, openButton, reviewButton]); toolbar.spacing = 8; toolbar.alignment = .centerY
        crumbs.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 12, height: 4); table.usesAlternatingRowBackgroundColors = false; table.style = .inset
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.allowsMultipleSelection = false
        table.setAccessibilityLabel(L("Storage map", "מפת אחסון"))
        for (id, title, width) in [("name", L("Folder", "תיקייה"), 190.0), ("size", L("On disk", "בדיסק"), 70.0), ("share", L("Share", "חלק"), 64.0), ("notes", L("Details", "פרטים"), 150.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = id == "share" ? 48 : 60; table.addTableColumn(c)
        }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = table
        let column = NSStackView(views: [toolbar, scroll]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     toolbar.widthAnchor.constraint(equalTo: column.widthAnchor), scroll.widthAnchor.constraint(equalTo: column.widthAnchor)])
        table.delegate = self; table.dataSource = self
        table.onOpen = { [weak self] in self?.openSelected() }
        table.onUp = { [weak self] in self?.goUp() }
        table.onReveal = { [weak self] index in guard let self = self, index < self.rows.count else { return }; self.onReveal?(self.rows[index].node?.url ?? self.current?.url ?? URL(fileURLWithPath: "/")) }
        table.doubleAction = #selector(openSelected); table.target = self

        detailTitle.font = .systemFont(ofSize: 17, weight: .medium); detailTitle.maximumNumberOfLines = 3
        detailPath.font = .monospacedSystemFont(ofSize: 11, weight: .regular); detailPath.textColor = .secondaryLabelColor; detailPath.maximumNumberOfLines = 3; detailPath.lineBreakMode = .byTruncatingMiddle; detailPath.isSelectable = true
        detailPath.setAccessibilityLabel(L("Folder path", "נתיב התיקייה"))
        detailSize.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        detailFacts.font = .systemFont(ofSize: 12); detailFacts.textColor = .secondaryLabelColor
        detailNotes.font = .systemFont(ofSize: 12); detailNotes.textColor = .systemOrange
        caveat.font = .systemFont(ofSize: 11); caveat.textColor = .tertiaryLabelColor
        detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 10
        for view in [detailSize, detailTitle, detailPath, detailFacts, detailNotes, caveat] { detail.addArrangedSubview(view) }
        detail.setCustomSpacing(4, after: detailTitle)
        detail.setCustomSpacing(24, after: detailNotes)
        for view in [detailTitle, detailPath, detailFacts, detailNotes, caveat] { view.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true }
        detail.setAccessibilityLabel(L("Folder details", "פרטי התיקייה"))
        showNothing()
    }
    required init?(coder: NSCoder) { nil }

    var isEmpty: Bool { current == nil }
    var selectedRow: MapRow? { table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil }
    /// The folder that "Review files here" would hand to the file review, or nil when the selection cannot be reviewed.
    var reviewTarget: URL? {
        guard let current = current else { return nil }
        guard let row = selectedRow else { return current.isPackage ? nil : current.url }
        if let node = row.node { return row.isOpenable ? node.url : nil }
        return current.url
    }

    func load(_ result: StorageMapResult?) {
        self.result = result
        guard let result = result else { showNothing(); return }
        show(result.root)
    }
    func showNothing() {
        current = nil; rows = []; table.reloadData(); crumbs.removeAllItems(); updateDetail(); updateButtons(); onSelectionChange?()
    }
    func show(_ node: StorageNode, selecting child: StorageNode? = nil) {
        current = node
        rows = node.children.map { MapRow(node: $0, title: $0.name, bytes: $0.bytes) }
        if node.directFiles > 0 { rows.append(MapRow(node: nil, title: L("Files in this folder", "קבצים בתיקייה עצמה"), bytes: node.directBytes)) }
        rows.sort { $0.bytes == $1.bytes ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.bytes > $1.bytes }
        table.reloadData()
        crumbs.removeAllItems()
        for ancestor in node.trail { crumbs.addItem(withTitle: ancestor.name.isEmpty ? ancestor.url.path : ancestor.name); crumbs.lastItem?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) }
        crumbs.selectItem(at: crumbs.numberOfItems - 1)
        if !rows.isEmpty {
            let index = child.flatMap { c in rows.firstIndex { $0.node === c } } ?? 0
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false); table.scrollRowToVisible(index)
        }
        updateDetail(); updateButtons(); onSelectionChange?()
    }
    /// Shows the deepest mapped folder that contains `url`, if the map covers it.
    @discardableResult func reveal(folder url: URL) -> Bool {
        guard let root = result?.root else { return false }
        let target = url.standardizedFileURL.path
        guard target == root.url.path || target.hasPrefix(root.url.path + "/") else { return false }
        var node = root
        while node.url.path != target, let next = node.children.first(where: { target == $0.url.path || target.hasPrefix($0.url.path + "/") }) { node = next }
        if node.url.path == target, !node.isPackage, !node.isUnreadable { show(node) } else if let parent = node.parent { show(parent, selecting: node) } else { show(node) }
        return true
    }
    @objc func openSelected() {
        guard let row = selectedRow else { return }
        guard let node = row.node, row.isOpenable else { NSSound.beep(); return }
        show(node); window?.makeFirstResponder(table)
    }
    @objc func goUp() {
        guard let current = current, let parent = current.parent else { NSSound.beep(); return }
        show(parent, selecting: current); window?.makeFirstResponder(table)
    }
    @objc func reviewSelected() { if let url = reviewTarget { onReview?(url) } else { NSSound.beep() } }
    @objc private func jumpToCrumb() {
        guard let current = current else { return }
        let trail = current.trail; let index = crumbs.indexOfSelectedItem
        guard index >= 0, index < trail.count - 1 else { return }
        show(trail[index], selecting: trail[index + 1]); window?.makeFirstResponder(table)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        let row = rows[index]; let parentBytes = max(current?.bytes ?? 0, 1)
        switch tableColumn?.identifier.rawValue {
        case "size":
            let v = NSTextField(labelWithString: bytes(row.bytes)); v.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); v.textColor = .secondaryLabelColor; v.alignment = .right; return v
        case "share":
            let bar = ShareBar(); bar.fraction = Double(row.bytes) / Double(parentBytes); bar.setAccessibilityLabel(L("Share of this folder", "חלק מהתיקייה")); bar.setAccessibilityRole(.progressIndicator); return bar
        case "notes":
            let v = NSTextField(labelWithString: notes(for: row)); v.font = .systemFont(ofSize: 11); v.textColor = row.node?.hasCaveats == true ? .systemOrange : .secondaryLabelColor; v.lineBreakMode = .byTruncatingTail; return v
        default:
            let symbol = row.node.map { $0.isUnreadable ? "lock.fill" : ($0.isPackage ? "shippingbox" : ($0.isHidden ? "eye.slash" : "folder.fill")) } ?? "doc.on.doc"
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = row.node?.isUnreadable == true ? .systemOrange : (row.isFolder ? .controlAccentColor : .secondaryLabelColor)
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true; icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let v = NSTextField(labelWithString: row.title); v.font = .systemFont(ofSize: 13, weight: .medium); v.lineBreakMode = .byTruncatingMiddle
            if !row.isFolder { v.textColor = .secondaryLabelColor }
            let cell = NSStackView(views: [icon, v]); cell.spacing = 9; cell.toolTip = row.node?.url.path ?? current?.url.path; return cell
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail(); updateButtons(); onSelectionChange?() }

    private func notes(for row: MapRow) -> String {
        guard let node = row.node else { return "\(current?.directFiles ?? 0) " + L("files", "קבצים") }
        var parts: [String] = []
        if node.isUnreadable { parts.append(L("Not accessible", "לא נגיש")) }
        else { parts.append("\(node.files) " + L("files", "קבצים") + (node.directories > 0 ? " · \(node.directories) " + L("folders", "תיקיות") : "")) }
        if node.isPackage { parts.append(L("Bundle", "חבילה")) }
        let chatLabel: String? = { switch ChatFolders.kind(of: node.url.appendingPathComponent("x")) { case .group?: return L("Group chat", "קבוצה"); case .personal?: return L("Personal chat", "שיחה אישית"); case .broadcast?: return L("Status / broadcast", "סטטוס / תפוצה"); case nil: return nil } }()
        if let label = chatLabel { parts.append(chatNames[node.name.lowercased()].map { label + ": " + $0.name } ?? label) }
        if node.isHidden { parts.append(L("Hidden", "מוסתר")) }
        if !node.isUnreadable && node.inaccessible > 0 { parts.append("\(node.inaccessible) " + L("not accessible", "לא נגישים")) }
        if node.notDownloaded > 0 { parts.append("\(node.notDownloaded) " + L("not downloaded", "לא הורדו")) }
        if node.otherVolumes > 0 { parts.append(L("Other volume skipped", "כונן אחר דולג")) }
        return parts.joined(separator: " · ")
    }
    private func updateDetail() {
        guard let current = current else {
            detailSize.stringValue = ""; detailTitle.stringValue = L("Where is the space?", "איפה המקום?")
            detailFacts.stringValue = L("Map a folder or drive to see which folders fill it, then review the files inside.", "מפה תיקייה או כונן כדי לראות אילו תיקיות ממלאות אותו, ואז סקור את הקבצים שבפנים.")
            detailNotes.stringValue = ""; detailNotes.isHidden = true; detailPath.stringValue = ""; detailPath.isHidden = true; return
        }
        let row = selectedRow; let node = row?.node ?? current
        let root = result?.root
        detailSize.stringValue = bytes(row?.bytes ?? current.bytes)
        detailTitle.stringValue = row?.node == nil && row != nil ? L("Files directly in ", "קבצים ישירות בתוך ") + current.name : node.name
        detailPath.stringValue = (node.url.path as NSString).abbreviatingWithTildeInPath; detailPath.toolTip = node.url.path; detailPath.isHidden = false
        var facts: [String] = []
        if row?.node == nil, row != nil { facts.append("\(current.directFiles) " + L("files", "קבצים")) }
        else if !node.isUnreadable { facts.append("\(node.files) " + L("files", "קבצים") + " · \(node.directories) " + L("folders", "תיקיות")) }
        if let root = root, root.bytes > 0 {
            let shown = row?.bytes ?? current.bytes
            facts.append(String(format: L("%.1f%% of ", "%.1f%% מתוך ") + root.name, Double(shown) / Double(root.bytes) * 100))
        }
        detailFacts.stringValue = facts.joined(separator: "\n")
        var notes: [String] = []
        if node.isUnreadable { notes.append(L("This folder could not be read. Grant access in System Settings › Privacy & Security, or leave it.", "לא ניתן לקרוא את התיקייה. אפשר לתת גישה ב־System Settings › Privacy & Security או להשאיר אותה.")) }
        if node.isPackage { notes.append(L("A bundle such as an app or a library. Its contents are measured but not reviewed file by file.", "חבילה כמו אפליקציה או ספרייה. התוכן נמדד אך לא נסקר קובץ־קובץ.")) }
        if node.isHidden { notes.append(L("Hidden folder. System and app data often live here; review with care.", "תיקייה מוסתרת. לרוב מכילה נתוני מערכת ואפליקציות; יש לסקור בזהירות.")) }
        if !node.isUnreadable && node.inaccessible > 0 { notes.append("\(node.inaccessible) " + L("items could not be read and are not counted.", "פריטים לא נקראו ואינם נספרים.")) }
        if node.notDownloaded > 0 { notes.append("\(node.notDownloaded) " + L("cloud items are not downloaded and take no local space.", "פריטי ענן לא הורדו ואינם תופסים מקום מקומי.")) }
        if node.otherVolumes > 0 { notes.append("\(node.otherVolumes) " + L("mount points for other volumes were not entered.", "נקודות עיגון של כוננים אחרים לא נסרקו.")) }
        if let result = result, node === result.root, result.cancelled { notes.append(L("Mapping was cancelled; totals are partial.", "המיפוי בוטל; הסכומים חלקיים.")) }
        detailNotes.stringValue = notes.joined(separator: "\n"); detailNotes.isHidden = notes.isEmpty
    }
    private func updateButtons() {
        openButton.isEnabled = selectedRow?.isOpenable == true
        reviewButton.isEnabled = reviewTarget != nil
    }
    func setEnabled(_ enabled: Bool) { table.isEnabled = enabled; crumbs.isEnabled = enabled; if enabled { updateButtons() } else { openButton.isEnabled = false; reviewButton.isEnabled = false } }
}
