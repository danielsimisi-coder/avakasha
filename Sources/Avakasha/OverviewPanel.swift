import Cocoa
import AvakashaCore

/// The space guard as the overview shows it: the floor, today's free space, the forecast and what grew.
struct GuardState: Equatable {
    let floor: Int64; let volumeName: String; let free: Int64; let forecastDays: Double?; let historyDays: Int; let growthLine: String?; let attentionTarget: Int64?
}

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
    var onTimeMachine: (() -> Void)?
    /// Per drive, the part of System Data no file move changes: purgeable space and local snapshots (names and dates only).
    private(set) var systemDataLines: [String] = []
    let openTrashButton = NSButton()
    /// "Keep free space": a floor, what the watch sees, and a plan when the floor is near.
    private let guardHeadline = NSTextField(wrappingLabelWithString: "")
    private let guardDetail = NSTextField(wrappingLabelWithString: "")
    let floorPopup = NSPopUpButton()
    let guardPlanButton = NSButton()
    var onFloor: ((Int64) -> Void)?
    var onGuardPlan: ((Int64) -> Void)?
    private(set) var guardState: GuardState?
    static let floorChoices: [Int64] = [0, 20_000_000_000, 40_000_000_000, 60_000_000_000, 100_000_000_000]
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
        guardHeadline.font = Type.bodyMedium; guardDetail.font = Type.subhead; guardDetail.textColor = .secondaryLabelColor
        for value in Self.floorChoices { floorPopup.addItem(withTitle: value == 0 ? L("Off", "כבוי") : L("Keep at least ", "לשמור לפחות ") + bytes(value)); floorPopup.lastItem?.representedObject = NSNumber(value: value) }
        floorPopup.controlSize = .small; floorPopup.font = Type.caption; floorPopup.target = self; floorPopup.action = #selector(floorChosen); floorPopup.setAccessibilityLabel(L("Free space to keep", "מקום פנוי לשמור"))
        guardPlanButton.bezelStyle = .rounded; guardPlanButton.controlSize = .small; guardPlanButton.font = Type.caption; guardPlanButton.target = self; guardPlanButton.action = #selector(guardPlan)
        guardPlanButton.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil); guardPlanButton.imagePosition = .imageLeading
        let guardControls = NSStackView(views: [floorPopup, guardPlanButton]); guardControls.spacing = 8
        let guardInner = NSStackView(views: [guardHeadline, guardDetail, guardControls]); guardInner.orientation = .vertical; guardInner.alignment = .leading; guardInner.spacing = 6
        let guardCard = NSView(); guardCard.wantsLayer = true; guardCard.layer?.cornerRadius = 10; guardCard.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        guardInner.translatesAutoresizingMaskIntoConstraints = false; guardCard.addSubview(guardInner)
        NSLayoutConstraint.activate([guardInner.leadingAnchor.constraint(equalTo: guardCard.leadingAnchor, constant: 16), guardInner.trailingAnchor.constraint(equalTo: guardCard.trailingAnchor, constant: -16),
                                     guardInner.topAnchor.constraint(equalTo: guardCard.topAnchor, constant: 12), guardInner.bottomAnchor.constraint(equalTo: guardCard.bottomAnchor, constant: -12),
                                     guardHeadline.widthAnchor.constraint(equalTo: guardInner.widthAnchor), guardDetail.widthAnchor.constraint(equalTo: guardInner.widthAnchor)])
        guardCard.setAccessibilityElement(true); guardCard.setAccessibilityRole(.group); guardCard.setAccessibilityLabel(L("Keep free space", "שמירת מקום פנוי"))
        // A card like the drive cards: headline, the steps, the button.
        let stepsInner = NSStackView(views: [stepsHeadline, stepsStack, stepsButton]); stepsInner.orientation = .vertical; stepsInner.alignment = .leading; stepsInner.spacing = 8
        let stepsCard = NSView(); stepsCard.wantsLayer = true; stepsCard.layer?.cornerRadius = 10; stepsCard.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        stepsInner.translatesAutoresizingMaskIntoConstraints = false; stepsCard.addSubview(stepsInner)
        NSLayoutConstraint.activate([stepsInner.leadingAnchor.constraint(equalTo: stepsCard.leadingAnchor, constant: 16), stepsInner.trailingAnchor.constraint(equalTo: stepsCard.trailingAnchor, constant: -16),
                                     stepsInner.topAnchor.constraint(equalTo: stepsCard.topAnchor, constant: 12), stepsInner.bottomAnchor.constraint(equalTo: stepsCard.bottomAnchor, constant: -12),
                                     stepsHeadline.widthAnchor.constraint(equalTo: stepsInner.widthAnchor), stepsStack.widthAnchor.constraint(equalTo: stepsInner.widthAnchor)])
        stepsCard.setAccessibilityElement(true); stepsCard.setAccessibilityRole(.group); stepsCard.setAccessibilityLabel(L("What can go", "מה אפשר לפנות"))
        [sessionLabel, openTrashButton].forEach(sessionRow.addArrangedSubview); sessionRow.orientation = .vertical; sessionRow.alignment = .leading; sessionRow.spacing = 6
        for v in [section("DRIVES", "כוננים"), volumesStack, section("KEEP FREE SPACE", "שמירת מקום פנוי"), guardCard, section("WHAT CAN GO", "מה אפשר לפנות"), stepsCard, sectionSession, sessionRow, section("START", "התחלה"), actions, caveatRow] { column.addArrangedSubview(v) }
        stepsCard.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true; guardCard.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        column.setCustomSpacing(24, after: volumesStack); column.setCustomSpacing(24, after: guardCard); column.setCustomSpacing(24, after: stepsCard); column.setCustomSpacing(24, after: sessionRow); column.setCustomSpacing(24, after: actions)
        // The sections scroll when the window is short or there are several drives; the column keeps its reading width.
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let document = FlippedView(); scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        document.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(column)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor), document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                                     column.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24), column.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -24),
                                     column.topAnchor.constraint(equalTo: document.topAnchor, constant: 8), column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16), column.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
                                     volumesStack.widthAnchor.constraint(equalTo: column.widthAnchor), sessionLabel.widthAnchor.constraint(equalTo: column.widthAnchor), caveatRow.widthAnchor.constraint(equalTo: column.widthAnchor)])
        column.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -48).withPriority(.defaultHigh).isActive = true
        setAccessibilityLabel(L("Overview", "סקירה כללית"))
        update(sessionMoved: 0)
        setSteps(measured: false, canGo: 0, other: 0, steps: [])
        setGuard(nil)
    }
    /// nil: the guard is off and the card explains it. Otherwise the floor, the forecast, what grew and, near the floor, a plan button.
    func setGuard(_ state: GuardState?) {
        guardState = state
        floorPopup.selectItem(at: Self.floorChoices.firstIndex(of: state?.floor ?? 0) ?? 0)
        guard let s = state else {
            guardHeadline.stringValue = L("Choose how much free space to keep.", "בוחרים כמה מקום פנוי לשמור.")
            guardDetail.stringValue = L("Avakasha then watches this Mac while it is open: what grows, when the floor will be reached, and a plan ready before it is. Off by default; nothing moves without your confirmation.", "מכאן Avakasha עוקבת אחרי ה־Mac כל עוד היא פתוחה: מה גדל, מתי יגיעו לרף, ותוכנית מוכנה לפני שזה קורה. כבוי כברירת מחדל; שום דבר לא זז בלי אישור שלך.")
            guardPlanButton.isHidden = true; return
        }
        guardHeadline.stringValue = L("Keeping at least ", "שומרים לפחות ") + bytes(s.floor) + L(" free on ", " פנויים ב־") + s.volumeName + " · " + bytes(s.free) + L(" free now", " פנויים עכשיו")
        var lines: [String] = []
        if s.free < s.floor { lines.append(L("Below the floor now.", "מתחת לרף עכשיו.")) }
        else if let days = s.forecastDays { lines.append(days < 1.5 ? L("At this pace, the floor is reached within a day or two.", "בקצב הזה מגיעים לרף תוך יום־יומיים.") : L("At this pace, the floor is reached in about \(Int(days.rounded())) days.", "בקצב הזה מגיעים לרף בעוד כ־\(Int(days.rounded())) ימים.")) }
        else { lines.append(s.historyDays < 3 ? L("Learning the pace: a forecast needs a few days of history.", "לומדים את הקצב: תחזית צריכה היסטוריה של כמה ימים.") : L("Free space is steady or growing.", "המקום הפנוי יציב או גדל.")) }
        if let growth = s.growthLine { lines.append(growth) }
        guardDetail.stringValue = lines.joined(separator: "\n")
        if let target = s.attentionTarget { guardPlanButton.title = L("Plan to free ", "תוכנית לפינוי ") + bytes(target) + "…"; guardPlanButton.isHidden = false } else { guardPlanButton.isHidden = true }
        guardPlanButton.setAccessibilityLabel(guardPlanButton.title)
    }
    @objc private func floorChosen() { onFloor?((floorPopup.selectedItem?.representedObject as? NSNumber)?.int64Value ?? 0) }
    @objc private func guardPlan() { if let target = guardState?.attentionTarget { onGuardPlan?(target) } }
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
        volumes = Volumes.mounted(); systemDataLines = []
        volumesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for volume in volumes {
            let name = NSTextField(labelWithString: volume.name + (volume.isStartup ? " · " + L("startup disk", "דיסק האתחול") : (volume.isRemovable ? " · " + L("external", "חיצוני") : "")))
            name.font = Type.bodyMedium
            let numbers = NSTextField(labelWithString: L("Used ", "בשימוש ") + bytes(volume.used) + L(" of ", " מתוך ") + bytes(volume.total) + " · " + bytes(volume.available) + L(" free", " פנויים"))
            numbers.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); numbers.textColor = .secondaryLabelColor
            let bar = ShareBar(); bar.fraction = volume.usedFraction; bar.thickness = 6; bar.heightAnchor.constraint(equalToConstant: 10).isActive = true
            bar.setAccessibilityLabel(volume.name + " " + L("used", "בשימוש"))
            let inner = NSStackView(views: [name, bar, numbers]); inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 6
            if let row = systemDataRow(for: volume) { inner.addArrangedSubview(row) }
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
    /// "System Data includes 4.9 GB purgeable space · 2 local Time Machine snapshots, newest 23 Sep", with an explanation and,
    /// when Time Machine keeps snapshots, a way to its settings. Nothing is removed from here.
    private func systemDataRow(for volume: VolumeInfo) -> NSView? {
        let snapshots = LocalSnapshots.listIfInternal(volume)
        let timeMachine = snapshots.filter(\.isTimeMachine), others = snapshots.count - timeMachine.count
        var parts: [String] = []
        if volume.purgeable >= 500_000_000 { parts.append(bytes(volume.purgeable) + L(" purgeable space macOS frees by itself", " מקום שניתן לפינוי, ש־macOS מפנה בעצמו")) }
        if let newest = timeMachine.first {
            parts.append("\(timeMachine.count) " + (timeMachine.count == 1 ? L("local Time Machine snapshot", "תמונת מצב מקומית של Time Machine") : L("local Time Machine snapshots", "תמונות מצב מקומיות של Time Machine"))
                         + L(", newest ", ", האחרונה ") + DateFormatter.localizedString(from: newest.created, dateStyle: .medium, timeStyle: .short))
        }
        if others > 0 { parts.append("\(others) " + (others == 1 ? L("other snapshot", "תמונת מצב אחרת") : L("other snapshots", "תמונות מצב אחרות"))) }
        guard !parts.isEmpty else { return nil }
        let text = L("System Data includes ", "נתוני המערכת כוללים ") + parts.joined(separator: " · ")
        systemDataLines.append(text)
        let label = NSTextField(wrappingLabelWithString: text); label.font = Type.caption; label.textColor = .secondaryLabelColor
        let info = InfoButton(L("About purgeable space and snapshots", "על מקום שניתן לפינוי ותמונות מצב"), L("Purgeable space is data macOS can remove by itself when space is needed, such as iCloud files it can download again and caches; it is already counted as free here. Local Time Machine snapshots keep recent versions of your files on this disk until they reach your backup disk; macOS removes them after about 24 hours, or sooner when space runs low. Other snapshots come from system updates or backup apps. Their sizes need administrator rights to read, so Avakasha shows only how many there are. Nothing here needs deleting by hand.", "מקום שניתן לפינוי הוא נתונים ש־macOS יכול להסיר בעצמו כשצריך מקום, כמו קובצי iCloud שאפשר להוריד שוב ומטמונים; כאן הוא כבר נספר כפנוי. תמונות מצב מקומיות של Time Machine שומרות גרסאות אחרונות של הקבצים בדיסק הזה עד שהן מגיעות לדיסק הגיבוי; macOS מסיר אותן אחרי כ־24 שעות, או מוקדם יותר כשהמקום נגמר. תמונות מצב אחרות מגיעות מעדכוני מערכת או מאפליקציות גיבוי. כדי לקרוא את הגודל שלהן צריך הרשאות מנהל, ולכן Avakasha מציגה רק כמה יש. אין צורך למחוק כאן דבר ידנית."))
        let row = NSStackView(views: [label, info]); row.spacing = 4; row.alignment = .firstBaseline
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if !timeMachine.isEmpty {
            let settings = NSButton(title: L("Time Machine Settings…", "הגדרות Time Machine…"), target: self, action: #selector(openTimeMachine)); settings.bezelStyle = .rounded; settings.controlSize = .small; settings.font = Type.caption
            row.addArrangedSubview(settings)
        }
        return row
    }
    @objc private func openTimeMachine() { onTimeMachine?() }
    @objc private func mapHome() { onMapHome?() }
    @objc private func mapDrive() { onMapDrive?() }
    @objc private func freeUp() { onFreeUp?() }
    @objc private func resume() { onContinue?() }
    @objc private func openTrash() { onOpenTrash?() }
}

/// Top-left origin, so a short page starts at the top of the scroll view.
private final class FlippedView: NSView { override var isFlipped: Bool { true } }

private extension NSLayoutConstraint {
    func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint { priority = p; return self }
}
