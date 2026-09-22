import Cocoa
import Quartz
import AVKit
import ImageIO
import SQLite3
import KeepelixCore

/// Interface language. English by default; Hebrew is an explicit choice in Keepelix › Language and applies on the next launch.
enum AppLanguage { static var current = "en"; static let supported = [("en", "English"), ("he", "עברית")] }
func L(_ en: String, _ he: String) -> String { AppLanguage.current == "he" ? he : en }
func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

final class FileTable: NSTableView {
    weak var owner: AppController?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { if !event.isARepeat {owner?.trashSelection()};return }
        if event.keyCode == 49 { if !event.isARepeat { owner?.spacePressed() }; return }
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 0 { owner?.selectAllFiles(); return }
            if event.keyCode == 6 { if event.modifierFlags.contains(.shift) {owner?.redoTrash()}else{owner?.undoTrash()};return }
        }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0, index < numberOfRows else { return nil }
        if !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        owner?.contextRow = index
        let menu = NSMenu()
        let item = NSMenuItem(title: L("Reveal this file in Finder", "הצג קובץ זה ב־Finder"), action: #selector(AppController.reveal), keyEquivalent: "")
        item.target = owner; menu.addItem(item); return menu
    }
}

final class AppController: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate, NSMenuItemValidation {
    let smokeMode = ProcessInfo.processInfo.arguments.contains("--smoke-test")
    let demoMode = ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.arguments.contains("--demo-map")
    var demoFolder: URL?
    let preferences: UserDefaults = {
        if ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.arguments.contains("--demo-map") { return UserDefaults(suiteName:"Keepelix.SyntheticDemo")! }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            guard let isolated = UserDefaults(suiteName:"Keepelix.SyntheticSmoke") else { fatalError("Cannot create synthetic test preferences") }
            return isolated
        }
        // A suite matching the app bundle identifier may return nil. Use the native app domain.
        return .standard
    }()
    var window: NSWindow!
    let table = FileTable()
    let search = NSSearchField()
    let sizeFilter = NSPopUpButton()
    let kindFilter = NSPopUpButton()
    let mode = NSPopUpButton()
    let groupPicker = NSPopUpButton()
    let agePicker = NSPopUpButton()
    let chatFilter = NSPopUpButton()
    var chatNamesButton: NSButton!
    var autoDownloadButton: NSButton!
    var chatNames: [String: ChatInfo] = [:]
    var chatNamesSource: URL?
    let sortPicker = NSPopUpButton()
    let ageHint = NSTextField(labelWithString:L("Based on last modification — age alone does not mean a file is unused.","לפי השינוי האחרון — גיל הקובץ לא מעיד בהכרח שלא השתמשת בו."))
    let status = NSTextField(labelWithString: "")
    let selectionLabel = NSTextField(labelWithString: "")
    let pathLabel = PathLink()
    let kindBadge = NSTextField(labelWithString: "")
    var videoPlayer: AVPlayerView!
    var videoHost: NSStackView!
    let playButton = NSButton()
    let muteButton = NSButton()
    let timeSlider = NSSlider()
    let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    var timeObserver: Any?
    var scrubbing = false
    var mediaInfoGeneration = 0
    let folderLabel = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    var emptyList: NSStackView!
    var emptyListTitle: NSTextField!
    var emptyListDetail: NSTextField!
    var previewPlaceholder: NSStackView!
    var primary: QLPreviewView!
    var comparison: QLPreviewView!
    var buttons: [NSButton] = []
    var locationButtons: [NSButton] = []
    var cancelButton: NSButton!
    var undoButton: NSButton!
    var extrasButton: NSButton!
    var root: URL?
    var files: [FileRecord] = []
    var shown: [FileRecord] = []
    var exact: [DuplicateGroup] = []
    var similar: [DuplicateGroup] = []
    var guards: [String: FileRecord] = [:]
    var token = CancellationToken()
    let work = DispatchQueue(label: "Keepelix.background", qos: .userInitiated)
    var busy = false
    var previewOpen = true // the preview pane is open by default; Space plays or pauses a video, otherwise toggles the preview
    var contextRow = -1
    var history = TrashHistory()
    var folderHistories: [String: TrashHistory] = [:]
    var trashBackend: TrashBackend = SystemTrash()
    var redoButton: NSButton!
    var confirmationMenuItem: NSMenuItem?
    var mapMode = false
    let mapPanel = StorageMapPanel()
    var mapRoot: URL?
    var reviewOnlyViews: [NSView] = []
    var headingLabel: NSTextField!
    var tips: NSTextField!
    var retryButton: NSButton!
    var mapButton: NSButton!
    var scroll: NSScrollView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1320,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.delegate=self; window.title="Keepelix · 0.1.0 beta 7"
        window.minSize=NSSize(width:1120,height:720);window.center();window.titlebarAppearsTransparent=true
        func label(_ text:String,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ secondary:Bool = false)->NSTextField {
            let v=NSTextField(labelWithString:text);v.font = .systemFont(ofSize:size,weight:weight);v.textColor=secondary ? .secondaryLabelColor : .labelColor;return v
        }
        func button(_ en:String,_ he:String,_ symbol:String,_ action:Selector)->NSButton {
            let b=NSButton(title:L(en,he),target:self,action:action);b.bezelStyle = .rounded
            b.font = .systemFont(ofSize:13,weight:.medium);b.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil);b.imagePosition = .imageLeading
            b.setAccessibilityLabel(L(en,he));buttons.append(b);return b
        }
        func row(_ views:[NSView],_ spacing:CGFloat = 10)->NSStackView {let s=NSStackView(views:views);s.spacing=spacing;s.alignment = .centerY;return s}
        func column(_ views:[NSView],_ spacing:CGFloat = 10)->NSStackView {let s=NSStackView(views:views);s.orientation = .vertical;s.alignment = .leading;s.spacing=spacing;return s}
        func spacer()->NSView {let v=NSView();v.setContentHuggingPriority(.init(1),for:.horizontal);v.heightAnchor.constraint(equalToConstant:1).isActive=true;return v}
        func divider()->NSBox {let v=NSBox();v.boxType = .separator;return v}
        let brandIcon=NSImageView(image:NSImage(systemSymbolName:"square.stack.3d.up.fill",accessibilityDescription:nil)!);brandIcon.contentTintColor = .controlAccentColor
        brandIcon.widthAnchor.constraint(equalToConstant:26).isActive=true;brandIcon.heightAnchor.constraint(equalToConstant:26).isActive=true
        let brand=row([brandIcon,label("Keepelix",21,.semibold)],10)
        let choose=button("Other folder or drive…","תיקייה אחרת או כונן…","folder.badge.plus",#selector(chooseFolder))
        let presets=[("WhatsApp","ווטסאפ","message.fill"),("Downloads","הורדות","arrow.down.circle.fill"),("Movies","סרטים","film.fill"),("Pictures","תמונות","photo.fill"),("Documents","מסמכים","doc.text.fill"),("Desktop","שולחן העבודה","desktopcomputer")]
        for (index,p) in presets.enumerated() {
            let b=button(p.0,p.1,p.2,#selector(chooseLocation(_:)));b.tag=index;b.isBordered=false;b.alignment = .left;b.imageHugsTitle=true
            b.contentTintColor = .labelColor;b.font = .systemFont(ofSize:14,weight:.medium)
            b.heightAnchor.constraint(equalToConstant:38).isActive=true
            b.toolTip=L("Click to scan this folder. Scanning never deletes files.","לחץ לסריקת התיקייה. הסריקה לא מוחקת קבצים.");locationButtons.append(b)
        }
        let locationList=column(locationButtons,4)
        let sidebarSpacer=NSView();sidebarSpacer.setContentHuggingPriority(.init(1),for:.vertical)
        let privacy=label(L("Local. Private. Yours.","מקומי. פרטי. שלך."),13,.medium)
        let olderButton=button("Older files","קבצים ישנים","clock",#selector(showOlderFiles));olderButton.isBordered=false;olderButton.alignment = .left;olderButton.font = .systemFont(ofSize:14,weight:.medium)
        let openBin=button("Trash","פח האשפה","trash",#selector(openTrash));openBin.isBordered=false;openBin.alignment = .left;openBin.font = .systemFont(ofSize:14,weight:.medium)
        let mapEntry=button("Storage map…","מפת אחסון…","chart.pie.fill",#selector(chooseMapFolder));mapEntry.isBordered=false;mapEntry.alignment = .left;mapEntry.font = .systemFont(ofSize:14,weight:.medium)
        mapEntry.toolTip=L("See which folders fill a folder or drive. Nothing is deleted.","ראה אילו תיקיות ממלאות תיקייה או כונן. שום דבר לא נמחק.")
        let sidebarContent=column([brand,label(L("LOCATIONS","מיקומים"),10,.semibold,true),locationList,choose,divider(),mapEntry,olderButton,openBin,sidebarSpacer,privacy],18)
        let sidebar=NSVisualEffectView();sidebar.material = .sidebar;sidebar.blendingMode = .behindWindow;sidebar.state = .followsWindowActiveState
        sidebar.addSubview(sidebarContent);sidebarContent.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([sidebar.widthAnchor.constraint(equalToConstant:216),sidebarContent.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:20),sidebarContent.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-16),sidebarContent.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:24),sidebarContent.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-24),locationList.widthAnchor.constraint(equalTo:sidebarContent.widthAnchor)])
        for b in locationButtons { b.widthAnchor.constraint(equalTo:locationList.widthAnchor).isActive=true }
        choose.font = .systemFont(ofSize:11);choose.controlSize = .small
        let resume=button("Resume","המשך סקירה","clock.arrow.circlepath",#selector(resumeFolder))
        let rescan=button("Refresh","רענן","arrow.clockwise",#selector(rescanFolder))
        headingLabel=label(L("Your files","הקבצים שלך"),23,.semibold)
        let heading=column([headingLabel],6)
        mapButton=button("Storage map","מפת אחסון","chart.pie",#selector(showStorageMap))
        mapButton.toolTip=L("See which folders take the space in this location.","ראה אילו תיקיות תופסות את המקום במיקום הזה.")
        let header=row([heading,spacer(),mapButton,resume,rescan])
        folderLabel.font = .monospacedSystemFont(ofSize:11,weight:.regular);folderLabel.textColor = .secondaryLabelColor;folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.stringValue=L("Choose a location from the sidebar to begin","בחר מיקום מהסרגל הצדדי כדי להתחיל")
        search.placeholderString=L("Search files…","חפש קבצים…");search.delegate=self;search.controlSize = .large
        search.widthAnchor.constraint(greaterThanOrEqualToConstant:210).isActive=true
        sizeFilter.addItems(withTitles:[L("All sizes","כל הגדלים"),"> 10 MB","> 100 MB","> 1 GB"]);sizeFilter.selectItem(at:0)
        kindFilter.addItem(withTitle:L("All types","כל הסוגים"));kindFilter.addItems(withTitles:FileKind.allCases.map{kind in switch kind {case .image:return L("Images","תמונות");case .video:return L("Videos","סרטונים");case .audio:return L("Audio","שמע");case .document:return L("Documents","מסמכים");case .archive:return L("Archives","ארכיונים");case .other:return L("Other","אחר")}})
        for popup in [sizeFilter,kindFilter] {popup.target=self;popup.action = #selector(applyFilters);popup.font = .systemFont(ofSize:12)}
        sizeFilter.setAccessibilityLabel(L("Minimum size","גודל מינימלי"));kindFilter.setAccessibilityLabel(L("File type","סוג קובץ"));sortPicker.setAccessibilityLabel(L("Sort order","סדר מיון"))
        mode.setAccessibilityLabel(L("Review view","תצוגת סקירה"));groupPicker.setAccessibilityLabel(L("Duplicate group","קבוצת כפילויות"));agePicker.setAccessibilityLabel(L("Age filter","סינון לפי גיל"));table.setAccessibilityLabel(L("Files","קבצים"))
        sortPicker.addItems(withTitles:[L("Largest first","הגדולים תחילה"),L("Smallest first","הקטנים תחילה"),L("Oldest first","הישנים תחילה"),L("Newest first","החדשים תחילה"),L("Name A–Z","שם א–ת"),L("Name Z–A","שם ת–א")]);sortPicker.target=self;sortPicker.action = #selector(changeSort);sortPicker.font = .systemFont(ofSize:12)
        chatFilter.addItems(withTitles:[L("All chats","כל השיחות"),L("Group chats","קבוצות"),L("Personal chats","שיחות אישיות"),L("Status & broadcasts","סטטוס ותפוצה")]);chatFilter.target=self;chatFilter.action = #selector(applyFilters);chatFilter.font = .systemFont(ofSize:12);chatFilter.isHidden=true
        chatFilter.setAccessibilityLabel(L("Chat type","סוג שיחה"));chatFilter.toolTip=L("By WhatsApp's per-chat folder names only. Chat databases are not read, so contact and group names are not shown.","לפי שמות תיקיות השיחה של ווטסאפ בלבד. מסד השיחות לא נקרא, ולכן שמות אנשי קשר וקבוצות אינם מוצגים.")
        chatNamesButton=button("Chat names…","שמות שיחות…","person.2",#selector(loadChatNamesFromButton));chatNamesButton.controlSize = .small;chatNamesButton.font = .systemFont(ofSize:11);chatNamesButton.isHidden=true
        chatNamesButton.toolTip=L("Read the chat list from WhatsApp's local database (read-only) to show group and contact names instead of folder identifiers.","קריאת רשימת השיחות ממסד הנתונים המקומי של ווטסאפ (לקריאה בלבד) כדי להציג שמות קבוצות ואנשי קשר במקום מזהי תיקיות.")
        autoDownloadButton=button("Stop auto-download…","עצירת הורדה אוטומטית…","arrow.down.circle.dotted",#selector(openWhatsAppAutoDownload));autoDownloadButton.controlSize = .small;autoDownloadButton.font = .systemFont(ofSize:11);autoDownloadButton.isHidden=true
        autoDownloadButton.toolTip=L("Opens WhatsApp and shows where its media auto-download setting is, so new media stops piling up.","פותח את ווטסאפ ומראה איפה הגדרת ההורדה האוטומטית של מדיה, כדי שמדיה חדשה תפסיק להצטבר.")
        let filters=row([search,sizeFilter,kindFilter,chatFilter,sortPicker]);search.setContentHuggingPriority(.init(1),for:.horizontal)
        mode.addItems(withTitles:[L("All files","כל הקבצים"),L("Exact duplicates","כפילויות זהות"),L("Similar images","תמונות דומות"),L("Older files","קבצים ישנים")]);mode.target=self;mode.action = #selector(modeChanged)
        groupPicker.target=self;groupPicker.action = #selector(applyFilters)
        let exactButton=button("Find duplicates","מצא כפילויות","square.on.square",#selector(findExactDuplicates))
        let similarButton=button("Compare images","השווה תמונות","photo.on.rectangle.angled",#selector(findSimilarImages))
        agePicker.addItems(withTitles:[L("Not modified in 6 months","לא שונו בחצי שנה"),L("Not modified in 1 year","לא שונו בשנה"),L("Not modified in 2 years","לא שונו בשנתיים"),L("Not modified in 5 years","לא שונו בחמש שנים")]);agePicker.selectItem(at:1);agePicker.target=self;agePicker.action = #selector(applyFilters)
        ageHint.font = .systemFont(ofSize:11);ageHint.textColor = .secondaryLabelColor
        let analysis=row([mode,groupPicker,agePicker,chatNamesButton,autoDownloadButton,spacer(),exactButton,similarButton])
        scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
        table.frame=NSRect(x:0,y:0,width:540,height:440);table.autoresizingMask=[.width];table.owner=self;table.delegate=self;table.dataSource=self
        table.setDraggingSourceOperationMask(.copy,forLocal:false) // dragging out copies; Keepelix never moves files without confirmation
        table.allowsMultipleSelection=true;table.rowHeight=38;table.intercellSpacing=NSSize(width:12,height:4);table.usesAlternatingRowBackgroundColors=false;table.style = .inset;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (id,title,width) in [("name",L("Name","שם"),240.0),("size",L("On disk","בדיסק"),80.0),("modified",L("Last modified","שינוי אחרון"),100.0)] {
            let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));c.title=title;c.width=width;c.sortDescriptorPrototype=NSSortDescriptor(key:id,ascending:id != "size");table.addTableColumn(c)
        }
        scroll.documentView=table
        primary=QLPreviewView(frame:NSRect(x:0,y:0,width:330,height:440),style:.normal);primary.autostarts=false
        comparison=QLPreviewView(frame:NSRect(x:0,y:0,width:330,height:440),style:.normal);comparison.autostarts=false
        // AVKit hides its own controls when the pointer leaves the video, so the transport bar below is drawn by Keepelix and always visible.
        videoPlayer=AVPlayerView(frame:NSRect(x:0,y:0,width:330,height:400));videoPlayer.controlsStyle = .none;videoPlayer.setAccessibilityLabel(L("Video","וידאו"))
        for (b,symbol,action,labelEn,labelHe) in [(playButton,"play.fill",#selector(togglePlayback),"Play","נגן"),(muteButton,"speaker.wave.2.fill",#selector(toggleMute),"Mute","השתק")] {
            b.bezelStyle = .rounded;b.image=NSImage(systemSymbolName:symbol,accessibilityDescription:L(labelEn,labelHe));b.imagePosition = .imageOnly;b.title="";b.target=self;b.action=action;b.setAccessibilityLabel(L(labelEn,labelHe))
        }
        timeSlider.minValue=0;timeSlider.maxValue=1;timeSlider.doubleValue=0;timeSlider.target=self;timeSlider.action = #selector(scrub(_:));timeSlider.isContinuous=true;timeSlider.setAccessibilityLabel(L("Playback position","מיקום הניגון"))
        timeSlider.setContentHuggingPriority(.init(1),for:.horizontal)
        timeLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);timeLabel.textColor = .secondaryLabelColor
        let transport=row([playButton,timeSlider,timeLabel,muteButton],8)
        videoHost=column([videoPlayer,transport],8);videoHost.isHidden=true
        videoPlayer.widthAnchor.constraint(equalTo:videoHost.widthAnchor).isActive=true;transport.widthAnchor.constraint(equalTo:videoHost.widthAnchor).isActive=true
        videoPlayer.setContentHuggingPriority(.init(1),for:.vertical)
        let previews=row([videoHost,primary,comparison],8);previews.distribution = .fillEqually
        let previewHost=NSView();previewHost.addSubview(previews);previews.translatesAutoresizingMaskIntoConstraints=false
        let previewIcon=NSImageView(image:NSImage(systemSymbolName:"doc.viewfinder",accessibilityDescription:nil)!);previewIcon.contentTintColor = .tertiaryLabelColor
        previewIcon.widthAnchor.constraint(equalToConstant:44).isActive=true;previewIcon.heightAnchor.constraint(equalToConstant:44).isActive=true
        previewPlaceholder=column([previewIcon,label(L("A closer look","מבט מקרוב"),18,.medium),label(L("Select a file and press Space","בחר קובץ ולחץ על רווח"),12,.regular,true)],12);previewPlaceholder.alignment = .centerX
        previewHost.addSubview(previewPlaceholder);previewPlaceholder.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([previews.leadingAnchor.constraint(equalTo:previewHost.leadingAnchor),previews.trailingAnchor.constraint(equalTo:previewHost.trailingAnchor),previews.topAnchor.constraint(equalTo:previewHost.topAnchor),previews.bottomAnchor.constraint(equalTo:previewHost.bottomAnchor),previewPlaceholder.centerXAnchor.constraint(equalTo:previewHost.centerXAnchor),previewPlaceholder.centerYAnchor.constraint(equalTo:previewHost.centerYAnchor)])
        let listHost=NSView();listHost.addSubview(scroll);scroll.translatesAutoresizingMaskIntoConstraints=false
        emptyListTitle=label(L("Start somewhere simple","מתחילים בתיקייה אחת"),17,.medium)
        emptyListDetail=label(L("Choose a location from the sidebar","בחר מיקום מהסרגל הצדדי"),12,.regular,true)
        let emptyIcon=NSImageView(image:NSImage(systemSymbolName:"folder.badge.magnifyingglass",accessibilityDescription:nil) ?? NSImage());emptyIcon.contentTintColor = .tertiaryLabelColor
        emptyIcon.widthAnchor.constraint(equalToConstant:40).isActive=true;emptyIcon.heightAnchor.constraint(equalToConstant:40).isActive=true
        emptyList=column([emptyIcon,emptyListTitle,emptyListDetail],12);emptyList.alignment = .centerX;emptyList.translatesAutoresizingMaskIntoConstraints=false;listHost.addSubview(emptyList)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:listHost.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:listHost.trailingAnchor),scroll.topAnchor.constraint(equalTo:listHost.topAnchor),scroll.bottomAnchor.constraint(equalTo:listHost.bottomAnchor),emptyList.centerXAnchor.constraint(equalTo:listHost.centerXAnchor),emptyList.centerYAnchor.constraint(equalTo:listHost.centerYAnchor)])
        mapPanel.translatesAutoresizingMaskIntoConstraints=false;listHost.addSubview(mapPanel,positioned:.below,relativeTo:emptyList);mapPanel.isHidden=true
        NSLayoutConstraint.activate([mapPanel.leadingAnchor.constraint(equalTo:listHost.leadingAnchor,constant:12),mapPanel.trailingAnchor.constraint(equalTo:listHost.trailingAnchor,constant:-12),mapPanel.topAnchor.constraint(equalTo:listHost.topAnchor,constant:12),mapPanel.bottomAnchor.constraint(equalTo:listHost.bottomAnchor)])
        mapPanel.onReview={[weak self] url in self?.reviewFromMap(url)}
        mapPanel.onReveal={[weak self] url in self?.revealFolder(url)}
        mapPanel.onSelectionChange={[weak self] in self?.refreshEmptyState()}
        previewHost.addSubview(mapPanel.detail);mapPanel.detail.translatesAutoresizingMaskIntoConstraints=false;mapPanel.detail.isHidden=true
        NSLayoutConstraint.activate([mapPanel.detail.leadingAnchor.constraint(equalTo:previewHost.leadingAnchor,constant:22),mapPanel.detail.trailingAnchor.constraint(equalTo:previewHost.trailingAnchor,constant:-22),mapPanel.detail.topAnchor.constraint(equalTo:previewHost.topAnchor,constant:26)])
        let split=NSSplitView();split.isVertical=true;split.dividerStyle = .thin;split.addArrangedSubview(listHost);split.addArrangedSubview(previewHost)
        listHost.widthAnchor.constraint(greaterThanOrEqualToConstant:480).isActive=true;previewHost.widthAnchor.constraint(greaterThanOrEqualToConstant:270).isActive=true
        let workspace=NSBox();workspace.boxType = .custom;workspace.borderColor = .separatorColor;workspace.borderWidth=0.5;workspace.cornerRadius=12;workspace.fillColor = .controlBackgroundColor;workspace.contentViewMargins = NSSize(width:0,height:0);workspace.contentView=split;workspace.setContentHuggingPriority(.init(1),for:.vertical)
        let all=button("Select all","בחר הכול","checkmark.circle",#selector(selectAllFiles))
        extrasButton=button("Select extra copies","בחר עותקים נוספים","checkmark.circle.badge.plus",#selector(selectExtras))
        selectionLabel.font = .systemFont(ofSize:12,weight:.medium);selectionLabel.textColor = .secondaryLabelColor
        pathLabel.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);pathLabel.setContentHuggingPriority(.init(1),for:.horizontal)
        pathLabel.setAccessibilityLabel(L("Selected file path · click to show in Finder","נתיב הקובץ הנבחר · לחיצה מציגה ב־Finder"))
        pathLabel.onOpen={[weak self] in self?.revealFocusedFile()}
        kindBadge.font = .systemFont(ofSize:10,weight:.semibold);kindBadge.wantsLayer=true;kindBadge.layer?.cornerRadius=5;kindBadge.alignment = .center
        kindBadge.setContentHuggingPriority(.required,for:.horizontal);kindBadge.setContentCompressionResistancePriority(.required,for:.horizontal)
        kindBadge.widthAnchor.constraint(greaterThanOrEqualToConstant:52).isActive=true;kindBadge.heightAnchor.constraint(equalToConstant:18).isActive=true;kindBadge.isHidden=true
        kindBadge.setAccessibilityLabel(L("File type","סוג הקובץ"))
        let selection=row([all,extrasButton,kindBadge,pathLabel,selectionLabel],10)
        let preview=button("Preview","תצוגה מקדימה","eye",#selector(togglePreview));preview.toolTip=L("Space to toggle preview","רווח לפתיחה וסגירה של תצוגה מקדימה")
        let next=button("Keep & next","השאר והמשך","arrow.right",#selector(nextFile))
        let trash=button("Move to Trash…","העבר לפח…","trash",#selector(trashSelection));trash.contentTintColor = .systemRed
        undoButton=button("Undo","שחזר","arrow.uturn.backward",#selector(undoTrash))
        redoButton=button("Redo","בצע שוב","arrow.uturn.forward",#selector(redoTrash))
        retryButton=button("Retry restore","נסה לשחזר שוב","arrow.clockwise.circle",#selector(retryRestore));retryButton.isHidden=true
        retryButton.toolTip=L("Try again to restore items whose original location was taken. Nothing is overwritten.","נסה שוב לשחזר פריטים שהמיקום המקורי שלהם נתפס. שום קובץ לא נדרס.")
        let review=row([preview,next,spacer(),retryButton,undoButton,redoButton,trash])
        cancelButton=NSButton(title:L("Cancel","בטל"),target:self,action:#selector(cancelWork));cancelButton.bezelStyle = .rounded;cancelButton.isEnabled=false
        spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false
        status.font = .systemFont(ofSize:11);status.textColor = .secondaryLabelColor;status.lineBreakMode = .byTruncatingTail
        let footer=row([spinner,status,spacer(),cancelButton],8)
        tips=label(L("Space · Play/Pause or Preview     Delete · Trash     ⌘Z · Undo","רווח · נגן/השהה או תצוגה     Delete · פח     ⌘Z · שחזור"),11,.regular,true)
        let bottom=row([tips,spacer()])
        let content=column([header,folderLabel,filters,analysis,ageHint,workspace,selection,divider(),review,footer,bottom],12)
        content.setCustomSpacing(20,after:header);content.setCustomSpacing(16,after:folderLabel)
        reviewOnlyViews=[filters,analysis,ageHint,selection,review]
        let host=NSView();host.addSubview(content);content.translatesAutoresizingMaskIntoConstraints=false
        let rootLayout=row([sidebar,host],0);rootLayout.alignment = .top;rootLayout.distribution = .fill;rootLayout.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(rootLayout)
        NSLayoutConstraint.activate([rootLayout.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),rootLayout.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),rootLayout.topAnchor.constraint(equalTo:window.contentView!.topAnchor),rootLayout.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor),sidebar.heightAnchor.constraint(equalTo:rootLayout.heightAnchor),host.widthAnchor.constraint(equalTo:rootLayout.widthAnchor,constant:-216),host.heightAnchor.constraint(equalTo:rootLayout.heightAnchor),content.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:26),content.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-26),content.topAnchor.constraint(equalTo:host.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:host.bottomAnchor,constant:-18),workspace.heightAnchor.constraint(greaterThanOrEqualToConstant:250)])
        for v in [header,folderLabel,filters,analysis,ageHint,workspace,selection,review,footer,bottom] {v.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true}
        makeMenus();modeChanged();updateEnabled();updatePreview()
        status.stringValue=L("Ready — choose a location to start.","מוכן — בחר מיקום כדי להתחיל.")
        if smokeMode {runSmokeTests();return}
        if ProcessInfo.processInfo.arguments.contains("--launch-check") {print("Packaged launch passed: production preferences and interface initialized; no scan started.");fflush(stdout);exit(0)}
        if demoMode { prepareDemo() }
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(table);NSApp.activate(ignoringOtherApps:true)
    }
    func prepareDemo() {
        window.title="Keepelix · Read-only demo";window.setContentSize(NSSize(width:1190,height:768));window.center()
        let container=FileManager.default.temporaryDirectory.appendingPathComponent("Keepelix-Demo-"+UUID().uuidString,isDirectory:true)
        let folder=container.appendingPathComponent(L("Example collection","אוסף לדוגמה"),isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);demoFolder=container
            for (index,name) in ["Coastal morning.png","Coastal morning — copy.png","Mountain light.png","Weekend palette.png"].enumerated() {
                let image=NSImage(size:NSSize(width:1200,height:900));image.lockFocus()
                NSGradient(starting:NSColor(calibratedRed:0.77,green:0.88,blue:0.89,alpha:1),ending:NSColor(calibratedRed:0.94,green:0.88,blue:0.75,alpha:1))!.draw(in:NSRect(x:0,y:0,width:1200,height:900),angle:90)
                NSColor(calibratedRed:0.99,green:0.77,blue:0.44,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:790,y:590,width:140,height:140)).fill()
                for (y,color) in [(320.0,NSColor(calibratedRed:0.19,green:0.48,blue:0.49,alpha:1)),(200.0,NSColor(calibratedRed:0.12,green:0.35,blue:0.39,alpha:1)),(50.0,NSColor(calibratedRed:0.08,green:0.25,blue:0.30,alpha:1))] {
                    color.setFill();let path=NSBezierPath();path.move(to:NSPoint(x:0,y:0));path.line(to:NSPoint(x:0,y:y+130));path.curve(to:NSPoint(x:1200,y:y+40),controlPoint1:NSPoint(x:400,y:y+340+Double(index/2)*50),controlPoint2:NSPoint(x:780,y:y-150));path.line(to:NSPoint(x:1200,y:0));path.close();path.fill()
                }
                image.unlockFocus();let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!;try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
            }
            try Data("Synthetic demo notes. These files were generated for the interface preview.".utf8).write(to:folder.appendingPathComponent("Weekend notes.txt"))
            try Self.writeSyntheticVideo(to:folder.appendingPathComponent("Harbour clip.mov"))
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1514764800)],ofItemAtPath:folder.appendingPathComponent("Weekend notes.txt").path)
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1577836800)],ofItemAtPath:folder.appendingPathComponent("Mountain light.png").path)
            for (sub,size) in [("Trips/2019 Coast",640_000),("Trips/Mountains",280_000),("Exports",120_000),("Archive/Old phone",60_000)] {
                let dir=folder.appendingPathComponent(sub,isDirectory:true);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
                try Data(repeating:0x2e,count:size).write(to:dir.appendingPathComponent("clip.bin"));try Data(repeating:0x2e,count:size/3).write(to:dir.appendingPathComponent("notes.bin"))
            }
            root=folder;files=try Scanner.scan(root:folder,token:CancellationToken()).files;sizeFilter.selectItem(at:0);applyFilters()
            folderLabel.stringValue=L("Example collection · generated demo files","אוסף לדוגמה · קבצים מלאכותיים")
            status.stringValue=L("Read-only demo · generated files only","הדגמה לקריאה בלבד · קבצים מלאכותיים בלבד")
            let featured = ProcessInfo.processInfo.arguments.contains("--demo-video") ? "Harbour clip.mov" : "Coastal morning.png"
            if let row=shown.firstIndex(where:{$0.name == featured}) {table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);previewOpen=true;updatePreview()}
            if ProcessInfo.processInfo.arguments.contains("--demo-map") {
                mapPanel.load(try StorageMapper.map(root:folder,token:CancellationToken()));mapRoot=folder;setMapMode(true)
                folderLabel.stringValue=L("Example collection · generated demo files","אוסף לדוגמה · קבצים מלאכותיים")
                status.stringValue=L("Read-only demo · generated files only","הדגמה לקריאה בלבד · קבצים מלאכותיים בלבד")
            }
        } catch {show(L("Demo unavailable","ההדגמה אינה זמינה"),error.localizedDescription)}
    }
    /// Three seconds of generated colour bands, so screenshots never need a real recording.
    static func writeSyntheticVideo(to url:URL) throws {
        let width=640,height=360,frames=72
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height])
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height])
        writer.add(input);guard writer.startWriting() else { throw writer.error ?? NSError(domain:"Keepelix",code:4) }
        writer.startSession(atSourceTime:.zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.01) }
            var buffer:CVPixelBuffer?
            guard let pool=adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess, let pixels=buffer else { throw NSError(domain:"Keepelix",code:5) }
            CVPixelBufferLockBaseAddress(pixels,[])
            if let context=CGContext(data:CVPixelBufferGetBaseAddress(pixels),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixels),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue) {
                let shift=CGFloat(frame)/CGFloat(frames)
                for band in 0..<6 {
                    context.setFillColor(CGColor(red:0.1+0.12*CGFloat(band),green:0.35+0.4*abs(sin(Double(band)+Double(shift)*6.28)),blue:0.45,alpha:1))
                    context.fill(CGRect(x:0,y:CGFloat(band)*CGFloat(height)/6,width:CGFloat(width),height:CGFloat(height)/6))
                }
                context.setFillColor(CGColor(red:0.99,green:0.77,blue:0.44,alpha:1));context.fillEllipse(in:CGRect(x:60+shift*460,y:220,width:80,height:80))
            }
            CVPixelBufferUnlockBaseAddress(pixels,[])
            adaptor.append(pixels,withPresentationTime:CMTime(value:CMTimeValue(frame),timescale:24))
        }
        input.markAsFinished();let done=DispatchSemaphore(value:0);writer.finishWriting{done.signal()};done.wait()
        if writer.status != .completed { throw writer.error ?? NSError(domain:"Keepelix",code:6) }
    }
    func applicationWillTerminate(_ notification:Notification) {
        if let demoFolder=demoFolder {try? FileManager.default.removeItem(at:demoFolder);preferences.removePersistentDomain(forName:"Keepelix.SyntheticDemo")}
    }
    func makeMenus() {
        let main = NSMenu(); let app = NSMenuItem(); main.addItem(app); let menu = NSMenu(); app.submenu = menu
        let about = NSMenuItem(title: L("About Keepelix", "אודות Keepelix"), action: #selector(aboutApp), keyEquivalent: ""); about.target = self; menu.addItem(about)
        menu.addItem(withTitle: L("Quit Keepelix","סגור Keepelix"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = L("Edit","עריכה"); main.addItem(edit); edit.submenu = NSMenu(title:L("Edit","עריכה"))
        for (title,selector,key) in [(L("Select all","בחר הכול"),#selector(selectAllCommand),"a"),(L("Undo","שחזר"),#selector(undoCommand),"z")] {
            let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target=self; edit.submenu!.addItem(item)
        }
        let redoItem=NSMenuItem(title:L("Redo","בצע שוב"),action:#selector(redoCommand),keyEquivalent:"z");redoItem.keyEquivalentModifierMask=[.command,.shift];redoItem.target=self;edit.submenu!.addItem(redoItem)
        let autoDownload=NSMenuItem(title:L("Stop WhatsApp auto-download…","עצירת הורדה אוטומטית בווטסאפ…"),action:#selector(openWhatsAppAutoDownload),keyEquivalent:"");autoDownload.target=self;menu.insertItem(autoDownload,at:1)
        menu.insertItem(.separator(),at:1)
        let confirmation=NSMenuItem(title:L("Confirm before Trash","אישור לפני העברה לפח"),action:#selector(toggleTrashConfirmation(_:)),keyEquivalent:"");confirmation.target=self;confirmation.state=preferences.bool(forKey:"skipTrashConfirmation") ? .off : .on;menu.insertItem(confirmation,at:2);confirmationMenuItem=confirmation
        // Standard text editing remains available in the search field.
        edit.submenu!.addItem(withTitle:L("Copy","העתק"),action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.submenu!.addItem(withTitle:L("Paste","הדבק"),action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        let language=NSMenuItem(title:L("Language","שפה"),action:nil,keyEquivalent:"");let languageMenu=NSMenu(title:L("Language","שפה"))
        for (code,title) in AppLanguage.supported {
            let item=NSMenuItem(title:title,action:#selector(chooseLanguage(_:)),keyEquivalent:"");item.target=self;item.representedObject=code
            item.state = AppLanguage.current == code ? .on : .off;languageMenu.addItem(item)
        }
        language.submenu=languageMenu;menu.insertItem(language,at:3);languageMenuItem=language
        NSApp.mainMenu=main
    }
    var languageMenuItem:NSMenuItem?
    /// Stores the choice for this app only (its own preferences domain) so system panels and layout direction follow on the next launch.
    @objc func chooseLanguage(_ sender:NSMenuItem) {
        guard let code=sender.representedObject as? String, AppLanguage.supported.contains(where:{$0.0 == code}) else { return }
        preferences.set(code,forKey:"language");preferences.set([code],forKey:"AppleLanguages")
        // AppKit mirrors the whole window (sidebar, tables, buttons) from this key at launch; Hebrew is right-to-left.
        preferences.set(code == "he",forKey:"AppleTextDirection")
        sender.menu?.items.forEach{$0.state = ($0.representedObject as? String) == code ? .on : .off}
        guard code != AppLanguage.current, !smokeMode else { return }
        let hebrew = code == "he"
        let a=NSAlert();a.messageText = hebrew ? "Keepelix תוצג בעברית בפתיחה הבאה" : "Keepelix will open in English next time"
        a.informativeText = hebrew ? "הפעל מחדש כדי להחיל את השפה וכיוון הממשק. פעולה שרצה כרגע צריכה להסתיים קודם." : "Relaunch to apply the language and layout direction. A running operation must finish first."
        a.addButton(withTitle: hebrew ? "הפעל מחדש עכשיו" : "Relaunch now");a.addButton(withTitle: hebrew ? "אחר כך" : "Later")
        if a.runModal() == .alertFirstButtonReturn { relaunch() }
    }
    func relaunch() {
        guard !busy else { return }
        let url=Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return } // running from a bare executable: quit and start again by hand
        let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true
        NSWorkspace.shared.openApplication(at:url,configuration:configuration){ _,_ in DispatchQueue.main.async{ NSApp.terminate(nil) } }
    }
    @objc func undoCommand() {
        if let editor=window.firstResponder as? NSTextView {editor.undoManager?.undo()} else {undoTrash()}
    }
    @objc func redoCommand() {
        if let editor=window.firstResponder as? NSTextView {editor.undoManager?.redo()} else {redoTrash()}
    }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(undoCommand) {
            if let editor=window.firstResponder as? NSTextView {return editor.undoManager?.canUndo ?? false}
            return !busy && !demoMode && !mapMode && history.canUndo
        }
        if item.action == #selector(redoCommand) {
            if let editor=window.firstResponder as? NSTextView {return editor.undoManager?.canRedo ?? false}
            return !busy && !demoMode && !mapMode && history.canRedo
        }
        return true
    }
    @objc func aboutApp() { show(L("Keepelix 0.1.0 beta 7", "Keepelix 0.1.0 בטא 7"), "© 2026 Daniel Siman Tov\n" + L("Contact: ","יצירת קשר: ") + "daniel.simisi@gmail.com\n\n" + L("Offline file review. MIT license. Not affiliated with WhatsApp or Meta. Undo is available for this app session; Finder Trash remains available afterward.","סקירת קבצים מקומית. רישיון MIT. ללא שיוך ל־WhatsApp או Meta. שחזור באפליקציה זמין במהלך ההפעלה הנוכחית; הפח של Finder נשאר זמין לאחר מכן.")) }
    func show(_ title: String, _ detail: String) {
        if smokeMode { print("Alert suppressed in smoke mode: \(title) — \(detail)"); return }
        let a=NSAlert();a.messageText=title;a.informativeText=detail;a.runModal()
    }
    @objc func openTrash() {
        let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash",isDirectory:true)
        if !NSWorkspace.shared.open(url) { show(L("Cannot open Trash","לא ניתן לפתוח את הפח"),L("Open Trash from the Dock.","אפשר לפתוח את פח האשפה מה־Dock.")) }
    }
    @objc func chooseFolder() {
        guard !busy else { return }; let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.allowsMultipleSelection=false
        p.message=L("Choose only the folder you want to review. No files are uploaded.","בחר רק את התיקייה שתרצה לבדוק. שום קובץ לא מועלה לרשת.")
        if p.runModal() == .OK, let u=p.url { startScan(u) }
    }
    static func presetURL(_ index:Int, home:URL) -> URL? {
        let paths=["Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media", "Downloads", "Movies", "Pictures", "Documents", "Desktop"]
        guard paths.indices.contains(index) else { return nil }
        return home.appendingPathComponent(paths[index],isDirectory:true)
    }
    func locationURL(_ tag:Int) -> URL? {
        guard let suggested=Self.presetURL(tag,home:FileManager.default.homeDirectoryForCurrentUser) else { return nil }
        if tag == 0, let saved=preferences.string(forKey:"whatsAppMediaFolder") { return URL(fileURLWithPath:saved,isDirectory:true) }
        return suggested
    }
    /// A location that is already loaded is shown again instead of scanned again; Refresh rescans explicitly.
    func isCurrentRoot(_ url:URL) -> Bool {
        guard let current=root, let resolved=try? FileSafety.root(url) else { return false }
        return resolved.path == current.path
    }
    func updateLocationHighlight() {
        let active = (mapMode ? mapRoot : root)?.path
        for b in locationButtons {
            let matches = active != nil && locationURL(b.tag).flatMap{ try? FileSafety.root($0) }?.path == active
            b.wantsLayer=true;b.layer?.cornerRadius=7
            b.layer?.backgroundColor = matches ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : nil
            b.contentTintColor = matches ? .controlAccentColor : .labelColor
            b.setAccessibilityValue(matches ? L("Current location","המיקום הנוכחי") : "")
        }
    }
    @objc func chooseLocation(_ sender:NSButton) {
        guard !busy, let candidate=locationURL(sender.tag) else { return }
        if isCurrentRoot(candidate) { if mapMode { setMapMode(false) };window.makeFirstResponder(table);return }
        var directory:ObjCBool=false
        if FileManager.default.fileExists(atPath:candidate.path,isDirectory:&directory),directory.boolValue {
            startScan(candidate);return
        }
        let picker=NSOpenPanel();picker.canChooseDirectories=true;picker.canChooseFiles=false;picker.allowsMultipleSelection=false
        picker.title=L("Locate ","בחר מיקום עבור ")+sender.title
        picker.message = sender.tag == 0 ? L("WhatsApp media was not found or is not accessible. Choose its Media folder. No account connection is needed; chat databases are skipped.","תיקיית המדיה של ווטסאפ לא נמצאה או אינה נגישה. בחר את תיקיית Media שלה. לא נדרש חיבור לחשבון; מסדי נתונים של שיחות אינם נסרקים.") : L("This folder was not found or is not accessible. Choose its location.","התיקייה לא נמצאה או אינה נגישה. בחר את המיקום שלה.")
        if picker.runModal() == .OK,let url=picker.url {
            if sender.tag == 0 { preferences.set(url.path,forKey:"whatsAppMediaFolder") }
            startScan(url)
        }
    }
    @objc func resumeFolder() {
        guard !busy else { return }
        if let path=preferences.string(forKey:"lastFolder") { startScan(URL(fileURLWithPath:path)) } else { chooseFolder() }
    }
    @objc func rescanFolder() {
        guard !busy else { return }
        if mapMode { if let target=mapRoot { startMap(target) } } else if let root=root { startScan(root) }
    }
    @objc func cancelWork() { token.cancel();status.stringValue=L("Cancelling…","מבטל…") }
    func setBusy(_ value: Bool) { busy=value;updateEnabled();if value{spinner.startAnimation(nil)}else{spinner.stopAnimation(nil)} }
    func updateEnabled() {
        buttons.forEach { b in
            let requiresSelection: Set<Selector> = [#selector(togglePreview),#selector(nextFile),#selector(trashSelection),#selector(deselect)]
            let requiresFiles: Set<Selector> = [#selector(selectAllFiles),#selector(findExactDuplicates),#selector(findSimilarImages)]
            b.isEnabled = !busy
            if let action=b.action, requiresSelection.contains(action) { b.isEnabled = !busy && !selectedFiles.isEmpty }
            if let action=b.action, requiresFiles.contains(action) { b.isEnabled = !busy && !files.isEmpty }
            if b.action == #selector(showOlderFiles) { b.isEnabled = !busy && root != nil }
            if b.action == #selector(rescanFolder) { b.isEnabled = !busy && (mapMode ? mapRoot != nil : root != nil) }
            if b.action == #selector(showStorageMap) { b.isEnabled = !busy && (mapMode ? root != nil : (root != nil || mapPanel.result != nil)) }
            if b.action == #selector(retryRestore) { b.isEnabled = !busy && !demoMode && !mapMode && history.blockedCount > 0 }
            if demoMode && (b.action == #selector(trashSelection) || b.action == #selector(undoTrash) || b.action == #selector(redoTrash)) { b.isEnabled=false }
            if b.action == #selector(resumeFolder) { b.isEnabled = !busy && preferences.string(forKey:"lastFolder") != nil }
        }; cancelButton?.isEnabled=busy
        [sizeFilter,kindFilter,mode,groupPicker,agePicker,sortPicker,chatFilter].forEach{$0.isEnabled = !busy};search.isEnabled = !busy;chatNamesButton?.isEnabled = !busy
        undoButton?.isEnabled = !busy && !demoMode && !mapMode && history.canUndo
        redoButton?.isEnabled = !busy && !demoMode && !mapMode && history.canRedo
        if !busy { retryButton?.isHidden = history.blockedCount == 0 } // history is only touched by the work queue while busy
        mapPanel.setEnabled(!busy)
        extrasButton?.isEnabled = !busy && mode.indexOfSelectedItem == 1 && !exact.isEmpty
        extrasButton?.isHidden = mode.indexOfSelectedItem != 1
    }
    func activateRoot(_ selectedRoot: URL) {
        if let root=root {folderHistories[root.path]=history}
        history=folderHistories[selectedRoot.path] ?? TrashHistory()
        root=selectedRoot
    }
    func startScan(_ url: URL) {
        guard !busy else{return}
        do { activateRoot(try FileSafety.root(url)) } catch { show(L("Cannot scan this folder","לא ניתן לסרוק את התיקייה"),error.localizedDescription);return }
        if mapMode { setMapMode(false) }
        let selectedRoot=root!;preferences.set(selectedRoot.path,forKey:"lastFolder");folderLabel.stringValue=selectedRoot.path;updateLocationHighlight()
        if chatNamesSource != ChatDirectory.databaseURL(near:selectedRoot) { chatNames=[:];chatNamesSource=nil }
        chatFilter.removeAllItems()
        primary.previewItem=nil;comparison.previewItem=nil;stopVideo();files=[];exact=[];similar=[];guards=[:];mode.selectItem(at:0);modeChanged()
        token=CancellationToken();let jobToken=token;setBusy(true);refreshEmptyState();status.stringValue=L("Scanning file metadata…","סורק שמות וגדלים…")
        work.async {
            do {
                let result=try Scanner.scan(root:selectedRoot,token:jobToken){count in DispatchQueue.main.async{self.status.stringValue=L("Scanning: ","נסרקו: ")+String(count)}}
                DispatchQueue.main.async {
                    self.files=result.files;self.setBusy(false);self.applyFilters()
                    self.status.stringValue="\(result.files.count) "+L("files","קבצים")+" · \(result.skipped) "+L("skipped","דולגו") + (result.cancelled ? " · "+L("Cancelled · partial results","בוטל · תוצאות חלקיות") : "")
                    if let last=self.preferences.string(forKey:"lastFile"),let i=self.shown.firstIndex(where:{$0.id==last}) {self.table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);self.table.scrollRowToVisible(i)}
                }
            } catch {DispatchQueue.main.async{self.setBusy(false);self.show(L("Scan failed","הסריקה נכשלה"),error.localizedDescription)}}
        }
    }
    // MARK: Storage map
    func setMapMode(_ on:Bool) {
        mapMode=on
        reviewOnlyViews.forEach{$0.isHidden=on}
        scroll.isHidden=on;mapPanel.isHidden = !on;mapPanel.detail.isHidden = !on
        headingLabel.stringValue = on ? L("Where is the space?","איפה המקום?") : L("Your files","הקבצים שלך")
        tips.stringValue = on ? L("Return · Open folder     ⌘↑ · Up     Review files here · Switch to file review","Return · פתיחת תיקייה     ⌘↑ · למעלה     סקור קבצים כאן · מעבר לסקירת קבצים") : L("Space · Play/Pause or Preview     Delete · Trash     ⌘Z · Undo","רווח · נגן/השהה או תצוגה     Delete · פח     ⌘Z · שחזור")
        mapButton.title = on ? L("Back to files","חזרה לקבצים") : L("Storage map","מפת אחסון")
        mapButton.image = NSImage(systemSymbolName: on ? "list.bullet" : "chart.pie",accessibilityDescription:nil);mapButton.setAccessibilityLabel(mapButton.title)
        if on {
            if !demoMode { folderLabel.stringValue = mapRoot?.path ?? folderLabel.stringValue }
            primary.previewItem=nil;comparison.previewItem=nil;stopVideo();previewPlaceholder.isHidden=true;primary.isHidden=true;comparison.isHidden=true
        } else {
            if !demoMode { folderLabel.stringValue = root?.path ?? L("Choose a location from the sidebar to begin","בחר מיקום מהסרגל הצדדי כדי להתחיל") }
            ageHint.isHidden = mode.indexOfSelectedItem != 3;comparison.isHidden = !(mode.indexOfSelectedItem == 1 || mode.indexOfSelectedItem == 2);updateSelection()
        }
        refreshEmptyState();updateEnabled();updateLocationHighlight()
    }
    func refreshEmptyState() {
        if mapMode {
            emptyList?.isHidden = !mapPanel.isEmpty
            emptyListTitle?.stringValue = busy ? L("Measuring folders…","מודד תיקיות…") : L("See where the space goes","לראות לאן הולך המקום")
            emptyListDetail?.stringValue = busy ? L("A large drive can take a while. Cancel keeps partial results.","כונן גדול עשוי לקחת זמן. ביטול שומר תוצאות חלקיות.") : L("Choose Storage map in the sidebar, then a folder or drive","בחר מפת אחסון בסרגל הצדדי, ואז תיקייה או כונן")
        } else {
            emptyList?.isHidden = !shown.isEmpty
            emptyListTitle?.stringValue = busy ? L("Scanning…","סורק…") : (root == nil ? L("Start somewhere simple","מתחילים בתיקייה אחת") : L("No matching files","אין קבצים מתאימים"))
            emptyListDetail?.stringValue = busy ? L("Reading names and sizes only. Cancel keeps what was found.","קורא רק שמות וגדלים. ביטול שומר את מה שנמצא.") : (root == nil ? L("Choose a location from the sidebar","בחר מיקום מהסרגל הצדדי") : L("Try another filter or location","נסה מסנן אחר או מיקום אחר"))
        }
    }
    @objc func chooseMapFolder() {
        guard !busy else { return }
        let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.allowsMultipleSelection=false
        p.directoryURL=FileManager.default.homeDirectoryForCurrentUser;p.prompt=L("Map","מפה")
        p.message=L("Choose the folder or drive to map. Sizes are measured on this Mac; nothing is moved or uploaded.","בחר תיקייה או כונן למיפוי. הגדלים נמדדים במק הזה; שום דבר לא מועבר או מועלה.")
        if p.runModal() == .OK, let u=p.url { startMap(u) }
    }
    @objc func showStorageMap() {
        guard !busy else { return }
        if mapMode { if root != nil { setMapMode(false);window.makeFirstResponder(table) };return }
        guard let current=root else { chooseMapFolder();return }
        if mapPanel.result != nil, mapPanel.reveal(folder:current) { mapRoot=mapPanel.result?.root.url;setMapMode(true);window.makeFirstResponder(mapPanel.table);return }
        startMap(current)
    }
    func startMap(_ url:URL) {
        guard !busy else { return }
        let target:URL
        do { target=try FileSafety.root(url) } catch {
            let detail = url.standardizedFileURL.path == "/" ? L("The whole startup disk cannot be mapped. Choose your home folder, a folder inside it, or an external drive.","אי אפשר למפות את כל דיסק ההפעלה. בחר את תיקיית הבית, תיקייה בתוכה או כונן חיצוני.") : error.localizedDescription
            show(L("Cannot map this folder","לא ניתן למפות את התיקייה"),detail);return
        }
        mapRoot=target;mapPanel.load(nil);setMapMode(true);folderLabel.stringValue=target.path;updateLocationHighlight()
        token=CancellationToken();let jobToken=token;setBusy(true);refreshEmptyState()
        status.stringValue=L("Measuring folders…","מודד תיקיות…")
        work.async {
            do {
                var lastUpdate=Date.distantPast
                let result=try StorageMapper.map(root:target,token:jobToken){entries,total in
                    guard Date().timeIntervalSince(lastUpdate)>0.2 else {return};lastUpdate=Date()
                    DispatchQueue.main.async{self.status.stringValue=L("Measuring: ","מודד: ")+"\(entries) "+L("items","פריטים")+" · "+bytes(total)}
                }
                DispatchQueue.main.async {
                    self.setBusy(false);self.mapPanel.load(result);self.refreshEmptyState()
                    self.status.stringValue=self.mapSummary(result);self.window.makeFirstResponder(self.mapPanel.table)
                }
            } catch {DispatchQueue.main.async{self.setBusy(false);self.refreshEmptyState();self.show(L("Cannot map this folder","לא ניתן למפות את התיקייה"),error.localizedDescription)}}
        }
    }
    func mapSummary(_ result:StorageMapResult)->String {
        let r=result.root
        var parts=[bytes(r.bytes)+" · \(r.files) "+L("files","קבצים")+" · \(r.directories) "+L("folders","תיקיות")]
        if r.inaccessible>0 {parts.append("\(r.inaccessible) "+L("not accessible","לא נגישים"))}
        if r.notDownloaded>0 {parts.append("\(r.notDownloaded) "+L("not downloaded","לא הורדו"))}
        if r.otherVolumes>0 {parts.append("\(r.otherVolumes) "+L("other volumes skipped","כוננים אחרים דולגו"))}
        if result.sharedFiles>0 {parts.append("\(result.sharedFiles) "+L("hard links counted once","קישורים קשיחים נספרו פעם אחת"))}
        if result.cancelled {parts.append(L("Cancelled · partial results","בוטל · תוצאות חלקיות"))}
        return parts.joined(separator:" · ")
    }
    func reviewFromMap(_ url:URL) { guard !busy else{return};startScan(url) }
    func revealFolder(_ url:URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    var currentGroups: [DuplicateGroup] {mode.indexOfSelectedItem == 1 ? exact : (mode.indexOfSelectedItem == 2 ? similar : [])}
    @objc func modeChanged() {
        groupPicker.removeAllItems();groupPicker.addItem(withTitle:L("All groups","כל הקבוצות"))
        for (i,g) in currentGroups.enumerated(){groupPicker.addItem(withTitle:"\(i+1) · \(g.members.count) files")}
        let duplicates = mode.indexOfSelectedItem == 1 || mode.indexOfSelectedItem == 2
        groupPicker.isHidden = !duplicates;comparison.isHidden = !duplicates
        agePicker.isHidden = mode.indexOfSelectedItem != 3;ageHint.isHidden = mode.indexOfSelectedItem != 3
        table.deselectAll(nil);guards=[:];applyFilters();updateEnabled()
    }
    @objc func applyFilters() {
        let old=Set(selectedFiles.map(\.id));let threshold:[Int64]=[0,10_000_000,100_000_000,1_000_000_000]
        let groupIndex=groupPicker.indexOfSelectedItem-1
        let groups=currentGroups
        let members:Set<String>? = (mode.indexOfSelectedItem==0 || mode.indexOfSelectedItem==3) ? nil : Set((groupIndex>=0 && groupIndex<groups.count ? groups[groupIndex].members : groups.flatMap(\.members)).map(\.id))
        let query=search.stringValue.lowercased()
        let months=[6,12,24,60][max(0,agePicker.indexOfSelectedItem)]
        let cutoff=Calendar.current.date(byAdding:.month,value:-months,to:Date()) ?? .distantPast
        var candidates=mode.indexOfSelectedItem == 3 ? ReviewQuery.older(files,than:cutoff) : files
        chatFilter.isHidden = !files.contains{ ChatFolders.kind(of:$0.url) != nil }
        chatNamesButton?.isHidden = chatFilter.isHidden || chatNames.isEmpty == false || root.flatMap{ ChatDirectory.databaseURL(near:$0) } == nil
        autoDownloadButton?.isHidden = chatFilter.isHidden
        if chatFilter.numberOfItems <= 4 { rebuildChatFilter() }
        if !chatFilter.isHidden {
            if let identifier=chatFilter.selectedItem?.representedObject as? String { candidates=candidates.filter{ ChatDirectory.identifier(of:$0.url) == identifier } }
            else if chatFilter.indexOfSelectedItem > 0 && chatFilter.indexOfSelectedItem <= ChatKind.allCases.count { candidates=ChatFolders.filter(candidates,kind:ChatKind.allCases[chatFilter.indexOfSelectedItem-1]) }
        }
        shown=candidates.filter { f in
            f.allocatedBytes>=threshold[max(0,sizeFilter.indexOfSelectedItem)] && (query.isEmpty || f.url.path.lowercased().contains(query)) &&
            (kindFilter.indexOfSelectedItem==0 || f.kind == FileKind.allCases[kindFilter.indexOfSelectedItem-1]) && (members==nil || members!.contains(f.id))
        }
        shown=ReviewQuery.sorted(shown,by:ReviewSort(rawValue:sortPicker.indexOfSelectedItem) ?? .largest)
        table.reloadData();table.selectRowIndexes(IndexSet(shown.indices.filter{old.contains(shown[$0].id)}),byExtendingSelection:false)
        updateSelection()
    }
    /// Kinds first, then every chat present in the scan, largest first, named when the chat list was loaded.
    func rebuildChatFilter() {
        let selected=chatFilter.selectedItem?.representedObject as? String ?? (chatFilter.indexOfSelectedItem > 0 && chatFilter.indexOfSelectedItem <= ChatKind.allCases.count ? "kind:\(chatFilter.indexOfSelectedItem)" : "")
        var totals:[String:Int64]=[:]
        for f in files { if let id=ChatDirectory.identifier(of:f.url) { totals[id,default:0] += f.allocatedBytes } }
        chatFilter.removeAllItems();chatFilter.addItems(withTitles:[L("All chats","כל השיחות"),L("Group chats","קבוצות"),L("Personal chats","שיחות אישיות"),L("Status & broadcasts","סטטוס ותפוצה")])
        guard !totals.isEmpty else { return }
        chatFilter.menu?.addItem(.separator())
        for (id,total) in totals.sorted(by:{ $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }).prefix(400) {
            let item=NSMenuItem(title:(chatNames[id]?.name ?? id)+" · "+bytes(total),action:nil,keyEquivalent:"");item.representedObject=id
            item.image=NSImage(systemSymbolName:chatNames[id]?.kind == .group || ChatFolders.kind(of:URL(fileURLWithPath:"/"+id+"/x")) == .group ? "person.3" : "person",accessibilityDescription:nil)
            chatFilter.menu?.addItem(item)
        }
        if let index=chatFilter.itemArray.firstIndex(where:{ ($0.representedObject as? String) == selected }) { chatFilter.selectItem(at:index) }
        else if selected.hasPrefix("kind:"), let k=Int(selected.dropFirst(5)) { chatFilter.selectItem(at:k) } else { chatFilter.selectItem(at:0) }
    }
    @objc func loadChatNamesFromButton() { loadChatNames(confirmed:false) }
    /// WhatsApp for Mac has no public deep link to a settings pane, so this opens the app and spells out the path.
    @objc func openWhatsAppAutoDownload() {
        let steps=L("In WhatsApp: Settings (⌘,) › Storage (or Storage and Data) › Media auto-download. Turn off Photos, Audio, Videos and Documents you do not want downloaded automatically. Exact names vary by WhatsApp version.","בווטסאפ: Settings (⌘,) ‹ Storage (או Storage and Data) ‹ Media auto-download. כבה תמונות, שמע, וידאו ומסמכים שאינך רוצה שיירדו אוטומטית. השמות המדויקים משתנים בין גרסאות ווטסאפ.")
        guard !smokeMode else { status.stringValue=steps;return }
        let a=NSAlert();a.messageText=L("Stop WhatsApp auto-download","עצירת הורדה אוטומטית בווטסאפ");a.informativeText=steps
        a.addButton(withTitle:L("Open WhatsApp","פתח את ווטסאפ"));a.addButton(withTitle:L("Close","סגור"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if let app=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"net.whatsapp.WhatsApp") {
            NSWorkspace.shared.openApplication(at:app,configuration:NSWorkspace.OpenConfiguration()){ _,error in if let error=error { DispatchQueue.main.async{ self.show(L("Cannot open WhatsApp","לא ניתן לפתוח את ווטסאפ"),error.localizedDescription) } } }
        } else { show(L("WhatsApp not found","ווטסאפ לא נמצא"),L("WhatsApp for Mac is not installed here. Change the setting in WhatsApp on the device you use.","ווטסאפ למק לא מותקן כאן. שנה את ההגדרה בווטסאפ במכשיר שבו אתה משתמש.")) }
    }
    /// Explicit, read-only read of WhatsApp's chat list (identifier, name, type). Never messages; nothing is stored.
    func loadChatNames(confirmed:Bool) {
        guard !busy, let root=root, let database=ChatDirectory.databaseURL(near:root) else { return }
        if !confirmed && !smokeMode {
            let a=NSAlert();a.messageText=L("Show chat names?","להציג שמות שיחות?")
            a.informativeText=L("Keepelix will open WhatsApp's local chat list read-only and read only each chat's identifier, display name and type, to label folders. Messages, contacts and media references are not read. Nothing is stored or sent anywhere. Close WhatsApp first if it reports the list as busy.","Keepelix תפתח את רשימת השיחות המקומית של ווטסאפ לקריאה בלבד ותקרא רק מזהה, שם תצוגה וסוג של כל שיחה, כדי לתייג תיקיות. הודעות, אנשי קשר והפניות למדיה לא נקראים. שום דבר לא נשמר ולא נשלח. אם הרשימה מדווחת כתפוסה, סגור את ווטסאפ קודם.")
            a.addButton(withTitle:L("Show names","הצג שמות"));a.addButton(withTitle:L("Cancel","בטל"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        setBusy(true);cancelButton.isEnabled=false;status.stringValue=L("Reading chat list…","קורא רשימת שיחות…")
        work.async {
            let result=Result{ try ChatDirectory.load(from:database) }
            DispatchQueue.main.async {
                self.setBusy(false)
                switch result {
                case .success(let chats):
                    self.chatNames=chats;self.chatNamesSource=database;self.chatNamesButton.isHidden=true;self.mapPanel.chatNames=chats;self.rebuildChatFilter();self.applyFilters()
                    self.status.stringValue="\(chats.count) "+L("chats named · read-only, nothing stored","שיחות עם שם · לקריאה בלבד, לא נשמר")
                case .failure(let error): self.show(L("Chat names unavailable","שמות שיחות אינם זמינים"),error.localizedDescription)
                }
            }
        }
    }
    @objc func showOlderFiles() { guard !busy,root != nil else{return};if mapMode {setMapMode(false)};mode.selectItem(at:3);modeChanged();window.makeFirstResponder(table) }
    @objc func changeSort() {
        guard !busy else{return}
        let order=ReviewSort(rawValue:sortPicker.indexOfSelectedItem) ?? .largest
        let key = (order == .name || order == .nameDescending) ? "name" : ((order == .oldest || order == .newest) ? "modified" : "size")
        table.sortDescriptors=[NSSortDescriptor(key:key,ascending:order == .name || order == .oldest || order == .smallest)]
        applyFilters()
    }
    func tableView(_ tableView:NSTableView,sortDescriptorsDidChange oldDescriptors:[NSSortDescriptor]) {
        guard !busy,let descriptor=tableView.sortDescriptors.first else{return}
        let order:ReviewSort
        switch descriptor.key {case "modified":order=descriptor.ascending ? .oldest : .newest;case "size":order=descriptor.ascending ? .smallest : .largest;default:order = descriptor.ascending ? .name : .nameDescending}
        sortPicker.selectItem(at:order.rawValue);applyFilters()
    }
    func controlTextDidChange(_ obj: Notification){applyFilters()}
    var selectedFiles:[FileRecord]{table.selectedRowIndexes.compactMap{$0<shown.count ? shown[$0]:nil}}
    /// The row most recently added to the selection (Shift+↓, Shift+↑, ⌘-click), so the preview follows what you just reached.
    var focusRow = -1
    var previousSelection = IndexSet()
    var focusedFile:FileRecord? {
        let rows=table.selectedRowIndexes
        if rows.contains(focusRow), focusRow<shown.count { return shown[focusRow] }
        return selectedFiles.first
    }
    func trackFocus() {
        let rows=table.selectedRowIndexes;let added=rows.subtracting(previousSelection);let removed=previousSelection.subtracting(rows)
        if let last=added.last, let first=added.first { focusRow = last > (previousSelection.last ?? -1) ? last : first }
        else if !removed.isEmpty, let hi=rows.last, let lo=rows.first { focusRow = (removed.first ?? 0) > hi ? hi : lo }
        else if !rows.contains(focusRow) { focusRow = rows.first ?? -1 }
        previousSelection=rows
    }
    func numberOfRows(in tableView:NSTableView)->Int{shown.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        let f=shown[row];let text:String
        switch tableColumn?.identifier.rawValue{case "size":text=bytes(f.allocatedBytes);case "modified":text=DateFormatter.localizedString(from:Date(timeIntervalSince1970:Double(f.identity.modifiedSeconds)),dateStyle:.short,timeStyle:.none);default:text=f.name}
        let v=NSTextField(labelWithString:text);v.lineBreakMode = .byTruncatingMiddle;v.toolTip=f.url.path
        v.font = .systemFont(ofSize:13,weight:tableColumn?.identifier.rawValue == "name" ? .medium : .regular)
        if tableColumn?.identifier.rawValue == "size" { v.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular);v.textColor = .secondaryLabelColor }
        if tableColumn?.identifier.rawValue == "modified" { v.font = .systemFont(ofSize:12);v.textColor = .secondaryLabelColor }
        guard tableColumn?.identifier.rawValue == "name" else { return v }
        let symbols:[FileKind:String]=[.image:"photo",.video:"film",.audio:"waveform",.document:"doc.text",.archive:"archivebox",.other:"doc"]
        let icon=NSImageView(image:NSImage(systemSymbolName:symbols[f.kind] ?? "doc",accessibilityDescription:Self.kindTitle(f.kind))!);icon.contentTintColor = Self.kindColor(f.kind)
        icon.widthAnchor.constraint(equalToConstant:18).isActive=true;icon.heightAnchor.constraint(equalToConstant:18).isActive=true
        let cell=NSStackView(views:[icon,v]);cell.spacing=9;cell.toolTip=f.url.path;return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification){trackFocus();updateSelection()}
    /// Drag one or more rows to Finder, WhatsApp or any other window as file URLs.
    func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting? {
        guard !busy,!mapMode,row<shown.count,let root=root,(try? FileSafety.validate(shown[row],root:root)) != nil else { return nil }
        return shown[row].url as NSURL
    }
    func tableView(_ tableView:NSTableView,draggingSession session:NSDraggingSession,willBeginAt screenPoint:NSPoint,forRowIndexes rowIndexes:IndexSet) { session.draggingFormation = .stack }
    func updateSelection(){
        let chosen=selectedFiles
        if chosen.isEmpty { selectionLabel.stringValue="\(shown.count) " + L("items","פריטים") }
        else { selectionLabel.stringValue=L("Item ","פריט ")+"\((table.selectedRowIndexes.contains(focusRow) ? focusRow : table.selectedRowIndexes.first!)+1)"+L(" of ","  מתוך ")+"\(shown.count) · \(chosen.count) "+L("selected","נבחרו")+" · "+bytes(chosen.reduce(0){$0+$1.allocatedBytes}) }
        let focused=focusedFile
        pathLabel.stringValue = focused.map{ displayPath($0.url) } ?? "";pathLabel.toolTip = focused?.url.path
        updateKindBadge(focused)
        refreshEmptyState()
        if let f=chosen.first{preferences.set(f.id,forKey:"lastFile")};updatePreview();updateEnabled()
    }
    static func kindTitle(_ kind:FileKind) -> String {
        switch kind {case .image:return L("Image","תמונה");case .video:return L("Video","וידאו");case .audio:return L("Audio","שמע");case .document:return L("Document","מסמך");case .archive:return L("Archive","ארכיון");case .other:return L("File","קובץ")}
    }
    static func kindColor(_ kind:FileKind) -> NSColor {
        switch kind {case .video:return .systemPurple;case .image:return .systemTeal;case .audio:return .systemOrange;default:return .secondaryLabelColor}
    }
    /// Shows the type at a glance; adds pixel size for images and duration for videos (metadata only, read locally).
    func updateKindBadge(_ file:FileRecord?) {
        mediaInfoGeneration += 1;let generation=mediaInfoGeneration
        guard let f=file else { kindBadge.isHidden=true;return }
        func show(_ text:String) { kindBadge.stringValue="  "+text+"  ";kindBadge.textColor=Self.kindColor(f.kind);kindBadge.layer?.backgroundColor=Self.kindColor(f.kind).withAlphaComponent(0.16).cgColor;kindBadge.isHidden=false }
        show(Self.kindTitle(f.kind).uppercased())
        if f.kind == .image, let source=CGImageSourceCreateWithURL(f.url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
           let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
           let w=properties[kCGImagePropertyPixelWidth] as? NSNumber,let h=properties[kCGImagePropertyPixelHeight] as? NSNumber {
            show(Self.kindTitle(f.kind).uppercased()+" · \(w.intValue)×\(h.intValue)")
        }
        if f.kind == .video {
            let asset=AVURLAsset(url:f.url)
            Task { @MainActor in
                guard let duration=try? await asset.load(.duration), generation == self.mediaInfoGeneration else { return }
                let seconds=CMTimeGetSeconds(duration);guard seconds.isFinite else { return }
                let total=Int(seconds.rounded());let clock = total >= 3600 ? String(format:"%d:%02d:%02d",total/3600,total%3600/60,total%60) : String(format:"%d:%02d",total/60,total%60)
                show(Self.kindTitle(f.kind).uppercased()+" · "+clock)
            }
        }
    }
    /// Opens the enclosing folder in Finder with the file selected, after the usual identity check.
    func revealFocusedFile() {
        guard !busy, let f=focusedFile, let root=root else { return }
        do { try FileSafety.validate(f,root:root);NSWorkspace.shared.activateFileViewerSelecting([f.url]) } catch { show(L("File unavailable","הקובץ אינו זמין"),error.localizedDescription) }
    }
    /// Home folder shown as ~ so long paths stay readable; the tooltip keeps the full path.
    func displayPath(_ url:URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }
    @objc func selectAllCommand(){
        if let text = window.firstResponder as? NSTextView { text.selectAll(nil) } else { selectAllFiles() }
    }
    @objc func selectAllFiles(){
        guard !busy,!mapMode else{return};guards=[:];table.selectAll(nil);updateSelection()
    }
    @objc func deselect(){guard !busy,!mapMode else{return};guards=[:];table.deselectAll(nil);updateSelection()}
    @objc func nextFile(){guard !busy,!shown.isEmpty else{return};let i=min(max(table.selectedRow+1,0),shown.count-1);table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);table.scrollRowToVisible(i);window.makeFirstResponder(table)}
    @objc func togglePreview(){guard !busy else{return};previewOpen.toggle();updatePreview();window.makeFirstResponder(table)}
    func spacePressed(){ guard !busy else{return}; if !mapMode, !videoHost.isHidden, videoPlayer.player != nil { togglePlayback() } else { togglePreview() } }
    func stopVideo(){
        if let observer=timeObserver { videoPlayer?.player?.removeTimeObserver(observer);timeObserver=nil }
        videoPlayer?.player?.pause();videoPlayer?.player=nil;videoHost?.isHidden=true
        playButton.image=NSImage(systemSymbolName:"play.fill",accessibilityDescription:L("Play","נגן"));timeSlider.doubleValue=0;timeLabel.stringValue="0:00 / 0:00"
    }
    static func clock(_ seconds:Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total=Int(seconds.rounded());return total >= 3600 ? String(format:"%d:%02d:%02d",total/3600,total%3600/60,total%60) : String(format:"%d:%02d",total/60,total%60)
    }
    func startVideo(_ url:URL) {
        let player=AVPlayer(url:url);player.actionAtItemEnd = .pause;videoPlayer.player=player;videoHost.isHidden=false
        muteButton.image=NSImage(systemSymbolName:player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",accessibilityDescription:nil)
        timeObserver=player.addPeriodicTimeObserver(forInterval:CMTime(value:1,timescale:4),queue:.main) { [weak self] time in
            guard let self=self, let item=player.currentItem else { return }
            let duration=CMTimeGetSeconds(item.duration), current=CMTimeGetSeconds(time)
            if !self.scrubbing, duration.isFinite, duration > 0 { self.timeSlider.doubleValue=current/duration }
            self.timeLabel.stringValue=Self.clock(current)+" / "+Self.clock(duration)
            let playing = player.rate != 0
            self.playButton.image=NSImage(systemSymbolName:playing ? "pause.fill" : "play.fill",accessibilityDescription:playing ? L("Pause","השהה") : L("Play","נגן"))
        }
    }
    @objc func togglePlayback() {
        guard let player=videoPlayer.player else { return }
        if player.rate != 0 { player.pause() } else {
            if let item=player.currentItem, CMTimeCompare(item.currentTime(),item.duration) >= 0 { player.seek(to:.zero) }
            player.play()
        }
    }
    @objc func toggleMute() {
        guard let player=videoPlayer.player else { return };player.isMuted.toggle()
        muteButton.image=NSImage(systemSymbolName:player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",accessibilityDescription:nil)
    }
    @objc func scrub(_ sender:NSSlider) {
        guard let player=videoPlayer.player, let item=player.currentItem else { return }
        let duration=CMTimeGetSeconds(item.duration);guard duration.isFinite else { return }
        scrubbing = NSApp.currentEvent?.type == .leftMouseDragged
        player.seek(to:CMTime(seconds:sender.doubleValue*duration,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
    }
    /// Formats AVFoundation plays natively get an inline player with visible controls; everything else uses Quick Look.
    static func playsInline(_ url:URL) -> Bool { ["mp4","m4v","mov"].contains(url.pathExtension.lowercased()) }
    func updatePreview(){
        primary?.previewItem=nil;comparison?.previewItem=nil;stopVideo()
        previewPlaceholder?.isHidden = false;primary?.isHidden = true
        guard !busy,!mapMode,previewOpen,let f=focusedFile,let root=root,(try? FileSafety.validate(f,root:root)) != nil else{return}
        previewPlaceholder?.isHidden = true
        if f.kind == .video, Self.playsInline(f.url) {
            startVideo(f.url) // paused until you press play
        } else {
            primary.isHidden = false;primary.previewItem=f.url as NSURL
        }
        if (mode.indexOfSelectedItem == 1 || mode.indexOfSelectedItem == 2), let group=currentGroups.first(where:{$0.members.contains(where:{$0.id==f.id})}),let other=(mode.indexOfSelectedItem == 2 && f.id != group.anchor.id ? group.anchor : group.members.first(where:{$0.id != f.id})),(try? FileSafety.validate(other,root:root)) != nil{comparison.previewItem=other.url as NSURL}
    }
    @objc func reveal(){guard !busy,contextRow>=0,contextRow<shown.count,let root=root else{return};let f=shown[contextRow];do{try FileSafety.validate(f,root:root);NSWorkspace.shared.activateFileViewerSelecting([f.url])}catch{show(L("File unavailable","הקובץ אינו זמין"),error.localizedDescription)}}
    @objc func findExactDuplicates(){runAnalysis(similar:false)}
    @objc func findSimilarImages(){
        guard !busy,root != nil else{return};let a=NSAlert();a.messageText=L("Compare images?","להשוות תמונות?");a.informativeText=L("Local comparison. Similarity is a suggestion; nothing is selected for deletion.","השוואה מקומית. דמיון הוא הצעה לבדיקה; לא תיבחר מחיקה אוטומטית.");a.addButton(withTitle:L("Compare","השווה"));a.addButton(withTitle:L("Cancel","בטל"));if a.runModal() == .alertFirstButtonReturn{runAnalysis(similar:true)}
    }
    func runAnalysis(similar:Bool){
        guard !busy,let root=root,!files.isEmpty else{return}
        token=CancellationToken();let jobToken=token;let source=files;setBusy(true);primary.previewItem=nil;comparison.previewItem=nil;stopVideo()
        work.async{
            do{
                let progress:(Int,Int)->Void={i,total in if i%25==0 || i==total{DispatchQueue.main.async{self.status.stringValue="\(i) / \(total)"}}}
                let result=try similar ? SimilarImages.find(source,root:root,token:jobToken,progress:progress) : ExactDuplicates.find(source,root:root,token:jobToken,progress:progress)
                DispatchQueue.main.async{
                    if similar{self.similar=result.groups}else{self.exact=result.groups}
                    self.setBusy(false);self.mode.selectItem(at:similar ? 2:1);self.sizeFilter.selectItem(at:0);self.kindFilter.selectItem(at:0);self.search.stringValue="";self.modeChanged()
                    let kindNote = similar ? L("Review suggestions only","הצעות לבדיקה בלבד") : L("SHA-256 exact copies","עותקים זהים לפי SHA-256")
                    self.status.stringValue="\(result.groups.count) "+L("groups","קבוצות")+" · \(result.skipped) "+L("skipped","דולגו")+" · "+kindNote
                    self.table.deselectAll(nil);self.updateSelection()
                }
            }catch{DispatchQueue.main.async{self.setBusy(false);self.status.stringValue=error.localizedDescription}}
        }
    }
    @objc func selectExtras(){
        guard !busy,mode.indexOfSelectedItem==1 else{return}
        let result=ExactDuplicates.selectExtras(exact,visible:Set(shown.map(\.id)));guards=result.keepers
        table.selectRowIndexes(IndexSet(shown.indices.filter{result.ids.contains(shown[$0].id)}),byExtendingSelection:false);updateSelection();window.makeFirstResponder(table)
    }
    func makeTrashAlert(_ chosen:[FileRecord])->NSAlert {
        let alert=NSAlert();alert.alertStyle = .warning
        alert.messageText=L("Move selected files to Trash?","להעביר את הבחירה לפח?")
        alert.informativeText="\(chosen.count) " + L("files","קבצים") + " · " + bytes(chosen.reduce(0){$0+$1.allocatedBytes}) + "\n" + L("Undo with ⌘Z.","אפשר לשחזר עם ⌘Z.")
        let list=NSTextView(frame:NSRect(x:0,y:0,width:390,height:min(84,CGFloat(chosen.count)*20+12)))
        list.isEditable=false;list.drawsBackground=false;list.font = .systemFont(ofSize:11);list.string=chosen.map{$0.url.path}.joined(separator:"\n")
        let scroll=NSScrollView(frame:list.frame);scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.documentView=list;alert.accessoryView=scroll
        alert.addButton(withTitle:L("Move to Trash","העבר לפח"));alert.addButton(withTitle:L("Cancel","בטל"))
        alert.showsSuppressionButton=true;alert.suppressionButton?.title=L("Do not show again","אל תציג שוב")
        return alert
    }
    @objc func toggleTrashConfirmation(_ sender:NSMenuItem) {
        let skip = !preferences.bool(forKey:"skipTrashConfirmation")
        preferences.set(skip,forKey:"skipTrashConfirmation");sender.state = skip ? .off : .on
    }
    @objc func trashSelection(){
        guard !busy,!demoMode,!mapMode,let root=root,!selectedFiles.isEmpty else{return}
        let chosen=selectedFiles
        if !preferences.bool(forKey:"skipTrashConfirmation") {
            let alert=makeTrashAlert(chosen)
            guard alert.runModal() == .alertFirstButtonReturn else{return}
            if alert.suppressionButton?.state == .on {preferences.set(true,forKey:"skipTrashConfirmation");confirmationMenuItem?.state = .off}
        }
        let keepers=guards;let row=table.selectedRow;setBusy(true);cancelButton.isEnabled=false;primary.previewItem=nil;comparison.previewItem=nil;stopVideo()
        work.async {
            let result=self.history.move(chosen,root:root,keepers:keepers,backend:self.trashBackend)
            DispatchQueue.main.async {self.finishMove(result,nextRow:row)}
        }
    }
    func finishMove(_ result:MoveResult,nextRow:Int) {
        let moved=Set(result.tickets.map{$0.original.path});files.removeAll{moved.contains($0.id)}
        exact=[];similar=[];guards=[:];mode.selectItem(at:0);setBusy(false);modeChanged()
        if !shown.isEmpty {let next=min(max(nextRow,0),shown.count-1);table.selectRowIndexes(IndexSet(integer:next),byExtendingSelection:false);table.scrollRowToVisible(next)}
        status.stringValue="\(result.tickets.count) " + L("moved to Trash","הועברו לפח")
        if !result.failures.isEmpty {show(L("Some files need attention","יש קבצים שדורשים בדיקה"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n"))}
        window.makeFirstResponder(table)
    }
    @objc func undoTrash(){
        guard !busy,!demoMode,!mapMode,history.canUndo else{return};setBusy(true);cancelButton.isEnabled=false
        work.async {
            let result=self.history.undo(backend:self.trashBackend)
            DispatchQueue.main.async {self.finishRestore(result)}
        }
    }
    @objc func retryRestore(){
        guard !busy,!demoMode,!mapMode,history.blockedCount>0 else{return};setBusy(true);cancelButton.isEnabled=false
        work.async {
            let result=self.history.retryBlocked(backend:self.trashBackend)
            DispatchQueue.main.async {self.finishRestore(result)}
        }
    }
    func finishRestore(_ result:RestoreResult?) {
        setBusy(false);guard let result=result else{return}
        if let root=root {
            for url in result.restored {
                if let record=try? FileRecord(url:url),(try? FileSafety.validate(record,root:root)) != nil {
                    files.removeAll{$0.id == record.id};files.append(record)
                }
            }
        }
        exact=[];similar=[];mode.selectItem(at:0);modeChanged()
        var text="\(result.restored.count) " + L("restored","שוחזרו")
        if history.blockedCount>0 {text += " · \(history.blockedCount) " + L("waiting in Trash · Retry restore","ממתינים בפח · נסה לשחזר שוב")}
        status.stringValue=text
        if !result.failures.isEmpty {
            show(L("Some files could not be restored","חלק מהקבצים לא שוחזרו"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n")+"\n\n"+L("They stay in Trash. Resolve the conflict and use Retry restore, or restore them from Finder Trash. Earlier batches remain available with Undo.","הם נשארים בפח. פתור את ההתנגשות ולחץ ״נסה לשחזר שוב״, או שחזר מהפח ב־Finder. פעולות קודמות עדיין זמינות לשחזור."))
        }
        window.makeFirstResponder(table)
    }
    @objc func redoTrash(){
        guard !busy,!demoMode,!mapMode,history.canRedo else{return};let row=table.selectedRow;setBusy(true);cancelButton.isEnabled=false
        work.async {
            let result=self.history.redo(backend:self.trashBackend)
            DispatchQueue.main.async {if let result=result {self.finishMove(result,nextRow:row)}else{self.setBusy(false)}}
        }
    }
    func runSmokeTests() {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("keepelix-smoke-" + UUID().uuidString)
        func cleanup() { try? FileManager.default.removeItem(at: temp); preferences.removePersistentDomain(forName:"Keepelix.SyntheticSmoke") }
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for (name, text) in [("coast-notes.txt", "Synthetic duplicate fixture"), ("coast-notes-copy.txt", "Synthetic duplicate fixture"), ("readme.txt", "Unrelated synthetic example")] {
                try Data(text.utf8).write(to: temp.appendingPathComponent(name))
            }
            precondition(locationButtons.count == 6 && locationButtons.map(\.tag) == Array(0..<6))
            precondition(Self.presetURL(0,home:temp)!.path.hasSuffix("Message/Media"))
            precondition(Self.presetURL(1,home:temp) == temp.appendingPathComponent("Downloads",isDirectory:true))
            precondition(Self.presetURL(6,home:temp) == nil)
            setBusy(true);precondition(locationButtons.allSatisfy{ !$0.isEnabled });setBusy(false)
            precondition(locationButtons.allSatisfy{ $0.isEnabled })
            root = temp
            files = try Scanner.scan(root:temp, token:CancellationToken()).files
            sizeFilter.selectItem(at:0); applyFilters()
            precondition(table.numberOfRows == 3 && table.allowsMultipleSelection)
            precondition(table.selectedRowIndexes.isEmpty, "Filtering must not silently select a file")
            table.selectRowIndexes(IndexSet([0,2]), byExtendingSelection:false)
            precondition(selectedFiles.count == 2)
            selectAllFiles(); precondition(selectedFiles.count == 3)
            deselect(); precondition(selectedFiles.isEmpty)
            search.stringValue = "readme"; applyFilters(); precondition(shown.count == 1 && selectedFiles.isEmpty)
            selectAllFiles(); precondition(selectedFiles.count == 1)
            search.stringValue = "coast"; applyFilters(); precondition(shown.count == 2 && selectedFiles.isEmpty)
            search.stringValue = ""; applyFilters()
            exact = try ExactDuplicates.find(files,root:temp,token:CancellationToken()).groups
            mode.selectItem(at:1);modeChanged();selectExtras()
            precondition(selectedFiles.count == 1 && guards.count == 1)
            let extra = selectedFiles[0];precondition(!guards.values.contains(where:{$0.id == extra.id}))
            mode.selectItem(at:0);modeChanged()
            precondition(selectedFiles.isEmpty && guards.isEmpty,"Changing mode must clear guarded selections")
            mode.selectItem(at:1);modeChanged();selectExtras()
            precondition(selectedFiles.count == 1 && guards.count == 1)
            // Exercise the real AppKit table menu on synthetic rows; do not invoke Finder.
            window.contentView!.layoutSubtreeIfNeeded()
            let row = min(1,shown.count-1)
            let point = table.convert(NSPoint(x:10,y:table.rect(ofRow:row).midY), to:nil)
            let event = NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
            precondition(table.menu(for:event)?.items.count == 1 && contextRow == row)
            mode.selectItem(at:0);modeChanged();selectAllFiles();deselect()
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            precondition(previewOpen && primary.previewItem != nil,"The preview is open by default");togglePreview();precondition(primary.previewItem == nil)
            togglePreview();precondition(primary.previewItem != nil)
            precondition(pathLabel.stringValue == displayPath(selectedFiles[0].url) && pathLabel.toolTip == selectedFiles[0].url.path,"The selected file's path must be shown")
            precondition((tableView(table,pasteboardWriterForRow:0) as? NSURL)?.path == shown[0].url.path,"Rows drag out as file URLs")
            pathLabel.setHovered(true);precondition(pathLabel.isUnderlined && pathLabel.onOpen != nil,"The path underlines on hover and opens Finder on click");pathLabel.setHovered(false);precondition(!pathLabel.isUnderlined)
            precondition(tableView(table,pasteboardWriterForRow:99) == nil && chatFilter.isHidden)
            let chatFile=temp.appendingPathComponent("Media/12036301@g.us/clip.txt");try FileManager.default.createDirectory(at:chatFile.deletingLastPathComponent(),withIntermediateDirectories:true);try Data("g".utf8).write(to:chatFile)
            files.append(try FileRecord(url:chatFile));applyFilters();precondition(!chatFilter.isHidden,"Chat filter appears only when chat folders exist")
            chatFilter.selectItem(at:1);applyFilters();precondition(shown.count == 1 && shown[0].url.lastPathComponent == "clip.txt");chatFilter.selectItem(at:2);applyFilters();precondition(shown.isEmpty)
            precondition(chatFilter.itemArray.contains{ ($0.representedObject as? String) == "12036301@g.us" } && chatNamesButton.isHidden,"Chats are listed by identifier; names need a database")
            precondition(!autoDownloadButton.isHidden);openWhatsAppAutoDownload();precondition(status.stringValue.contains("auto-download") || status.stringValue.contains("אוטומטית"))
            var db:OpaquePointer?;precondition(sqlite3_open(temp.appendingPathComponent(ChatDirectory.databaseName).path,&db) == SQLITE_OK)
            precondition(sqlite3_exec(db,"CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZPARTNERNAME TEXT); INSERT INTO ZWACHATSESSION (ZCONTACTJID, ZPARTNERNAME) VALUES ('12036301@g.us','Synthetic hiking group')",nil,nil,nil) == SQLITE_OK);sqlite3_close(db)
            applyFilters();precondition(!chatNamesButton.isHidden,"Offer names once a chat list is found");loadChatNames(confirmed:true);settle()
            precondition(chatNames["12036301@g.us"]?.name == "Synthetic hiking group" && chatNamesButton.isHidden)
            let named=chatFilter.itemArray.firstIndex{ $0.title.hasPrefix("Synthetic hiking group") }!;chatFilter.selectItem(at:named);applyFilters();precondition(shown.count == 1 && shown[0].url.lastPathComponent == "clip.txt","Filtering by a named chat")
            try FileManager.default.removeItem(at:temp.appendingPathComponent(ChatDirectory.databaseName))
            chatFilter.selectItem(at:0);files.removeAll{$0.url == chatFile};try FileManager.default.removeItem(at:temp.appendingPathComponent("Media"));applyFilters();precondition(chatFilter.isHidden)
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            precondition(!kindBadge.isHidden && kindBadge.stringValue.contains(Self.kindTitle(.document).uppercased()) && videoHost.isHidden,"Text files show a document badge and no player")
            precondition(selectionLabel.stringValue.hasPrefix(L("Item ","פריט ")+"1"+L(" of ","  מתוך ")+"\(shown.count)"),"Position counter: \(selectionLabel.stringValue)")
            let clip=temp.appendingPathComponent("Synthetic clip.mov");try Self.writeSyntheticVideo(to:clip);files.append(try FileRecord(url:clip));applyFilters()
            table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url.lastPathComponent == "Synthetic clip.mov"}!),byExtendingSelection:false)
            precondition(!videoHost.isHidden && videoPlayer.player != nil && videoPlayer.player?.rate == 0 && primary.isHidden,"Videos open in the inline player, paused")
            togglePlayback();precondition(videoPlayer.player?.rate != 0);togglePlayback();precondition(videoPlayer.player?.rate == 0)
            let space=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49)!
            table.keyDown(with:space);precondition(videoPlayer.player?.rate != 0 && previewOpen,"Space plays a video instead of closing the preview")
            table.keyDown(with:space);precondition(videoPlayer.player?.rate == 0 && previewOpen,"Space pauses it")
            toggleMute();precondition(videoPlayer.player?.isMuted == true);toggleMute()
            togglePreview();precondition(videoHost.isHidden && videoPlayer.player == nil,"Closing the preview releases the video");togglePreview()
            files.removeAll{$0.url == clip};try FileManager.default.removeItem(at:clip);applyFilters()
            precondition(Self.playsInline(URL(fileURLWithPath:"/x/clip.MOV")) && !Self.playsInline(URL(fileURLWithPath:"/x/clip.mkv")))
            deselect();precondition(pathLabel.stringValue.isEmpty);table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            nextFile();precondition(table.selectedRow == 1 && primary.previewItem != nil)
            togglePreview();precondition(primary.previewItem == nil)
            // Extending the selection previews the row just reached, shrinking it steps back.
            togglePreview();table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            let shiftDown=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.shift],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{F701}",charactersIgnoringModifiers:"\u{F701}",isARepeat:false,keyCode:125)!
            table.keyDown(with:shiftDown);precondition(table.selectedRowIndexes == IndexSet([0,1]) && primary.previewItem as? URL == shown[1].url && selectionLabel.stringValue.hasPrefix(L("Item ","פריט ")+"2"),"Shift+Down must preview the newly added row: \(selectionLabel.stringValue)")
            table.keyDown(with:shiftDown);precondition(table.selectedRowIndexes == IndexSet([0,1,2]) && primary.previewItem as? URL == shown[2].url)
            let shiftUp=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.shift],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\u{F700}",charactersIgnoringModifiers:"\u{F700}",isARepeat:false,keyCode:126)!
            table.keyDown(with:shiftUp);precondition(table.selectedRowIndexes == IndexSet([0,1]) && primary.previewItem as? URL == shown[1].url,"Shift+Up back previews the last remaining row")
            table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false);table.keyDown(with:shiftUp);precondition(table.selectedRowIndexes == IndexSet([1,2]) && primary.previewItem as? URL == shown[1].url,"Shift+Up from a single row previews the row above")
            togglePreview()
            let oldURL=temp.appendingPathComponent("old-sample.txt")
            try Data("Synthetic old file".utf8).write(to:oldURL)
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:946684800)],ofItemAtPath:oldURL.path)
            files.append(try FileRecord(url:oldURL));showOlderFiles()
            precondition(shown.count == 1 && shown[0].url == oldURL && selectedFiles.isEmpty)
            mode.selectItem(at:0);modeChanged();sortPicker.selectItem(at:ReviewSort.oldest.rawValue);changeSort()
            precondition(shown.first?.url == oldURL)
            table.sortDescriptors=[NSSortDescriptor(key:"modified",ascending:false)]
            precondition(shown.last?.url == oldURL)
            func settle() { let deadline=Date().addingTimeInterval(20);while busy && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(!busy,"Synthetic operation timed out") }
            // Storage map on a synthetic tree: measure, drill, go up, hand off to file review and return without re-mapping.
            let mapFolder=temp.appendingPathComponent("map",isDirectory:true)
            for sub in ["Big","Small"] {try FileManager.default.createDirectory(at:mapFolder.appendingPathComponent(sub),withIntermediateDirectories:true)}
            try Data(repeating:0x41,count:50_000).write(to:mapFolder.appendingPathComponent("Big/large.bin"))
            try Data("s".utf8).write(to:mapFolder.appendingPathComponent("Small/tiny.txt"));try Data("t".utf8).write(to:mapFolder.appendingPathComponent("Small/tiny2.txt"))
            try Data("loose".utf8).write(to:mapFolder.appendingPathComponent("loose.txt"))
            let reviewRoot=root!;let bigPath=mapFolder.appendingPathComponent("Big").resolvingSymlinksInPath().path
            startMap(mapFolder);settle()
            precondition(mapMode && !mapPanel.isEmpty && scroll.isHidden && !mapPanel.isHidden && emptyList.isHidden && !mapPanel.detail.isHidden)
            precondition(mapPanel.rows.map(\.title) == ["Big","Small",L("Files in this folder","קבצים בתיקייה עצמה")],"Map rows sort by size: \(mapPanel.rows.map(\.title))")
            precondition(mapPanel.table.selectedRow == 0 && mapPanel.reviewTarget?.path == bigPath && mapPanel.openButton.isEnabled)
            precondition(status.stringValue.contains("4 "+L("files","קבצים")) && status.stringValue.contains("2 "+L("folders","תיקיות")),status.stringValue)
            mapPanel.openSelected();precondition(mapPanel.current?.name == "Big" && mapPanel.rows.count == 1 && !mapPanel.rows[0].isFolder && !mapPanel.openButton.isEnabled)
            precondition(mapPanel.reviewTarget?.path == bigPath,"The loose-files row reviews the current folder")
            mapPanel.goUp();precondition(mapPanel.current?.name == "map" && mapPanel.selectedRow?.title == "Big")
            let mapDelete=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51)!
            mapPanel.table.keyDown(with:mapDelete);precondition(!busy && FileManager.default.fileExists(atPath:mapFolder.appendingPathComponent("Big/large.bin").path),"Delete in the map must not move anything")
            selectAllFiles();precondition(table.selectedRowIndexes.isEmpty,"Select all must not reach the hidden file table in map mode")
            mapPanel.reviewSelected();settle()
            precondition(!mapMode && root?.path == bigPath && files.count == 1 && files[0].name == "large.bin" && !scroll.isHidden && mapPanel.isHidden,"Review files here hands the folder to file review")
            showStorageMap();precondition(mapMode && mapPanel.current?.name == "Big" && mapPanel.result != nil,"Return to the map without re-mapping")
            showStorageMap();precondition(!mapMode && root?.path == bigPath,"Back to files")
            startScan(reviewRoot);settle();precondition(!mapMode && root?.path == reviewRoot.resolvingSymlinksInPath().path)
            precondition(!history.canUndo && !history.canRedo)
            let alert=makeTrashAlert([files[0]]);precondition(alert.showsSuppressionButton && alert.suppressionButton?.state == .off)
            struct FixtureTrash: TrashBackend {
                let folder:URL
                func moveToTrash(_ url:URL)throws->URL {
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    let destination=folder.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.moveItem(at:url,to:destination);return destination
                }
                func restore(_ source:URL,to destination:URL)throws {try FileManager.default.moveItem(at:source,to:destination)}
            }
            trashBackend=FixtureTrash(folder:temp.appendingPathComponent(".fixture-trash"))
            preferences.set(true,forKey:"skipTrashConfirmation")
            sortPicker.selectItem(at:ReviewSort.name.rawValue);changeSort()
            let target=temp.appendingPathComponent("coast-notes.txt").resolvingSymlinksInPath()
            table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url.path == target.path}!),byExtendingSelection:false)
            precondition(selectedFiles[0].url.path == target.path)
            func key(_ code:UInt16,_ flags:NSEvent.ModifierFlags=[],_ repeated:Bool=false) {
                let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeated,keyCode:code)!
                table.keyDown(with:event);settle()
            }
            key(51);precondition(!FileManager.default.fileExists(atPath:target.path) && history.canUndo)
            let count=files.count;key(51,[],true);precondition(files.count == count,"Held Delete must not trash the next file")
            key(6,[.command]);precondition(FileManager.default.fileExists(atPath:target.path) && history.canRedo)
            key(6,[.command,.shift]);precondition(!FileManager.default.fileExists(atPath:target.path) && history.canUndo)
            key(6,[.command]);precondition(FileManager.default.fileExists(atPath:target.path))
            // Blocked restore: a newcomer at the original path is never overwritten, earlier batches stay undoable, and Retry restore succeeds once the path is free.
            let other=shown.first{$0.url != target}!.url
            table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url == other}!),byExtendingSelection:false);key(51)
            table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url == target}!),byExtendingSelection:false);key(51)
            precondition(!FileManager.default.fileExists(atPath:target.path) && !FileManager.default.fileExists(atPath:other.path))
            try Data("newcomer".utf8).write(to:target)
            key(6,[.command]);precondition(history.blockedCount == 1 && history.canUndo && !retryButton.isHidden && retryButton.isEnabled,"Blocked restore must not hide earlier batches")
            let occupant=try String(contentsOf:target);precondition(occupant == "newcomer","Undo must never overwrite")
            key(6,[.command]);precondition(FileManager.default.fileExists(atPath:other.path) && !history.canUndo && history.blockedCount == 1,"Earlier batch restored behind the blocked one")
            try FileManager.default.removeItem(at:target)
            retryRestore();settle()
            let restoredText=try String(contentsOf:target)
            precondition(history.blockedCount == 0 && waitingRestores == 0,"Retry must clear the waiting list: \(history.blockedCount)")
            precondition(retryButton.isHidden,"Retry button must hide once nothing waits")
            precondition(restoredText == "Synthetic duplicate fixture","Restored content mismatch: \(restoredText)")
            precondition(history.canRedo,"A retried restore must be redoable")
            let savedRoot=root!;activateRoot(temp.appendingPathComponent("other"));precondition(!history.canUndo && !history.canRedo);activateRoot(savedRoot);precondition(history.canRedo)
            toggleTrashConfirmation(confirmationMenuItem!);precondition(!preferences.bool(forKey:"skipTrashConfirmation"))
            let languageItems=languageMenuItem!.submenu!.items;precondition(languageItems.map{$0.representedObject as? String} == ["en","he"] && languageItems[0].state == .on)
            chooseLanguage(languageItems[1]);precondition(preferences.string(forKey:"language") == "he" && preferences.stringArray(forKey:"AppleLanguages") == ["he"] && languageItems[1].state == .on && languageItems[0].state == .off)
            precondition(AppLanguage.current == "en" && L("a","ב") == "a","A language choice applies on the next launch, not mid-session")
            precondition(preferences.bool(forKey:"AppleTextDirection"),"Hebrew must switch the layout direction")
            chooseLanguage(languageItems[0]);precondition(preferences.stringArray(forKey:"AppleLanguages") == ["en"] && !preferences.bool(forKey:"AppleTextDirection"))
            precondition(isCurrentRoot(root!) && !isCurrentRoot(temp.appendingPathComponent("map")),"Clicking the loaded location again must not rescan")
            print("UI smoke: storage map, selection, old-file sorting, preview, confirmation preference, Delete, Undo, Redo, blocked-restore retry and held-key protection passed. No real files changed; no windows shown.")
            cleanup();fflush(stdout);exit(0)
        } catch { fputs("UI smoke failed: \(error)\n",stderr);cleanup();exit(1) }
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { applicationShouldTerminate(NSApplication.shared) == .terminateNow }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{
        if busy && !(token.isCancelled && cancelButton.isEnabled){show(L("Operation in progress","פעולה עדיין מתבצעת"),L("Cancel the scan and wait, or let the Trash operation finish before quitting.","בטל את הסריקה והמתן, או אפשר להעברה לפח להסתיים לפני הסגירה."));return .terminateCancel}
        let waiting=waitingRestores
        if waiting>0 && !smokeMode {
            let a=NSAlert();a.alertStyle = .warning;a.messageText=L("Quit with restores waiting?","לצאת כשיש שחזורים ממתינים?")
            a.informativeText="\(waiting) "+L("items could not be restored and stay in Trash. After quitting, restore them from Finder Trash; this app's history is not kept.","פריטים לא שוחזרו ונשארים בפח. אחרי היציאה אפשר לשחזר אותם מהפח ב־Finder; ההיסטוריה של האפליקציה לא נשמרת.")
            a.addButton(withTitle:L("Quit","צא"));a.addButton(withTitle:L("Cancel","בטל"))
            if a.runModal() != .alertFirstButtonReturn {return .terminateCancel}
        }
        return .terminateNow
    }
    var waitingRestores:Int {
        var seen=Set<ObjectIdentifier>();var total=0
        for h in [history]+Array(folderHistories.values) where seen.insert(ObjectIdentifier(h)).inserted {total+=h.blockedCount}
        return total
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
let launchArguments=ProcessInfo.processInfo.arguments
if let index=launchArguments.firstIndex(of:"--language"), index+1<launchArguments.count, AppLanguage.supported.contains(where:{$0.0 == launchArguments[index+1]}) {
    AppLanguage.current=launchArguments[index+1]
} else if !launchArguments.contains("--smoke-test") && !launchArguments.contains("--demo") && !launchArguments.contains("--demo-map") {
    AppLanguage.current = UserDefaults.standard.string(forKey:"language") == "he" ? "he" : "en"
}
let app=NSApplication.shared;app.setActivationPolicy((ProcessInfo.processInfo.arguments.contains("--smoke-test") || ProcessInfo.processInfo.arguments.contains("--launch-check")) ? .prohibited : .regular)
let controller=AppController();app.delegate=controller;app.run()
