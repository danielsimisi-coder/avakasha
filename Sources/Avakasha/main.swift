import Cocoa
import Quartz
import AVKit
import ImageIO
import SQLite3
import AvakashaCore

/// Interface language. English by default; Hebrew is an explicit choice in Avakasha › Language and applies on the next launch.
enum AppLanguage { static var current = "en"; static let supported = [("en", "English"), ("he", "עברית")] }
func L(_ en: String, _ he: String) -> String { AppLanguage.current == "he" ? he : en }
func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

final class FileTable: NSTableView {
    weak var owner: AppController?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { if !event.isARepeat {owner?.trashSelection()};return }
        if event.keyCode == 49 { if !event.isARepeat { owner?.spacePressed() }; return }
        if event.keyCode == 1 && event.modifierFlags.intersection([.command,.control,.option]).isEmpty { if !event.isARepeat { owner?.toggleStar() }; return } // S
        if event.keyCode == 40 && event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty { if !event.isARepeat { owner?.toggleReviewed() }; return } // K
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
        if ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.arguments.contains("--demo-map") { return UserDefaults(suiteName:"Avakasha.SyntheticDemo")! }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            guard let isolated = UserDefaults(suiteName:"Avakasha.SyntheticSmoke") else { fatalError("Cannot create synthetic test preferences") }
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
    let starFilter = NSPopUpButton()
    /// Paths starred by the user. Stored in this app's preferences only; the files themselves are not touched.
    var starred: Set<String> = []
    /// Files the user looked at and decided to keep; pinned to size and mtime, so a rewritten file shows up again.
    lazy var reviewed: ReviewedStore = { let p=preferences; return ReviewedStore(load:{ p.dictionary(forKey:"reviewedFiles") as? [String:String] ?? [:] },save:{ p.set($0,forKey:"reviewedFiles") }) }()
    /// Where the file list came from: a folder scan, or the largest files of the storage map (Refresh re-measures the map).
    enum ReviewSource { case scan, largestFiles }
    var reviewSource: ReviewSource = .scan
    /// True while Refresh re-measures the map for the largest-files view; cleared when the map completes or fails.
    var pendingLargestReview = false
    /// The map root the largest-files list was built from; Refresh re-measures this, never whatever was mapped later.
    var largestRoot: URL?
    let spaceLabel = NSTextField(labelWithString: "")
    var chatNamesButton: NSButton!
    var autoDownloadButton: NSButton!
    var chatNames: [String: ChatInfo] = [:]
    var chatNamesSource: URL?
    let sortPicker = NSPopUpButton()
    static let ageHintText = L("Based on last modification — age alone does not mean a file is unused.","לפי השינוי האחרון — גיל הקובץ לא מעיד בהכרח שלא השתמשת בו.")
    static let installerHintText = L("Installer and archive files not modified in that time. Keep them if the app is not installed yet or the archive was never extracted. You decide.","קבצי התקנה וארכיונים שלא שונו בפרק הזמן הזה. השאר אותם אם האפליקציה עדיין לא מותקנת או שהארכיון לא חולץ. אתה מחליט.")
    static let reviewTips = L("Space · Play/Pause or Preview     Delete · Trash     ⌘Z · Undo     S · Star   K · Reviewed","רווח · נגן/השהה או תצוגה     Delete · פח     ⌘Z · שחזור     S · כוכב   K · נסקר")
    let ageHint = NSTextField(labelWithString:AppController.ageHintText)
    let status = NSTextField(labelWithString: "")
    let selectionLabel = NSTextField(labelWithString: "")
    let pathLabel = PathLink()
    let kindBadge = NSTextField(labelWithString: "")
    let chatBadge = NSButton()
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
    let work = DispatchQueue(label: "Avakasha.background", qos: .userInitiated)
    var busy = false
    var previewOpen = true // the preview pane is open by default; Space plays or pauses a video, otherwise toggles the preview
    var contextRow = -1
    var history = TrashHistory()
    var folderHistories: [String: TrashHistory] = [:]
    var trashBackend: TrashBackend = SystemTrash()
    var redoButton: NSButton!
    var confirmationMenuItem: NSMenuItem?
    var mapMode = false
    /// The home screen: disks, this session, where to start. Shown at launch until something is scanned or mapped.
    var overviewMode = false
    let overviewPanel = OverviewPanel()
    var sidebarOverview: NSButton!, sidebarMap: NSButton!, sidebarOlder: NSButton!, sidebarInstallers: NSButton!, sidebarFreeUp: NSButton!
    /// "Free up space": known caches and app data explained one by one, measured on request.
    var freeUpMode = false
    let freeUpPanel = FreeUpPanel()
    /// The home folder the Free up space screen works on. A stored value so the hidden smoke can point it at a synthetic home.
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var previewHostView: NSView!
    let mapPanel = StorageMapPanel()
    var mapRoot: URL?
    var reviewOnlyViews: [NSView] = []
    var headingLabel: NSTextField!
    var tips: NSTextField!
    var retryButton: NSButton!
    var mapButton: NSButton!
    /// True once files were moved or restored after the current map was measured.
    var mapStale = false
    let continueLink = PathLink()
    var rescanButton: NSButton!
    var cancellable = false // true while a scan, map or analysis can be stopped with partial results
    var escapeMonitor: Any?
    var scroll: NSScrollView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1320,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.delegate=self; window.title="Avakasha · 0.1.0 beta 9"
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
        let brand=row([brandIcon,label("Avakasha",21,.semibold)],10)
        let choose=button("Other folder or drive…","תיקייה אחרת או כונן…","folder.badge.plus",#selector(chooseFolder))
        let presets=[("WhatsApp","ווטסאפ","message.fill"),("Downloads","הורדות","arrow.down.circle.fill"),("Movies","סרטים","film.fill"),("Pictures","תמונות","photo.fill"),("Documents","מסמכים","doc.text.fill"),("Desktop","שולחן העבודה","desktopcomputer")]
        for (index,p) in presets.enumerated() {
            let b=button(p.0,p.1,p.2,#selector(chooseLocation(_:)));b.tag=index;b.isBordered=false;b.alignment = .natural;b.imageHugsTitle=true
            b.contentTintColor = .labelColor;b.font = .systemFont(ofSize:14,weight:.medium)
            b.heightAnchor.constraint(equalToConstant:38).isActive=true
            b.toolTip=L("Click to scan this folder. Scanning never deletes files.","לחץ לסריקת התיקייה. הסריקה לא מוחקת קבצים.");locationButtons.append(b)
        }
        let locationList=column(locationButtons,4)
        let sidebarSpacer=NSView();sidebarSpacer.setContentHuggingPriority(.init(1),for:.vertical)
        let privacy=label(L("Local. Private. Yours.","מקומי. פרטי. שלך."),13,.medium)
        let overviewEntry=button("Overview","סקירה כללית","house.fill",#selector(showOverview));overviewEntry.isBordered=false;overviewEntry.alignment = .natural;overviewEntry.font = .systemFont(ofSize:14,weight:.medium);sidebarOverview=overviewEntry
        overviewEntry.toolTip=L("Disks, this session and where to start.","כוננים, ההפעלה הזו ומאיפה להתחיל.")
        let olderButton=button("Older files","קבצים ישנים","clock",#selector(showOlderFiles));olderButton.isBordered=false;olderButton.alignment = .natural;olderButton.font = .systemFont(ofSize:14,weight:.medium);sidebarOlder=olderButton
        let installersButton=button("Installers","קבצי התקנה","shippingbox",#selector(showInstallers));installersButton.isBordered=false;installersButton.alignment = .natural;installersButton.font = .systemFont(ofSize:14,weight:.medium);sidebarInstallers=installersButton
        installersButton.toolTip=L("Disk images, installer packages and archives in this location that have not changed for a while. Nothing is deleted.","תמונות דיסק, חבילות התקנה וארכיונים במיקום הזה שלא השתנו זמן רב. שום דבר לא נמחק.")
        let openBin=button("Trash","פח האשפה","trash",#selector(openTrash));openBin.isBordered=false;openBin.alignment = .natural;openBin.font = .systemFont(ofSize:14,weight:.medium)
        let freeUpEntry=button("Free up space","פינוי מקום","sparkles",#selector(showFreeUp));freeUpEntry.isBordered=false;freeUpEntry.alignment = .natural;freeUpEntry.font = .systemFont(ofSize:14,weight:.medium);sidebarFreeUp=freeUpEntry
        freeUpEntry.toolTip=L("Caches and app data that fill System Data, explained one by one. Measured only when you ask.","מטמונים ונתוני אפליקציות שממלאים את System Data, מוסברים אחד־אחד. נמדדים רק כשתבקש.")
        let mapEntry=button("Storage map…","מפת אחסון…","chart.pie.fill",#selector(chooseMapFolder));mapEntry.isBordered=false;mapEntry.alignment = .natural;mapEntry.font = .systemFont(ofSize:14,weight:.medium);sidebarMap=mapEntry
        mapEntry.toolTip=L("See which folders fill a folder or drive. Nothing is deleted.","ראה אילו תיקיות ממלאות תיקייה או כונן. שום דבר לא נמחק.")
        let sidebarContent=column([brand,overviewEntry,label(L("LOCATIONS","מיקומים"),10,.semibold,true),locationList,choose,divider(),mapEntry,freeUpEntry,olderButton,installersButton,openBin,sidebarSpacer,privacy],18)
        let sidebar=NSVisualEffectView();sidebar.material = .sidebar;sidebar.blendingMode = .behindWindow;sidebar.state = .followsWindowActiveState
        sidebar.addSubview(sidebarContent);sidebarContent.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([sidebar.widthAnchor.constraint(equalToConstant:216),sidebarContent.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:20),sidebarContent.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-16),sidebarContent.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:24),sidebarContent.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-24),locationList.widthAnchor.constraint(equalTo:sidebarContent.widthAnchor)])
        for b in locationButtons { b.widthAnchor.constraint(equalTo:locationList.widthAnchor).isActive=true }
        choose.font = .systemFont(ofSize:11);choose.controlSize = .small
        let rescan=button("Refresh","רענן","arrow.clockwise",#selector(rescanFolder));rescanButton=rescan
        headingLabel=label(L("Your files","הקבצים שלך"),23,.semibold)
        let heading=column([headingLabel],6)
        mapButton=button("Storage map","מפת אחסון","chart.pie",#selector(showStorageMap))
        mapButton.toolTip=L("See which folders take the space in this location.","ראה אילו תיקיות תופסות את המקום במיקום הזה.")
        let header=row([heading,spacer(),mapButton,rescan])
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
        mode.addItems(withTitles:[L("All files","כל הקבצים"),L("Exact duplicates","כפילויות זהות"),L("Similar images","תמונות דומות"),L("Older files","קבצים ישנים"),L("Installers & archives","קבצי התקנה וארכיונים")]);mode.target=self;mode.action = #selector(modeChanged)
        groupPicker.target=self;groupPicker.action = #selector(applyFilters)
        let exactButton=button("Find duplicates","מצא כפילויות","square.on.square",#selector(findExactDuplicates))
        let similarButton=button("Compare images","השווה תמונות","photo.on.rectangle.angled",#selector(findSimilarImages))
        agePicker.addItems(withTitles:[L("Not modified in 6 months","לא שונו בחצי שנה"),L("Not modified in 1 year","לא שונו בשנה"),L("Not modified in 2 years","לא שונו בשנתיים"),L("Not modified in 5 years","לא שונו בחמש שנים")]);agePicker.selectItem(at:1);agePicker.target=self;agePicker.action = #selector(applyFilters)
        ageHint.font = .systemFont(ofSize:11);ageHint.textColor = .secondaryLabelColor
        starFilter.addItems(withTitles:[L("★ All","★ הכול"),L("Starred only","עם כוכב בלבד"),L("Hide starred","ללא כוכב"),L("Not yet reviewed","טרם נסקרו"),L("Reviewed only","נסקרו בלבד")]);starFilter.target=self;starFilter.action = #selector(applyFilters);starFilter.font = .systemFont(ofSize:12)
        starFilter.setAccessibilityLabel(L("Star and review filter","סינון כוכב וסקירה"));starFilter.toolTip=L("Star important files with S or the star column. Stars are kept by this app only; files are not changed.","סמן קבצים חשובים ב־S או בעמודת הכוכב. הכוכבים נשמרים באפליקציה בלבד; הקבצים לא משתנים.")
        starred=Set(preferences.stringArray(forKey:"starredPaths") ?? [])
        let analysis=row([mode,groupPicker,agePicker,starFilter,chatNamesButton,autoDownloadButton,spacer(),exactButton,similarButton])
        scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
        table.frame=NSRect(x:0,y:0,width:540,height:440);table.autoresizingMask=[.width];table.owner=self;table.delegate=self;table.dataSource=self
        table.setDraggingSourceOperationMask(.copy,forLocal:false) // dragging out copies; Avakasha never moves files without confirmation
        table.allowsMultipleSelection=true;table.rowHeight=38;table.intercellSpacing=NSSize(width:12,height:4);table.usesAlternatingRowBackgroundColors=false;table.style = .inset;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (id,title,width) in [("star","★",24.0),("name",L("Name","שם"),240.0),("size",L("On disk","בדיסק"),80.0),("modified",L("Last modified","שינוי אחרון"),100.0)] {
            let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));c.title=title;c.width=width;table.addTableColumn(c)
            if id == "star" { c.minWidth=24;c.maxWidth=24;c.resizingMask=[] } else { c.sortDescriptorPrototype=NSSortDescriptor(key:id,ascending:id != "size") }
        }
        scroll.documentView=table
        primary=QLPreviewView(frame:NSRect(x:0,y:0,width:330,height:440),style:.normal);primary.autostarts=false
        comparison=QLPreviewView(frame:NSRect(x:0,y:0,width:330,height:440),style:.normal);comparison.autostarts=false
        // AVKit hides its own controls when the pointer leaves the video, so the transport bar below is drawn by Avakasha and always visible.
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
        continueLink.isHidden=true;continueLink.alignment = .center;continueLink.setAccessibilityLabel(L("Continue with the last folder","המשך עם התיקייה האחרונה"))
        continueLink.onOpen={[weak self] in self?.resumeFolder()}
        emptyList=column([emptyIcon,emptyListTitle,emptyListDetail,continueLink],12);emptyList.alignment = .centerX;emptyList.translatesAutoresizingMaskIntoConstraints=false;listHost.addSubview(emptyList)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:listHost.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:listHost.trailingAnchor),scroll.topAnchor.constraint(equalTo:listHost.topAnchor),scroll.bottomAnchor.constraint(equalTo:listHost.bottomAnchor),emptyList.centerXAnchor.constraint(equalTo:listHost.centerXAnchor),emptyList.centerYAnchor.constraint(equalTo:listHost.centerYAnchor)])
        mapPanel.translatesAutoresizingMaskIntoConstraints=false;listHost.addSubview(mapPanel,positioned:.below,relativeTo:emptyList);mapPanel.isHidden=true
        NSLayoutConstraint.activate([mapPanel.leadingAnchor.constraint(equalTo:listHost.leadingAnchor,constant:12),mapPanel.trailingAnchor.constraint(equalTo:listHost.trailingAnchor,constant:-12),mapPanel.topAnchor.constraint(equalTo:listHost.topAnchor,constant:12),mapPanel.bottomAnchor.constraint(equalTo:listHost.bottomAnchor)])
        mapPanel.onReview={[weak self] url in self?.reviewFromMap(url)}
        mapPanel.onReveal={[weak self] url in self?.revealFolder(url)}
        mapPanel.onSelectionChange={[weak self] in self?.refreshEmptyState()}
        mapPanel.onRescan={[weak self] in if let target=self?.mapRoot { self?.startMap(target) }}
        mapPanel.onLargest={[weak self] in self?.reviewLargestFiles()}
        overviewPanel.translatesAutoresizingMaskIntoConstraints=false;listHost.addSubview(overviewPanel,positioned:.below,relativeTo:emptyList);overviewPanel.isHidden=true
        NSLayoutConstraint.activate([overviewPanel.leadingAnchor.constraint(equalTo:listHost.leadingAnchor),overviewPanel.trailingAnchor.constraint(equalTo:listHost.trailingAnchor),overviewPanel.topAnchor.constraint(equalTo:listHost.topAnchor),overviewPanel.bottomAnchor.constraint(equalTo:listHost.bottomAnchor)])
        overviewPanel.onMapHome={[weak self] in self?.startMap(FileManager.default.homeDirectoryForCurrentUser)}
        overviewPanel.onMapDrive={[weak self] in self?.chooseMapFolder()}
        overviewPanel.onFreeUp={[weak self] in self?.showFreeUp()}
        previewHostView=previewHost
        mapPanel.onTrashFolder={[weak self] node in self?.trashFolderFromMap(node)}
        freeUpPanel.translatesAutoresizingMaskIntoConstraints=false;listHost.addSubview(freeUpPanel,positioned:.below,relativeTo:emptyList);freeUpPanel.isHidden=true
        NSLayoutConstraint.activate([freeUpPanel.leadingAnchor.constraint(equalTo:listHost.leadingAnchor,constant:12),freeUpPanel.trailingAnchor.constraint(equalTo:listHost.trailingAnchor,constant:-12),freeUpPanel.topAnchor.constraint(equalTo:listHost.topAnchor,constant:12),freeUpPanel.bottomAnchor.constraint(equalTo:listHost.bottomAnchor)])
        previewHost.addSubview(freeUpPanel.detail);freeUpPanel.detail.translatesAutoresizingMaskIntoConstraints=false;freeUpPanel.detail.isHidden=true
        NSLayoutConstraint.activate([freeUpPanel.detail.leadingAnchor.constraint(equalTo:previewHost.leadingAnchor,constant:22),freeUpPanel.detail.trailingAnchor.constraint(equalTo:previewHost.trailingAnchor,constant:-22),freeUpPanel.detail.topAnchor.constraint(equalTo:previewHost.topAnchor,constant:26)])
        freeUpPanel.onMeasure={[weak self] locations in self?.measureLocations(locations)}
        freeUpPanel.onTrash={[weak self] location,measurement in self?.trashLocation(location,measured:measurement)}
        freeUpPanel.onReveal={[weak self] url in self?.revealFolder(url)}
        freeUpPanel.onCopyCommand={[weak self] command in NSPasteboard.general.clearContents();NSPasteboard.general.setString(command,forType:.string);self?.status.stringValue=L("Command copied · paste it in Terminal","הפקודה הועתקה · הדבק ב־Terminal")}
        freeUpPanel.onSelectionChange={[weak self] in self?.updateEnabled()}
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
        pathLabel.onOpen={[weak self] in self?.revealFocusedFile()};pathLabel.onCopy={[weak self] in self?.copyFocusedPath()}
        pathLabel.toolTip=L("Click to show in Finder · right-click or ⌘C to copy the path","לחיצה מציגה ב־Finder · לחיצה ימנית או ⌘C מעתיקים את הנתיב")
        kindBadge.font = .systemFont(ofSize:10,weight:.semibold);kindBadge.wantsLayer=true;kindBadge.layer?.cornerRadius=5;kindBadge.alignment = .center
        kindBadge.setContentHuggingPriority(.required,for:.horizontal);kindBadge.setContentCompressionResistancePriority(.required,for:.horizontal)
        kindBadge.widthAnchor.constraint(greaterThanOrEqualToConstant:52).isActive=true;kindBadge.heightAnchor.constraint(equalToConstant:18).isActive=true;kindBadge.isHidden=true
        kindBadge.setAccessibilityLabel(L("File type","סוג הקובץ"))
        chatBadge.isBordered=false;chatBadge.wantsLayer=true;chatBadge.layer?.cornerRadius=5;chatBadge.font = .systemFont(ofSize:10,weight:.semibold);chatBadge.imagePosition = .imageLeading;chatBadge.imageHugsTitle=true
        chatBadge.target=self;chatBadge.action = #selector(filterByFocusedChat);chatBadge.isHidden=true;chatBadge.heightAnchor.constraint(equalToConstant:18).isActive=true
        chatBadge.setContentHuggingPriority(.required,for:.horizontal);chatBadge.setContentCompressionResistancePriority(.defaultHigh,for:.horizontal);chatBadge.lineBreakMode = .byTruncatingTail
        chatBadge.toolTip=L("The WhatsApp chat this file belongs to. Click to show only this chat.","השיחה בווטסאפ שהקובץ שייך אליה. לחיצה מציגה רק את השיחה הזו.")
        let selection=row([all,extrasButton,kindBadge,chatBadge,pathLabel,selectionLabel],10)
        let preview=button("Preview","תצוגה מקדימה","eye",#selector(togglePreview));preview.toolTip=L("Space to toggle preview","רווח לפתיחה וסגירה של תצוגה מקדימה")
        let next=button("Keep & next","השאר והמשך","arrow.right",#selector(nextFile));next.toolTip=L("Marks the highlighted file as reviewed and kept, then moves to the next one.","מסמן את הקובץ המואר כנסקר ונשמר ועובר לבא.")
        let trash=button("Move to Trash…","העבר לפח…","trash",#selector(trashSelection));trash.contentTintColor = .systemRed
        undoButton=button("Undo","שחזר","arrow.uturn.backward",#selector(undoTrash))
        redoButton=button("Redo","בצע שוב","arrow.uturn.forward",#selector(redoTrash))
        retryButton=button("Retry restore","נסה לשחזר שוב","arrow.clockwise.circle",#selector(retryRestore));retryButton.isHidden=true
        retryButton.toolTip=L("Try again to restore items whose original location was taken. Nothing is overwritten.","נסה שוב לשחזר פריטים שהמיקום המקורי שלהם נתפס. שום קובץ לא נדרס.")
        let review=row([preview,next,spacer(),retryButton,undoButton,redoButton,trash])
        cancelButton=NSButton(title:L("Stop","עצור"),target:self,action:#selector(cancelWork));cancelButton.bezelStyle = .rounded;cancelButton.isEnabled=false
        cancelButton.image=NSImage(systemSymbolName:"stop.fill",accessibilityDescription:nil);cancelButton.imagePosition = .imageLeading;cancelButton.setAccessibilityLabel(L("Stop and keep partial results","עצור ושמור תוצאות חלקיות"))
        escapeMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){ [weak self] event in
            guard let self=self, event.keyCode == 53, self.busy, self.cancellable, !(self.window.firstResponder is NSTextView) else { return event }
            self.cancelWork();return nil // Esc stops a running scan, map or comparison
        }
        spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false
        status.font = .systemFont(ofSize:11);status.textColor = .secondaryLabelColor;status.lineBreakMode = .byTruncatingTail
        let footer=row([spinner,status,spacer(),cancelButton],8)
        tips=label(Self.reviewTips,11,.regular,true)
        spaceLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);spaceLabel.textColor = .secondaryLabelColor;spaceLabel.lineBreakMode = .byTruncatingTail;spaceLabel.isHidden=true
        spaceLabel.toolTip=L("Trash is not free space until you empty it in Finder. APFS clones and snapshots can make the freed amount differ.","הפח אינו מקום פנוי עד שמרוקנים אותו ב־Finder. שכפולי APFS ותמונות מצב עשויים לשנות את הכמות שמתפנה.")
        spaceLabel.setAccessibilityLabel(L("Session space summary","סיכום מקום בהפעלה זו"))
        let bottom=row([tips,spacer(),spaceLabel])
        let content=column([header,folderLabel,filters,analysis,ageHint,workspace,selection,divider(),review,footer,bottom],12)
        content.setCustomSpacing(20,after:header);content.setCustomSpacing(16,after:folderLabel)
        reviewOnlyViews=[filters,analysis,ageHint,selection,review]
        let host=NSView();host.addSubview(content);content.translatesAutoresizingMaskIntoConstraints=false
        let rootLayout=row([sidebar,host],0);rootLayout.alignment = .top;rootLayout.distribution = .fill;rootLayout.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(rootLayout)
        NSLayoutConstraint.activate([rootLayout.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),rootLayout.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),rootLayout.topAnchor.constraint(equalTo:window.contentView!.topAnchor),rootLayout.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor),sidebar.heightAnchor.constraint(equalTo:rootLayout.heightAnchor),host.widthAnchor.constraint(equalTo:rootLayout.widthAnchor,constant:-216),host.heightAnchor.constraint(equalTo:rootLayout.heightAnchor),content.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:26),content.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-26),content.topAnchor.constraint(equalTo:host.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:host.bottomAnchor,constant:-18),workspace.heightAnchor.constraint(greaterThanOrEqualToConstant:250)])
        for v in [header,folderLabel,filters,analysis,ageHint,workspace,selection,review,footer,bottom] {v.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true}
        makeMenus();modeChanged();updateEnabled();updatePreview();setOverview(true)
        status.stringValue=L("Ready — choose a location to start.","מוכן — בחר מיקום כדי להתחיל.")
        if smokeMode {runSmokeTests();return}
        if ProcessInfo.processInfo.arguments.contains("--launch-check") {print("Packaged launch passed: production preferences and interface initialized; no scan started.");fflush(stdout);exit(0)}
        if demoMode { prepareDemo() }
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(table);NSApp.activate(ignoringOtherApps:true)
    }
    func prepareDemo() {
        window.title="Avakasha · Read-only demo";window.setContentSize(NSSize(width:1190,height:768));window.center()
        let container=FileManager.default.temporaryDirectory.appendingPathComponent("Avakasha-Demo-"+UUID().uuidString,isDirectory:true)
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
            if ProcessInfo.processInfo.arguments.contains("--demo-overview") { setOverview(true) }
            if ProcessInfo.processInfo.arguments.contains("--demo-older") { showOlderFiles() }
            mapPanel.showsPaths=false;pathLabel.isHidden=true
            if overviewMode && !ProcessInfo.processInfo.arguments.contains("--demo-overview") { setOverview(false) } // the demo shows files unless asked for the overview
            window.minSize=NSSize(width:1190,height:768);window.setContentSize(NSSize(width:1190,height:768));window.center() // pin the demo window size
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
        writer.add(input);guard writer.startWriting() else { throw writer.error ?? NSError(domain:"Avakasha",code:4) }
        writer.startSession(atSourceTime:.zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.01) }
            var buffer:CVPixelBuffer?
            guard let pool=adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess, let pixels=buffer else { throw NSError(domain:"Avakasha",code:5) }
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
        if writer.status != .completed { throw writer.error ?? NSError(domain:"Avakasha",code:6) }
    }
    func applicationWillTerminate(_ notification:Notification) {
        if let demoFolder=demoFolder {try? FileManager.default.removeItem(at:demoFolder);preferences.removePersistentDomain(forName:"Avakasha.SyntheticDemo")}
    }
    func makeMenus() {
        let main = NSMenu(); let app = NSMenuItem(); main.addItem(app); let menu = NSMenu(); app.submenu = menu
        let about = NSMenuItem(title: L("About Avakasha", "אודות Avakasha"), action: #selector(aboutApp), keyEquivalent: ""); about.target = self; menu.addItem(about)
        menu.addItem(withTitle: L("Quit Avakasha","סגור Avakasha"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = L("Edit","עריכה"); main.addItem(edit); edit.submenu = NSMenu(title:L("Edit","עריכה"))
        for (title,selector,key) in [(L("Select all","בחר הכול"),#selector(selectAllCommand),"a"),(L("Undo","שחזר"),#selector(undoCommand),"z")] {
            let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target=self; edit.submenu!.addItem(item)
        }
        let redoItem=NSMenuItem(title:L("Redo","בצע שוב"),action:#selector(redoCommand),keyEquivalent:"z");redoItem.keyEquivalentModifierMask=[.command,.shift];redoItem.target=self;edit.submenu!.addItem(redoItem)
        let autoDownload=NSMenuItem(title:L("Stop WhatsApp auto-download…","עצירת הורדה אוטומטית בווטסאפ…"),action:#selector(openWhatsAppAutoDownload),keyEquivalent:"");autoDownload.target=self;menu.insertItem(autoDownload,at:1)
        menu.insertItem(.separator(),at:1)
        let confirmation=NSMenuItem(title:L("Confirm before Trash","אישור לפני העברה לפח"),action:#selector(toggleTrashConfirmation(_:)),keyEquivalent:"");confirmation.target=self;confirmation.state=preferences.bool(forKey:"skipTrashConfirmation") ? .off : .on;menu.insertItem(confirmation,at:2);confirmationMenuItem=confirmation
        // Standard text editing remains available in the search field.
        let copyItem=NSMenuItem(title:L("Copy","העתק"),action:#selector(copyCommand),keyEquivalent:"c");copyItem.target=self;edit.submenu!.addItem(copyItem)
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
        let a=NSAlert();a.messageText = hebrew ? "Avakasha תוצג בעברית בפתיחה הבאה" : "Avakasha will open in English next time"
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
            return !busy && !demoMode && !overviewMode && activeHistory.canUndo
        }
        if item.action == #selector(redoCommand) {
            if let editor=window.firstResponder as? NSTextView {return editor.undoManager?.canRedo ?? false}
            return !busy && !demoMode && !overviewMode && !mapMode && !freeUpMode && history.canRedo
        }
        return true
    }
    @objc func aboutApp() { show(L("Avakasha 0.1.0 beta 9", "Avakasha 0.1.0 בטא 9"), "© 2026 Daniel Siman Tov\n" + L("Contact: ","יצירת קשר: ") + "daniel.simisi@gmail.com\n\n" + L("Offline file review. MIT license. Not affiliated with WhatsApp or Meta. Undo is available for this app session; Finder Trash remains available afterward.","סקירת קבצים מקומית. רישיון MIT. ללא שיוך ל־WhatsApp או Meta. שחזור באפליקציה זמין במהלך ההפעלה הנוכחית; הפח של Finder נשאר זמין לאחר מכן.")) }
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
    /// The largest-files list is not a full scan of its root, so choosing that location scans it.
    func isCurrentRoot(_ url:URL) -> Bool {
        guard reviewSource == .scan, let current=root, let resolved=try? FileSafety.root(url) else { return false }
        return resolved.path == current.path
    }
    /// The sidebar highlights the view you are in: a location while its files are shown, the map, the overview or a review filter.
    func updateLocationHighlight() {
        let active = (!mapMode && !overviewMode && !freeUpMode) ? root?.path : nil
        func highlight(_ b: NSButton?, _ on: Bool, _ value: String) {
            guard let b=b else { return }
            b.wantsLayer=true;b.layer?.cornerRadius=7
            b.layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : nil
            b.contentTintColor = on ? .controlAccentColor : .labelColor
            b.setAccessibilityValue(on ? value : "")
        }
        for b in locationButtons {
            let matches = active != nil && reviewSource == .scan && locationURL(b.tag).flatMap{ try? FileSafety.root($0) }?.path == active
            highlight(b, matches, L("Current location","המיקום הנוכחי"))
        }
        let reviewing = !mapMode && !overviewMode && !freeUpMode && root != nil
        highlight(sidebarOverview, overviewMode, L("Current view","התצוגה הנוכחית"))
        highlight(sidebarMap, mapMode, L("Current view","התצוגה הנוכחית"))
        highlight(sidebarFreeUp, freeUpMode, L("Current view","התצוגה הנוכחית"))
        highlight(sidebarOlder, reviewing && mode.indexOfSelectedItem == 3, L("Current view","התצוגה הנוכחית"))
        highlight(sidebarInstallers, reviewing && mode.indexOfSelectedItem == 4, L("Current view","התצוגה הנוכחית"))
    }
    @objc func showOverview() { guard !busy else { return };setOverview(true) }
    @objc func showFreeUp() { guard !busy else { return };setFreeUp(true) }
    func setFreeUp(_ on:Bool) {
        freeUpMode=on
        if on {
            if overviewMode { setOverview(false) };if mapMode { mapMode=false }
            reviewOnlyViews.forEach{$0.isHidden=true};scroll.isHidden=true;mapPanel.isHidden=true;mapPanel.detail.isHidden=true;overviewPanel.isHidden=true;emptyList.isHidden=true
            previewHostView.isHidden=false;previewPlaceholder.isHidden=true;primary.isHidden=true;comparison.isHidden=true;primary.previewItem=nil;comparison.previewItem=nil;stopVideo()
            freeUpPanel.home=home;freeUpPanel.reload(keepMeasurements:true);freeUpPanel.isHidden=false;freeUpPanel.detail.isHidden=false
            headingLabel.stringValue=L("Free up space","פינוי מקום");folderLabel.stringValue=L("Known caches and app data in your home folder · measured only when you ask","מטמונים ונתוני אפליקציות מוכרים בתיקיית הבית · נמדדים רק כשתבקש")
            tips.stringValue=L("Measure all · sizes     Move to Trash… · only for data the app rebuilds     ⌘Z · Undo","מדוד הכול · גדלים     העבר לפח… · רק לנתונים שהאפליקציה בונה מחדש     ⌘Z · שחזור")
            status.stringValue = freeUpPanel.rows.isEmpty ? L("Nothing from the known list exists in this home folder.","לא נמצא כאן דבר מהרשימה המוכרת.") : "\(freeUpPanel.rows.count) "+L("known locations · press Measure all","מיקומים מוכרים · לחץ מדוד הכול")
            updateEnabled();updateLocationHighlight();updateSpaceLabel();window.makeFirstResponder(freeUpPanel.table)
        } else {
            freeUpPanel.isHidden=true;freeUpPanel.detail.isHidden=true;previewHostView.isHidden=false
        }
    }
    /// Measures known locations one by one on the work queue; cancel keeps what was measured so far.
    func measureLocations(_ locations:[KnownLocation]) {
        guard !busy, !locations.isEmpty else { return }
        token=CancellationToken();let jobToken=token;let base=freeUpPanel.home;setBusy(true)
        work.async {
            var done=0
            for location in locations {
                if jobToken.isCancelled { break }
                DispatchQueue.main.async { self.status.stringValue=L("Measuring ","מודד ")+LocationTexts.text(for:location).title+"…" }
                let measurement=KnownLocations.measure(location,home:base,token:jobToken)
                if measurement.cancelled { break };done += 1
                DispatchQueue.main.async { self.freeUpPanel.apply(measurement) }
            }
            let finished=done
            DispatchQueue.main.async {
                self.setBusy(false)
                let stopped = jobToken.isCancelled ? " · "+L("Stopped · partial","נעצר · חלקי") : ""
                self.status.stringValue="\(finished) "+L("measured","נמדדו")+" · "+bytes(self.freeUpPanel.measuredTotal)+" · "+L("of which ","מתוכם ")+bytes(self.freeUpPanel.rebuildableTotal)+" "+L("is data the owning apps rebuild","נתונים שהאפליקציות בונות מחדש")+stopped
                self.updateEnabled()
            }
        }
    }
    /// Whole-folder move for a known, rebuildable location: same guarded flow as the map, with the home folder as the safety root.
    func trashLocation(_ location:KnownLocation,measured:LocationMeasurement,confirmed:Bool=false) {
        guard !busy, location.safety == .rebuildable, let base=try? FileSafety.root(freeUpPanel.home) else { return }
        let text=LocationTexts.text(for:location)
        trashFolder(location.url(home:base),root:base,title:text.title,explanation:text.what+"\n"+L("If removed: ","אם יוסר: ")+text.next,confirmed:confirmed,fromCatalogue:true) { [weak self] in
            self?.freeUpPanel.markMoved(location)
        }
    }
    /// Whole-folder move from the storage map.
    func trashFolderFromMap(_ node:StorageNode,confirmed:Bool=false) {
        guard !busy, let target=mapRoot else { return }
        trashFolder(node.url,root:target,title:node.name,explanation:nil,confirmed:confirmed) { [weak self] in
            guard let self=self else { return }
            self.mapPanel.remove(node);self.mapStale=true;self.mapPanel.setStale(true)
            let prefix=node.url.path+"/";if self.files.contains(where:{ $0.id.hasPrefix(prefix) }) { self.files.removeAll{ $0.id.hasPrefix(prefix) };self.exact=[];self.similar=[];self.guards=[:] };if !self.mapMode { self.applyFilters() }
        }
    }
    /// The one path every whole-folder move takes: check, measure again, confirm with fresh numbers, move with identity checks, record for Undo.
    /// Wording for the core's folder refusals, in the interface language.
    func folderErrorText(_ error:Error) -> String {
        switch error as? TriageError {
        case .unsafePath?: return L("The folder is outside the chosen root, or is a link.","התיקייה נמצאת מחוץ לתיקיית הבסיס, או שהיא קישור.")
        case .changed?: return L("The folder changed since it was measured. Measure it again before moving it.","התיקייה השתנתה מאז שנמדדה. מדוד אותה שוב לפני ההעברה.")
        case .folderProtected?: return L("Bundles, hidden folders, folders under hidden folders, the home folder and system folders are never moved as a whole. Review the files inside instead.","חבילות, תיקיות מוסתרות, תיקיות תחת תיקיות מוסתרות, תיקיית הבית ותיקיות מערכת לעולם לא מועברות בשלמותן. סקור את הקבצים שבפנים במקום.")
        case .notLocal?: return L("The folder is on another volume or not downloaded.","התיקייה נמצאת בכונן אחר או שלא הורדה.")
        default: return error.localizedDescription
        }
    }
    /// The always-on confirmation for a whole-folder move: fresh numbers, path, Cancel as the default button.
    func makeFolderTrashAlert(title:String,fresh:StorageMapResult,folder:URL,explanation:String?) -> NSAlert {
        let a=NSAlert();a.alertStyle = .critical;a.messageText=L("Move the folder “","להעביר את התיקייה ״")+title+L("” to Trash?","״ לפח?")
        var lines=[bytes(fresh.root.bytes)+" · \(fresh.root.files) "+L("files","קבצים")+" · \(fresh.root.directories) "+L("folders","תיקיות"),(folder.path as NSString).abbreviatingWithTildeInPath]
        if let explanation=explanation { lines.append(explanation) }
        lines.append(L("Everything inside goes to Trash as one item. Undo with ⌘Z in this session.","כל מה שבפנים עובר לפח כפריט אחד. אפשר לשחזר עם ⌘Z בהפעלה הזו."))
        a.informativeText=lines.joined(separator:"\n")
        let move=a.addButton(withTitle:L("Move to Trash","העבר לפח"));let cancel=a.addButton(withTitle:L("Cancel","בטל"))
        move.keyEquivalent="";cancel.keyEquivalent="\r";move.hasDestructiveAction=true // Return cancels; moving needs a deliberate click
        return a
    }
    /// Test hook: nil asks the user, true or false answers the folder confirmation without a dialog.
    var folderConfirmationOverride: Bool?
    func trashFolder(_ folder:URL,root:URL,title:String,explanation:String?,confirmed:Bool,fromCatalogue:Bool=false,onMoved:@escaping ()->Void) {
        guard !busy,!demoMode else { return }
        let expected:FolderIdentity
        do { expected=try FolderTrash.check(folder,root:root,allowHiddenAncestors:fromCatalogue) } catch { show(L("This folder cannot be moved as a whole","לא ניתן להעביר את התיקייה הזו בשלמותה"),folderErrorText(error));status.stringValue=L("Nothing moved","שום דבר לא הועבר");return }
        token=CancellationToken();let jobToken=token;setBusy(true);status.stringValue=L("Measuring ","מודד ")+title+"…"
        work.async {
            let fresh=try? StorageMapper.map(root:folder,token:jobToken,limit:0)
            DispatchQueue.main.async {
                self.setBusy(false)
                guard let fresh=fresh, !fresh.cancelled else { self.status.stringValue=L("Stopped · nothing moved","נעצר · שום דבר לא הועבר");return }
                if fresh.root.hasCaveats { self.show(L("Not moved","לא הועבר"),L("The folder holds items that could not be measured (not accessible, not downloaded, or on another volume). Review its files instead.","התיקייה מכילה פריטים שלא ניתן היה למדוד (לא נגישים, לא הורדו, או בכונן אחר). סקור את הקבצים שלה במקום.")); return }
                if !confirmed {
                    let approved: Bool
                    if let override=self.folderConfirmationOverride { approved=override }
                    else if self.smokeMode { approved=true }
                    else { approved = self.makeFolderTrashAlert(title:title,fresh:fresh,folder:folder,explanation:explanation).runModal() == .alertFirstButtonReturn }
                    guard approved else { self.status.stringValue=L("Nothing moved","שום דבר לא הועבר");return }
                }
                let acting=self.historyFor(root);self.setBusy(true,cancellable:false)
                self.work.async {
                    let result=acting.moveFolder(folder,root:root,expected:expected,bytes:fresh.root.bytes,allowHiddenAncestors:fromCatalogue,backend:self.trashBackend)
                    DispatchQueue.main.async {
                        self.setBusy(false)
                        if result.ticket != nil { onMoved();self.status.stringValue=title+" · "+L("moved to Trash · Undo with ⌘Z","הועבר לפח · שחזור עם ⌘Z")+" · "+bytes(fresh.root.bytes);self.updateSpaceLabel();self.updateEnabled() }
                        else if let failure=result.failure { self.show(L("Not moved","לא הועבר"),failure.message) }
                    }
                }
            }
        }
    }
    func setOverview(_ on:Bool) {
        guard on != overviewMode || on else { return }
        overviewMode=on
        if on {
            if mapMode { mapMode=false };if freeUpMode { setFreeUp(false) }
            reviewOnlyViews.forEach{$0.isHidden=true};scroll.isHidden=true;mapPanel.isHidden=true;mapPanel.detail.isHidden=true
            overviewPanel.isHidden=false;previewHostView.isHidden=true;emptyList.isHidden=true
            headingLabel.stringValue=L("Overview","סקירה כללית");folderLabel.stringValue=L("Disks, this session and where to start","כוננים, ההפעלה הזו ומאיפה להתחיל")
            tips.stringValue=L("Choose a location to review its files, or map a folder or drive to see what fills it.","בחר מיקום כדי לסקור את הקבצים שלו, או מפה תיקייה או כונן כדי לראות מה ממלא אותו.")
            mapButton.title=L("Storage map","מפת אחסון");mapButton.image=NSImage(systemSymbolName:"chart.pie",accessibilityDescription:nil)
            primary.previewItem=nil;comparison.previewItem=nil;stopVideo()
            overviewPanel.update(sessionMoved:totalMovedBytes)
            updateEnabled();updateLocationHighlight();window.makeFirstResponder(overviewPanel.mapHomeButton)
        } else {
            overviewPanel.isHidden=true;previewHostView.isHidden=false
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
        if mapMode { if let target=mapRoot { startMap(target) } }
        else if reviewSource == .largestFiles, let target=largestRoot { pendingLargestReview=true;startMap(target) }
        else if let root=root { startScan(root) }
    }
    @objc func cancelWork() { guard busy, cancellable else { return };token.cancel();status.stringValue=L("Stopping… keeping what was found","עוצר… שומר את מה שנמצא");cancelButton.isEnabled=false;rescanButton.isEnabled=false }
    func setBusy(_ value: Bool, cancellable: Bool = true) {
        busy=value;self.cancellable = value && cancellable;updateEnabled()
        if value{spinner.startAnimation(nil)}else{spinner.stopAnimation(nil)}
        // While something can be stopped, Refresh turns into a red Stop so the way out is obvious.
        let stopping = value && cancellable
        rescanButton?.title = stopping ? L("Stop","עצור") : L("Refresh","רענן")
        rescanButton?.image = NSImage(systemSymbolName: stopping ? "stop.fill" : "arrow.clockwise",accessibilityDescription:nil)
        rescanButton?.contentTintColor = stopping ? .systemRed : nil
        rescanButton?.action = stopping ? #selector(cancelWork) : #selector(rescanFolder);rescanButton?.setAccessibilityLabel(rescanButton.title)
        rescanButton?.toolTip = stopping ? L("Stop now and keep the files found so far (Esc)","עצור עכשיו ושמור את הקבצים שנמצאו עד כה (Esc)") : nil
    }
    func updateEnabled() {
        buttons.forEach { b in
            let requiresSelection: Set<Selector> = [#selector(togglePreview),#selector(nextFile),#selector(trashSelection),#selector(deselect)]
            let requiresFiles: Set<Selector> = [#selector(selectAllFiles),#selector(findExactDuplicates),#selector(findSimilarImages)]
            b.isEnabled = !busy
            if let action=b.action, requiresSelection.contains(action) { b.isEnabled = !busy && !selectedFiles.isEmpty }
            if let action=b.action, requiresFiles.contains(action) { b.isEnabled = !busy && !files.isEmpty }
            if b.action == #selector(showOlderFiles) || b.action == #selector(showInstallers) { b.isEnabled = !busy && root != nil }
            if b.action == #selector(rescanFolder) { b.isEnabled = !busy && !overviewMode && (mapMode ? mapRoot != nil : root != nil);b.isHidden = overviewMode }
            if b.action == #selector(cancelWork) && b !== cancelButton { b.isEnabled = busy && cancellable && !token.isCancelled }
            if b.action == #selector(showStorageMap) { b.isEnabled = !busy && (overviewMode ? true : (mapMode ? root != nil : (root != nil || mapPanel.result != nil)));b.isHidden = overviewMode && mapPanel.result == nil }
            if b.action == #selector(showOverview) { b.isEnabled = !busy }
            if b.action == #selector(retryRestore) { b.isEnabled = !busy && !demoMode && !overviewMode && activeHistory.blockedCount > 0 }
            if b.action == #selector(showFreeUp) { b.isEnabled = !busy }
            if demoMode && (b.action == #selector(trashSelection) || b.action == #selector(undoTrash) || b.action == #selector(redoTrash)) { b.isEnabled=false }
            if b.action == #selector(resumeFolder) { b.isEnabled = !busy && preferences.string(forKey:"lastFolder") != nil }
        }; cancelButton?.isEnabled = busy && cancellable && !token.isCancelled
        [sizeFilter,kindFilter,mode,groupPicker,agePicker,sortPicker,chatFilter].forEach{$0.isEnabled = !busy};search.isEnabled = !busy;chatNamesButton?.isEnabled = !busy
        undoButton?.isEnabled = !busy && !demoMode && !overviewMode && activeHistory.canUndo
        redoButton?.isEnabled = !busy && !demoMode && !overviewMode && !mapMode && !freeUpMode && history.canRedo
        if !busy { retryButton?.isHidden = activeHistory.blockedCount == 0 } // history is only touched by the work queue while busy
        freeUpPanel.setEnabled(!busy)
        mapPanel.setEnabled(!busy)
        extrasButton?.isEnabled = !busy && mode.indexOfSelectedItem == 1 && !exact.isEmpty
        extrasButton?.isHidden = mode.indexOfSelectedItem != 1
    }
    func activateRoot(_ selectedRoot: URL) {
        if let root=root {folderHistories[root.path]=history}
        history=folderHistories[selectedRoot.path] ?? TrashHistory()
        root=selectedRoot;updateSpaceLabel()
    }
    /// Bytes this session moved to Trash across every folder history, each history counted once.
    /// The history the current view acts on: the map's root while the map is shown, the home folder in Free up space, otherwise the reviewed root.
    var activeHistory: TrashHistory {
        if freeUpMode, let h=try? FileSafety.root(home) { return historyFor(h) }
        if mapMode, let target=mapRoot { return historyFor(target) }
        return history
    }
    func historyFor(_ target:URL) -> TrashHistory {
        if let current=root, current.path == target.path { return history }
        if let existing=folderHistories[target.path] { return existing }
        let fresh=TrashHistory();folderHistories[target.path]=fresh;return fresh
    }
    var totalMovedBytes:Int64 {
        var seen=Set<ObjectIdentifier>();var total:Int64=0
        for h in [history]+Array(folderHistories.values) where seen.insert(ObjectIdentifier(h)).inserted {total+=h.sessionMovedBytes}
        return total
    }
    /// Two honest numbers side by side: what was moved (still in Trash) and what the volume reports free. Never a prediction.
    func updateSpaceLabel() {
        guard let anchor = freeUpMode ? freeUpPanel.home : (root ?? mapRoot) else { spaceLabel.isHidden=true;return }
        var text = totalMovedBytes > 0 ? L("Moved to Trash this session: ","הועבר לפח בהפעלה זו: ")+bytes(totalMovedBytes) : L("Nothing moved to Trash yet","עדיין לא הועבר דבר לפח")
        if let free=DiskSpace.available(at:anchor) { text += " · "+L("Free on this volume: ","פנוי בכונן הזה: ")+bytes(free) }
        spaceLabel.stringValue=text;spaceLabel.isHidden=false
        if overviewMode { overviewPanel.update(sessionMoved:totalMovedBytes) }
    }
    func startScan(_ url: URL) {
        guard !busy else{return}
        do { activateRoot(try FileSafety.root(url)) } catch { show(L("Cannot scan this folder","לא ניתן לסרוק את התיקייה"),error.localizedDescription);return }
        reviewSource = .scan;if overviewMode { setOverview(false) };if freeUpMode { setFreeUp(false) };if mapMode { setMapMode(false) }
        let selectedRoot=root!;preferences.set(selectedRoot.path,forKey:"lastFolder");folderLabel.stringValue=selectedRoot.path;updateLocationHighlight()
        if chatNamesSource != ChatDirectory.databaseURL(near:selectedRoot) { chatNames=[:];chatNamesSource=nil }
        chatFilter.removeAllItems()
        primary.previewItem=nil;comparison.previewItem=nil;stopVideo();files=[];exact=[];similar=[];guards=[:];mode.selectItem(at:0);modeChanged()
        token=CancellationToken();let jobToken=token;setBusy(true);refreshEmptyState();status.stringValue=L("Scanning file metadata…","סורק שמות וגדלים…")
        work.async {
            do {
                let result=try Scanner.scan(root:selectedRoot,token:jobToken){count in DispatchQueue.main.async{self.status.stringValue=L("Scanning: ","נסרקו: ")+String(count)}}
                DispatchQueue.main.async {
                    self.files=result.files;self.setBusy(false);self.applyFilters();self.updateSpaceLabel()
                    self.status.stringValue="\(result.files.count) "+L("files","קבצים")+" · \(result.skipped) "+L("skipped","דולגו") + (result.cancelled ? " · "+L("Stopped · partial results","נעצר · תוצאות חלקיות") : "")
                    if let last=self.preferences.string(forKey:"lastFile"),let i=self.shown.firstIndex(where:{$0.id==last}) {self.table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);self.table.scrollRowToVisible(i)}
                }
            } catch {DispatchQueue.main.async{self.setBusy(false);self.show(L("Scan failed","הסריקה נכשלה"),error.localizedDescription)}}
        }
    }
    // MARK: Storage map
    func setMapMode(_ on:Bool) {
        if overviewMode { setOverview(false) };if freeUpMode { setFreeUp(false) }
        mapMode=on
        reviewOnlyViews.forEach{$0.isHidden=on}
        scroll.isHidden=on;mapPanel.isHidden = !on;mapPanel.detail.isHidden = !on
        headingLabel.stringValue = on ? L("Where is the space?","איפה המקום?") : L("Your files","הקבצים שלך")
        tips.stringValue = on ? L("Return · Open folder     ⌘↑ · Up     Review files here · Switch to file review","Return · פתיחת תיקייה     ⌘↑ · למעלה     סקור קבצים כאן · מעבר לסקירת קבצים") : Self.reviewTips
        mapButton.title = on ? L("Back to files","חזרה לקבצים") : L("Storage map","מפת אחסון")
        mapButton.image = NSImage(systemSymbolName: on ? "list.bullet" : "chart.pie",accessibilityDescription:nil);mapButton.setAccessibilityLabel(mapButton.title)
        if on {
            if !demoMode { folderLabel.stringValue = mapRoot?.path ?? folderLabel.stringValue }
            mapPanel.setStale(mapStale)
            if mapStale, let result=mapPanel.result { status.stringValue=mapSummary(result)+" · "+L("changed since measured · Rescan","השתנה מאז המדידה · מדוד מחדש") }
            primary.previewItem=nil;comparison.previewItem=nil;stopVideo();previewPlaceholder.isHidden=true;primary.isHidden=true;comparison.isHidden=true
        } else {
            if !demoMode { folderLabel.stringValue = root.map{ $0.path + (reviewSource == .largestFiles ? " · "+L("largest files","הקבצים הגדולים") : "") } ?? L("Choose a location from the sidebar to begin","בחר מיקום מהסרגל הצדדי כדי להתחיל") }
            ageHint.isHidden = !usesAge;comparison.isHidden = !(mode.indexOfSelectedItem == 1 || mode.indexOfSelectedItem == 2);updateSelection()
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
            emptyListTitle?.stringValue = busy ? L("Scanning…","סורק…") : (root == nil ? L("Start somewhere simple","מתחילים בתיקייה אחת") : (reviewSource == .largestFiles && files.isEmpty ? L("No reviewable large files here","אין כאן קבצים גדולים לסקירה") : L("No matching files","אין קבצים מתאימים")))
            emptyListDetail?.stringValue = busy ? L("Reading names and sizes only. Cancel keeps what was found.","קורא רק שמות וגדלים. ביטול שומר את מה שנמצא.") : (root == nil ? L("Choose a location from the sidebar","בחר מיקום מהסרגל הצדדי") : (reviewSource == .largestFiles && files.isEmpty ? L("The map found nothing here that file review can show","המפה לא מצאה כאן דבר שסקירת הקבצים יכולה להציג") : L("Try another filter or location","נסה מסנן אחר או מיקום אחר")))
            let last=preferences.string(forKey:"lastFolder")
            continueLink.isHidden = busy || root != nil || last == nil || demoMode
            continueLink.stringValue = last.map{ L("Continue: ","המשך: ")+displayPath(URL(fileURLWithPath:$0)) } ?? "";continueLink.toolTip=last
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
        if overviewMode { if mapPanel.result != nil, let target=mapRoot { setOverview(false);mapRoot=target;setMapMode(true);window.makeFirstResponder(mapPanel.table) } else { chooseMapFolder() };return }
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
        mapRoot=target;mapPanel.load(nil);if overviewMode { setOverview(false) };setMapMode(true);folderLabel.stringValue=target.path;updateLocationHighlight()
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
                    self.setBusy(false);self.mapStale=false;self.mapPanel.load(result);self.mapPanel.setStale(false);self.refreshEmptyState();self.updateSpaceLabel()
                    self.status.stringValue=self.mapSummary(result);self.window.makeFirstResponder(self.mapPanel.table)
                    if self.pendingLargestReview { self.pendingLargestReview=false;self.reviewLargestFiles() }
                }
            } catch {DispatchQueue.main.async{self.pendingLargestReview=false;self.setBusy(false);self.refreshEmptyState();self.show(L("Cannot map this folder","לא ניתן למפות את התיקייה"),error.localizedDescription)}}
        }
    }
    func mapSummary(_ result:StorageMapResult)->String {
        let r=result.root
        var parts=[bytes(r.bytes)+" · \(r.files) "+L("files","קבצים")+" · \(r.directories) "+L("folders","תיקיות")]
        if r.inaccessible>0 {parts.append("\(r.inaccessible) "+L("not accessible","לא נגישים"))}
        if r.notDownloaded>0 {parts.append("\(r.notDownloaded) "+L("not downloaded","לא הורדו"))}
        if r.otherVolumes>0 {parts.append("\(r.otherVolumes) "+L("other volumes skipped","כוננים אחרים דולגו"))}
        if result.sharedFiles>0 {parts.append("\(result.sharedFiles) "+L("hard links counted once","קישורים קשיחים נספרו פעם אחת"))}
        if result.cancelled {parts.append(L("Stopped · partial results","נעצר · תוצאות חלקיות"))}
        return parts.joined(separator:" · ")
    }
    func reviewFromMap(_ url:URL) { guard !busy else{return};startScan(url) }
    /// The map's largest files as a review list. Every file is re-validated against the map root, so the list can
    /// never hold a file outside it or one that changed since the map was measured.
    @objc func reviewLargestFiles() {
        guard !busy, let result=mapPanel.result, let mapRoot=mapRoot else { return }
        activateRoot(mapRoot);reviewSource = .largestFiles;largestRoot=mapRoot
        files=result.largestFiles.compactMap{ f in guard let record=try? FileRecord(url:f.url), (try? FileSafety.validate(record,root:mapRoot)) != nil else { return nil };return record }
        if chatNamesSource != ChatDirectory.databaseURL(near:mapRoot) { chatNames=[:];chatNamesSource=nil }
        chatFilter.removeAllItems();primary.previewItem=nil;comparison.previewItem=nil;stopVideo();exact=[];similar=[];guards=[:]
        mode.selectItem(at:0);sortPicker.selectItem(at:ReviewSort.largest.rawValue);setMapMode(false);changeSort();modeChanged()
        folderLabel.stringValue=mapRoot.path+" · "+L("largest files","הקבצים הגדולים");updateLocationHighlight()
        if files.isEmpty { status.stringValue=L("No reviewable large files here","אין כאן קבצים גדולים לסקירה") }
        else { status.stringValue="\(files.count) "+L("largest files under ","הקבצים הגדולים ביותר תחת ")+mapRoot.lastPathComponent+" · "+L("sizes are space on disk","הגדלים הם מקום בדיסק") }
        // The map's own caveats travel with the list: a stopped or stale measurement is not a complete top list.
        if result.cancelled { status.stringValue += " · "+L("Stopped · partial results","נעצר · תוצאות חלקיות") }
        if mapStale { status.stringValue += " · "+L("changed since measured · Refresh","השתנה מאז המדידה · רענן") }
        if !shown.isEmpty { table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);table.scrollRowToVisible(0) }
        window.makeFirstResponder(table)
    }
    func revealFolder(_ url:URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    var currentGroups: [DuplicateGroup] {mode.indexOfSelectedItem == 1 ? exact : (mode.indexOfSelectedItem == 2 ? similar : [])}
    /// Older files and Installers & archives both take their cutoff from the age popup.
    var usesAge: Bool { mode.indexOfSelectedItem == 3 || mode.indexOfSelectedItem == 4 }
    @objc func modeChanged() {
        groupPicker.removeAllItems();groupPicker.addItem(withTitle:L("All groups","כל הקבוצות"))
        for (i,g) in currentGroups.enumerated(){groupPicker.addItem(withTitle:"\(i+1) · \(g.members.count) files")}
        let duplicates = mode.indexOfSelectedItem == 1 || mode.indexOfSelectedItem == 2
        groupPicker.isHidden = !duplicates;comparison.isHidden = !duplicates
        agePicker.isHidden = !usesAge;ageHint.isHidden = !usesAge;ageHint.stringValue = mode.indexOfSelectedItem == 4 ? Self.installerHintText : Self.ageHintText
        table.deselectAll(nil);guards=[:];applyFilters();updateEnabled();updateLocationHighlight()
    }
    @objc func applyFilters() {
        let old=Set(selectedFiles.map(\.id));let threshold:[Int64]=[0,10_000_000,100_000_000,1_000_000_000]
        let groupIndex=groupPicker.indexOfSelectedItem-1
        let groups=currentGroups
        let members:Set<String>? = (mode.indexOfSelectedItem==0 || usesAge) ? nil : Set((groupIndex>=0 && groupIndex<groups.count ? groups[groupIndex].members : groups.flatMap(\.members)).map(\.id))
        let query=search.stringValue.lowercased()
        let months=[6,12,24,60][max(0,agePicker.indexOfSelectedItem)]
        let cutoff=Calendar.current.date(byAdding:.month,value:-months,to:Date()) ?? .distantPast
        var candidates=mode.indexOfSelectedItem == 3 ? ReviewQuery.older(files,than:cutoff) : (mode.indexOfSelectedItem == 4 ? ReviewQuery.installers(files,olderThan:cutoff) : files)
        chatFilter.isHidden = !files.contains{ ChatFolders.kind(of:$0.url) != nil }
        chatNamesButton?.isHidden = chatFilter.isHidden || !chatNames.isEmpty
        autoDownloadButton?.isHidden = chatFilter.isHidden
        if chatFilter.numberOfItems <= 4 { rebuildChatFilter() }
        if !chatFilter.isHidden {
            if let identifier=chatFilter.selectedItem?.representedObject as? String { candidates=candidates.filter{ ChatDirectory.identifier(of:$0.url) == identifier } }
            else if chatFilter.indexOfSelectedItem > 0 && chatFilter.indexOfSelectedItem <= ChatKind.allCases.count { candidates=ChatFolders.filter(candidates,kind:ChatKind.allCases[chatFilter.indexOfSelectedItem-1]) }
        }
        let starMode=starFilter.indexOfSelectedItem
        func passesStar(_ f:FileRecord)->Bool { switch starMode {case 1:return starred.contains(f.id);case 2:return !starred.contains(f.id);case 3:return !reviewed.isReviewed(f);case 4:return reviewed.isReviewed(f);default:return true} }
        shown=candidates.filter { f in
            passesStar(f) &&
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
        guard !busy, let root=root else { return }
        var database=ChatDirectory.databaseURL(near:root)
        if database == nil {
            guard !smokeMode else { return }
            let p=NSOpenPanel();p.canChooseFiles=true;p.canChooseDirectories=false;p.allowsMultipleSelection=false;p.prompt=L("Use this list","השתמש ברשימה זו")
            p.directoryURL=root.deletingLastPathComponent().deletingLastPathComponent()
            p.message=L("WhatsApp's chat list (ChatStorage.sqlite) was not found near this folder. Locate it; it is usually in the WhatsApp group container. It will be opened read-only.","רשימת השיחות של ווטסאפ (ChatStorage.sqlite) לא נמצאה ליד התיקייה הזו. אתר אותה; בדרך כלל היא בקונטיינר של ווטסאפ. היא תיפתח לקריאה בלבד.")
            guard p.runModal() == .OK, let chosen=p.url, chosen.lastPathComponent == ChatDirectory.databaseName else { return }
            database=chosen
        }
        guard let database=database else { return }
        if !confirmed && !smokeMode {
            let a=NSAlert();a.messageText=L("Show chat names?","להציג שמות שיחות?")
            a.informativeText=L("Avakasha will open WhatsApp's local chat list read-only and read only each chat's identifier, display name and type, to label folders. Messages, contacts and media references are not read. Nothing is stored or sent anywhere. Close WhatsApp first if it reports the list as busy.","Avakasha תפתח את רשימת השיחות המקומית של ווטסאפ לקריאה בלבד ותקרא רק מזהה, שם תצוגה וסוג של כל שיחה, כדי לתייג תיקיות. הודעות, אנשי קשר והפניות למדיה לא נקראים. שום דבר לא נשמר ולא נשלח. אם הרשימה מדווחת כתפוסה, סגור את ווטסאפ קודם.")
            a.addButton(withTitle:L("Show names","הצג שמות"));a.addButton(withTitle:L("Cancel","בטל"))
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        setBusy(true,cancellable:false);status.stringValue=L("Reading chat list…","קורא רשימת שיחות…")
        work.async {
            let result=Result{ try ChatDirectory.load(from:database) }
            DispatchQueue.main.async {
                self.setBusy(false)
                switch result {
                case .success(let chats):
                    self.chatNames=chats;self.chatNamesSource=database;self.chatNamesButton.isHidden=true;self.mapPanel.chatNames=chats;self.rebuildChatFilter();self.applyFilters()
                    let folders=Set(self.files.compactMap{ ChatDirectory.identifier(of:$0.url) });let matched=folders.filter{ chats[$0] != nil }.count
                    self.status.stringValue="\(matched) / \(folders.count) "+L("chat folders named","תיקיות שיחה קיבלו שם")+" · \(chats.count) "+L("chats in the list · read-only, nothing stored","שיחות ברשימה · לקריאה בלבד, לא נשמר")
                    if matched < folders.count { self.status.stringValue += " · "+L("unmatched folders keep their identifier","תיקיות ללא התאמה נשארות עם המזהה") }
                case .failure(let error): self.show(L("Chat names unavailable","שמות שיחות אינם זמינים"),error.localizedDescription)
                }
            }
        }
    }
    @objc func showOlderFiles() { guard !busy,root != nil else{return};if overviewMode {setOverview(false)};setMapMode(false);mode.selectItem(at:3);modeChanged();updateLocationHighlight();window.makeFirstResponder(table) }
    @objc func showInstallers() { guard !busy,root != nil else{return};if overviewMode {setOverview(false)};setMapMode(false);mode.selectItem(at:4);modeChanged();updateLocationHighlight();window.makeFirstResponder(table) }
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
        if tableColumn?.identifier.rawValue == "star" {
            let on=starred.contains(f.id);let kept = !on && reviewed.isReviewed(f) // a star always wins over the reviewed mark
            let label = on ? L("Starred","עם כוכב") : (kept ? L("Reviewed and kept","נסקר ונשמר") : L("Star","כוכב"))
            let b=NSButton(image:NSImage(systemSymbolName:on ? "star.fill" : (kept ? "checkmark.circle.fill" : "star"),accessibilityDescription:on ? L("Starred","עם כוכב") : (kept ? label : L("Not starred","ללא כוכב")))!,target:self,action:kept ? #selector(reviewedClicked(_:)) : #selector(starClicked(_:)))
            b.isBordered=false;b.contentTintColor = on ? .systemYellow : (kept ? .systemGreen : .tertiaryLabelColor);b.tag=row
            b.toolTip = kept ? L("Reviewed and kept · click or K to review again","נסקר ונשמר · לחיצה או K לסקירה מחדש") : L("Star this file (S)","סמן בכוכב (S)");b.setAccessibilityLabel(label);return b
        }
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
        if let f=focused, reviewed.isReviewed(f) { selectionLabel.stringValue += " · "+L("reviewed","נסקר") }
        pathLabel.stringValue = focused.map{ displayPath($0.url) } ?? "";pathLabel.toolTip = focused?.url.path
        updateKindBadge(focused);updateChatBadge(focused)
        refreshEmptyState()
        if let f=chosen.first{preferences.set(f.id,forKey:"lastFile")};updatePreview();updateEnabled()
    }
    static func kindTitle(_ kind:FileKind) -> String {
        switch kind {case .image:return L("Image","תמונה");case .video:return L("Video","וידאו");case .audio:return L("Audio","שמע");case .document:return L("Document","מסמך");case .archive:return L("Archive","ארכיון");case .other:return L("File","קובץ")}
    }
    static func installerTitle(_ kind:InstallerKind) -> String {
        switch kind {case .diskImage:return L("Disk image","דמות דיסק");case .package:return L("Package","חבילת התקנה");case .archive:return L("Archive","ארכיון")}
    }
    static func kindColor(_ kind:FileKind) -> NSColor {
        switch kind {case .video:return .systemPurple;case .image:return .systemTeal;case .audio:return .systemOrange;default:return .secondaryLabelColor}
    }
    /// Shows the type at a glance; adds pixel size for images and duration for videos (metadata only, read locally).
    func updateKindBadge(_ file:FileRecord?) {
        mediaInfoGeneration += 1;let generation=mediaInfoGeneration
        guard let f=file else { kindBadge.isHidden=true;return }
        let installer=ReviewQuery.installerKind(f.url);let color:NSColor = installer == nil ? Self.kindColor(f.kind) : .systemIndigo
        func show(_ text:String) { kindBadge.stringValue="  "+text+"  ";kindBadge.textColor=color;kindBadge.layer?.backgroundColor=color.withAlphaComponent(0.16).cgColor;kindBadge.isHidden=false }
        show((installer.map(Self.installerTitle) ?? Self.kindTitle(f.kind)).uppercased())
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
    /// Puts the full path on the pasteboard as text, plus the file itself for pasting into Finder or a chat.
    @discardableResult func copyFocusedPath() -> Bool {
        guard let f=focusedFile else { return false }
        let board=NSPasteboard.general;board.clearContents();board.writeObjects([f.url as NSURL]);board.setString(f.url.path,forType:.string)
        status.stringValue=L("Path copied","הנתיב הועתק")+" · "+displayPath(f.url);return true
    }
    @objc func copyCommand() {
        if let text=window.firstResponder as? NSText { text.copy(nil) } else if !copyFocusedPath() { NSSound.beep() }
    }
    /// Opens the enclosing folder in Finder with the file selected, after the usual identity check.
    func revealFocusedFile() {
        guard !busy, let f=focusedFile, let root=root else { return }
        do { try FileSafety.validate(f,root:root);NSWorkspace.shared.activateFileViewerSelecting([f.url]) } catch { show(L("File unavailable","הקובץ אינו זמין"),error.localizedDescription) }
    }
    /// Names the WhatsApp chat of the highlighted file: display name once the chat list was loaded, otherwise the folder identifier.
    func updateChatBadge(_ file:FileRecord?) {
        guard let f=file, let id=ChatDirectory.identifier(of:f.url) else { chatBadge.isHidden=true;return }
        let kind=chatNames[id]?.kind ?? ChatFolders.kind(of:f.url) ?? .personal
        let symbol = kind == .group ? "person.3.fill" : (kind == .broadcast ? "megaphone.fill" : "person.fill")
        let color:NSColor = kind == .group ? .systemGreen : .systemBlue
        chatBadge.title="  "+(chatNames[id]?.name ?? id)+"  ";chatBadge.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil);chatBadge.contentTintColor=color
        chatBadge.layer?.backgroundColor=color.withAlphaComponent(0.16).cgColor;chatBadge.isHidden=false
        chatBadge.setAccessibilityLabel((kind == .group ? L("Group","קבוצה") : L("Chat","שיחה"))+": "+(chatNames[id]?.name ?? id))
    }
    @objc func filterByFocusedChat() {
        guard !busy, let f=focusedFile, let id=ChatDirectory.identifier(of:f.url) else { return }
        if chatFilter.numberOfItems <= 4 { rebuildChatFilter() }
        guard let index=chatFilter.itemArray.firstIndex(where:{ ($0.representedObject as? String) == id }) else { return }
        chatFilter.selectItem(at:index);applyFilters();window.makeFirstResponder(table)
    }
    /// Home folder shown as ~ so long paths stay readable; the tooltip keeps the full path.
    func displayPath(_ url:URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }
    @objc func starClicked(_ sender:NSButton){ guard sender.tag<shown.count else { return };setStar(shown[sender.tag],!starred.contains(shown[sender.tag].id)) }
    @objc func reviewedClicked(_ sender:NSButton){ guard !busy,sender.tag<shown.count else { return };reviewed.toggle([shown[sender.tag]]);applyFilters() }
    /// K marks every selected file as reviewed and kept (all off again if every one already is). Files are never touched.
    func toggleReviewed(){ guard !busy,!mapMode,!selectedFiles.isEmpty else { return };reviewed.toggle(selectedFiles);applyFilters() }
    /// S toggles the star on every selected file (all on if any is unstarred).
    func toggleStar(){
        guard !busy,!mapMode,!selectedFiles.isEmpty else { return }
        let files=selectedFiles;let turnOn=files.contains{ !starred.contains($0.id) }
        for f in files { setStar(f,turnOn,refresh:false) };persistStars();applyFilters()
    }
    func setStar(_ f:FileRecord,_ on:Bool,refresh:Bool=true){
        if on { starred.insert(f.id) } else { starred.remove(f.id) }
        if refresh { persistStars();applyFilters() }
    }
    func persistStars(){ preferences.set(Array(starred).sorted(),forKey:"starredPaths") }
    @objc func selectAllCommand(){
        if let text = window.firstResponder as? NSTextView { text.selectAll(nil) } else { selectAllFiles() }
    }
    @objc func selectAllFiles(){
        guard !busy,!mapMode else{return};guards=[:];table.selectAll(nil);updateSelection()
    }
    @objc func deselect(){guard !busy,!mapMode else{return};guards=[:];table.deselectAll(nil);updateSelection()}
    /// Keep & next remembers the focused file as reviewed, then steps on; under "Not yet reviewed" the kept file leaves the list and the next one takes its row.
    @objc func nextFile(){
        guard !busy,!mapMode,!overviewMode,!shown.isEmpty else{return};let current=max(table.selectedRow,0)
        if let f=focusedFile { reviewed.mark([f]) };applyFilters()
        guard !shown.isEmpty else { return };let i=min(table.selectedRow < 0 ? current : current+1,shown.count-1)
        table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);table.scrollRowToVisible(i);window.makeFirstResponder(table)
    }
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
        // Starred files are never auto-selected as extra copies.
        let result=ExactDuplicates.selectExtras(exact,visible:Set(shown.map(\.id)).subtracting(starred));guards=result.keepers
        table.selectRowIndexes(IndexSet(shown.indices.filter{result.ids.contains(shown[$0].id)}),byExtendingSelection:false);updateSelection();window.makeFirstResponder(table)
    }
    func makeTrashAlert(_ chosen:[FileRecord])->NSAlert {
        let alert=NSAlert();alert.alertStyle = .warning
        alert.messageText=L("Move selected files to Trash?","להעביר את הבחירה לפח?")
        alert.informativeText="\(chosen.count) " + L("files","קבצים") + " · " + bytes(chosen.reduce(0){$0+$1.allocatedBytes}) + "\n" + L("Undo with ⌘Z.","אפשר לשחזר עם ⌘Z.")
        let starredCount=chosen.filter{ starred.contains($0.id) }.count
        if starredCount>0 { alert.alertStyle = .critical;alert.informativeText = "★ \(starredCount) " + L("starred files are included.","קבצים עם כוכב כלולים.") + "\n" + alert.informativeText }
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
        let keepers=guards;let row=table.selectedRow;setBusy(true,cancellable:false);primary.previewItem=nil;comparison.previewItem=nil;stopVideo()
        work.async {
            let result=self.history.move(chosen,root:root,keepers:keepers,backend:self.trashBackend)
            DispatchQueue.main.async {self.finishMove(result,nextRow:row)}
        }
    }
    /// After files move or come back, the last map no longer adds up; say so instead of showing stale totals as current.
    func markMapStale() { guard mapPanel.result != nil else { return };mapStale=true;mapPanel.setStale(true) }
    func finishMove(_ result:MoveResult,nextRow:Int) {
        if !result.tickets.isEmpty { markMapStale() }
        let moved=Set(result.tickets.map{$0.original.path});files.removeAll{moved.contains($0.id)}
        if !moved.isDisjoint(with:starred) { starred.subtract(moved);persistStars() }
        reviewed.forget(paths:moved) // a file in Trash is not "kept"; if it comes back it is reviewed again
        exact=[];similar=[];guards=[:];mode.selectItem(at:0);setBusy(false);modeChanged();updateSpaceLabel()
        if !shown.isEmpty {let next=min(max(nextRow,0),shown.count-1);table.selectRowIndexes(IndexSet(integer:next),byExtendingSelection:false);table.scrollRowToVisible(next)}
        status.stringValue="\(result.tickets.count) " + L("moved to Trash","הועברו לפח")
        if !result.failures.isEmpty {show(L("Some files need attention","יש קבצים שדורשים בדיקה"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n"))}
        window.makeFirstResponder(table)
    }
    @objc func undoTrash(){
        guard !busy,!demoMode,!overviewMode,activeHistory.canUndo else{return};let acting=activeHistory;setBusy(true,cancellable:false)
        work.async {
            let result=acting.undo(backend:self.trashBackend)
            DispatchQueue.main.async {self.finishRestore(result)}
        }
    }
    @objc func retryRestore(){
        guard !busy,!demoMode,!overviewMode,activeHistory.blockedCount>0 else{return};let acting=activeHistory;setBusy(true,cancellable:false)
        work.async {
            let result=acting.retryBlocked(backend:self.trashBackend)
            DispatchQueue.main.async {self.finishRestore(result)}
        }
    }
    func finishRestore(_ result:RestoreResult?) {
        setBusy(false);guard let result=result else{return}
        if !result.restored.isEmpty { markMapStale();if freeUpMode { freeUpPanel.reload(keepMeasurements:true);result.restored.forEach{ freeUpPanel.restored($0) } } }
        if mapMode || freeUpMode {
            var text="\(result.restored.count) " + L("restored","שוחזרו")
            if activeHistory.blockedCount>0 {text += " · \(activeHistory.blockedCount) " + L("waiting in Trash · Retry restore","ממתינים בפח · נסה לשחזר שוב")}
            status.stringValue=text;updateSpaceLabel();updateEnabled()
            if !result.failures.isEmpty { show(L("Some items could not be restored","חלק מהפריטים לא שוחזרו"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n")) }
            return
        }
        if let root=root {
            for url in result.restored {
                if let record=try? FileRecord(url:url),(try? FileSafety.validate(record,root:root)) != nil {
                    files.removeAll{$0.id == record.id};files.append(record)
                }
            }
        }
        exact=[];similar=[];mode.selectItem(at:0);modeChanged();updateSpaceLabel()
        var text="\(result.restored.count) " + L("restored","שוחזרו")
        if history.blockedCount>0 {text += " · \(history.blockedCount) " + L("waiting in Trash · Retry restore","ממתינים בפח · נסה לשחזר שוב")}
        status.stringValue=text
        if !result.failures.isEmpty {
            show(L("Some files could not be restored","חלק מהקבצים לא שוחזרו"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n")+"\n\n"+L("They stay in Trash. Resolve the conflict and use Retry restore, or restore them from Finder Trash. Earlier batches remain available with Undo.","הם נשארים בפח. פתור את ההתנגשות ולחץ ״נסה לשחזר שוב״, או שחזר מהפח ב־Finder. פעולות קודמות עדיין זמינות לשחזור."))
        }
        window.makeFirstResponder(table)
    }
    @objc func redoTrash(){
        guard !busy,!demoMode,!overviewMode,!mapMode,!freeUpMode,history.canRedo else{return};let row=table.selectedRow;setBusy(true,cancellable:false)
        work.async {
            let result=self.history.redo(backend:self.trashBackend)
            DispatchQueue.main.async {if let result=result {self.finishMove(result,nextRow:row)}else{self.setBusy(false)}}
        }
    }
    func runSmokeTests() {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("avakasha-smoke-" + UUID().uuidString)
        func cleanup() { try? FileManager.default.removeItem(at: temp); preferences.removePersistentDomain(forName:"Avakasha.SyntheticSmoke") }
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
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
            for (name, text) in [("coast-notes.txt", "Synthetic duplicate fixture"), ("coast-notes-copy.txt", "Synthetic duplicate fixture"), ("readme.txt", "Unrelated synthetic example")] {
                try Data(text.utf8).write(to: temp.appendingPathComponent(name))
            }
            precondition(locationButtons.count == 6 && locationButtons.map(\.tag) == Array(0..<6))
            precondition(Self.presetURL(0,home:temp)!.path.hasSuffix("Message/Media"))
            precondition(Self.presetURL(1,home:temp) == temp.appendingPathComponent("Downloads",isDirectory:true))
            precondition(Self.presetURL(6,home:temp) == nil)
            setBusy(true);precondition(locationButtons.allSatisfy{ !$0.isEnabled });setBusy(false)
            precondition(locationButtons.allSatisfy{ $0.isEnabled })
            precondition(overviewMode && !overviewPanel.isHidden && previewHostView.isHidden && !overviewPanel.volumes.isEmpty && overviewPanel.volumes[0].isStartup,"The app opens on the overview with real volume capacities")
            precondition(sidebarOverview.contentTintColor == .controlAccentColor && sidebarMap.contentTintColor != .controlAccentColor,"Overview is highlighted in the sidebar")
            setOverview(false) // the rest of the smoke drives the file review directly, as choosing a location would
            preferences.set(temp.path,forKey:"lastFolder");refreshEmptyState();precondition(!continueLink.isHidden && continueLink.stringValue.hasSuffix(displayPath(temp)),"Empty state offers to continue with the last folder")
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
            setStar(extra,true);selectExtras();precondition(selectedFiles.isEmpty,"A starred extra copy is never auto-selected");setStar(extra,false);selectExtras();precondition(selectedFiles.count == 1)
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
            let savedBoard=NSPasteboard.general.string(forType:.string);copyCommand()
            precondition(NSPasteboard.general.string(forType:.string) == selectedFiles[0].url.path && (NSPasteboard.general.readObjects(forClasses:[NSURL.self],options:nil)?.first as? URL)?.path == selectedFiles[0].url.path,"⌘C copies the path and the file")
            NSPasteboard.general.clearContents();if let s=savedBoard { NSPasteboard.general.setString(s,forType:.string) }
            precondition(tableView(table,pasteboardWriterForRow:99) == nil && chatFilter.isHidden)
            let chatFile=temp.appendingPathComponent("Media/12036301@g.us/clip.txt");try FileManager.default.createDirectory(at:chatFile.deletingLastPathComponent(),withIntermediateDirectories:true);try Data("g".utf8).write(to:chatFile)
            files.append(try FileRecord(url:chatFile));applyFilters();precondition(!chatFilter.isHidden,"Chat filter appears only when chat folders exist")
            chatFilter.selectItem(at:1);applyFilters();precondition(shown.count == 1 && shown[0].url.lastPathComponent == "clip.txt");chatFilter.selectItem(at:2);applyFilters();precondition(shown.isEmpty)
            precondition(chatFilter.itemArray.contains{ ($0.representedObject as? String) == "12036301@g.us" } && !chatNamesButton.isHidden,"Chats are listed by identifier; names are offered on request")
            precondition(!autoDownloadButton.isHidden);openWhatsAppAutoDownload();precondition(status.stringValue.contains("auto-download") || status.stringValue.contains("אוטומטית"))
            var db:OpaquePointer?;precondition(sqlite3_open(temp.appendingPathComponent(ChatDirectory.databaseName).path,&db) == SQLITE_OK)
            precondition(sqlite3_exec(db,"CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZPARTNERNAME TEXT); INSERT INTO ZWACHATSESSION (ZCONTACTJID, ZPARTNERNAME) VALUES ('12036301@g.us','Synthetic hiking group')",nil,nil,nil) == SQLITE_OK);sqlite3_close(db)
            applyFilters();precondition(!chatNamesButton.isHidden,"Offer names once a chat list is found");loadChatNames(confirmed:true);settle()
            precondition(chatNames["12036301@g.us"]?.name == "Synthetic hiking group" && chatNamesButton.isHidden && status.stringValue.hasPrefix("1 / 1"),status.stringValue)
            let named=chatFilter.itemArray.firstIndex{ $0.title.hasPrefix("Synthetic hiking group") }!;chatFilter.selectItem(at:named);applyFilters();precondition(shown.count == 1 && shown[0].url.lastPathComponent == "clip.txt","Filtering by a named chat")
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);precondition(!chatBadge.isHidden && chatBadge.title.contains("Synthetic hiking group"),"The chat badge names the highlighted file's chat")
            chatFilter.selectItem(at:0);applyFilters();table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url == chatFile}!),byExtendingSelection:false);filterByFocusedChat();precondition(shown.count == 1 && (chatFilter.selectedItem?.representedObject as? String) == "12036301@g.us","Clicking the badge filters to that chat")
            chatFilter.selectItem(at:0);applyFilters();table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url != chatFile}!),byExtendingSelection:false);precondition(chatBadge.isHidden,"No badge outside chat folders")
            try FileManager.default.removeItem(at:temp.appendingPathComponent(ChatDirectory.databaseName))
            chatFilter.selectItem(at:0);files.removeAll{$0.url == chatFile};try FileManager.default.removeItem(at:temp.appendingPathComponent("Media"));applyFilters();precondition(chatFilter.isHidden)
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            precondition(!kindBadge.isHidden && kindBadge.stringValue.contains(Self.kindTitle(.document).uppercased()) && videoHost.isHidden,"Text files show a document badge and no player")
            // Stars: S toggles, the filter shows or hides starred files, stars persist locally and never auto-select as extras.
            let starTarget=selectedFiles[0];let sKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"s",charactersIgnoringModifiers:"s",isARepeat:false,keyCode:1)!
            table.keyDown(with:sKey);precondition(starred.contains(starTarget.id) && preferences.stringArray(forKey:"starredPaths") == [starTarget.id],"S stars the selection and persists it")
            let total=shown.count;starFilter.selectItem(at:1);applyFilters();precondition(shown.map(\.id) == [starTarget.id],"Starred only")
            starFilter.selectItem(at:2);applyFilters();precondition(shown.count == total-1 && !shown.contains{$0.id == starTarget.id},"Hide starred")
            starFilter.selectItem(at:0);applyFilters();table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.id == starTarget.id}!),byExtendingSelection:false)
            let starAlert=makeTrashAlert([starTarget]);precondition(starAlert.alertStyle == .critical && starAlert.informativeText.hasPrefix("★ 1"),"Trashing a starred file warns")
            precondition((tableView(table,viewFor:table.tableColumns[0],row:table.selectedRow) as? NSButton)?.contentTintColor == .systemYellow)
            table.keyDown(with:sKey);precondition(starred.isEmpty && (preferences.stringArray(forKey:"starredPaths") ?? []).isEmpty,"S again removes the star")
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
            precondition(!overviewMode && overviewPanel.isHidden && sidebarMap.contentTintColor == .controlAccentColor && locationButtons.allSatisfy{ $0.contentTintColor != .controlAccentColor },"In the map only the map entry is highlighted, never a location")
            showOverview();precondition(overviewMode && mapPanel.isHidden && sidebarOverview.contentTintColor == .controlAccentColor);showStorageMap();precondition(mapMode && !overviewMode && mapPanel.current != nil,"Storage map from the overview returns to the last map without re-measuring")
            precondition(mapPanel.rows.map(\.title) == ["Big","Small",L("Files in this folder","קבצים בתיקייה עצמה")],"Map rows sort by size: \(mapPanel.rows.map(\.title))")
            precondition(mapPanel.table.selectedRow == 0 && mapPanel.reviewTarget?.path == bigPath && mapPanel.openButton.isEnabled)
            precondition(status.stringValue.contains("4 "+L("files","קבצים")) && status.stringValue.contains("2 "+L("folders","תיקיות")),status.stringValue)
            mapPanel.openSelected();precondition(mapPanel.current?.name == "Big" && mapPanel.rows.count == 1 && !mapPanel.rows[0].isFolder && !mapPanel.openButton.isEnabled)
            precondition(mapPanel.reviewTarget?.path == bigPath,"The loose-files row reviews the current folder")
            mapPanel.goUp();precondition(mapPanel.current?.name == "map" && mapPanel.selectedRow?.title == "Big")
            let mapDelete=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51)!
            mapPanel.table.selectRowIndexes(IndexSet(integer:mapPanel.rows.firstIndex{ !$0.isFolder }!),byExtendingSelection:false)
            mapPanel.table.keyDown(with:mapDelete);precondition(!busy && FileManager.default.fileExists(atPath:mapFolder.appendingPathComponent("Big/large.bin").path),"Delete on the loose-files row moves nothing")
            mapPanel.table.selectRowIndexes(IndexSet(integer:mapPanel.rows.firstIndex{ $0.title == "Big" }!),byExtendingSelection:false)
            selectAllFiles();precondition(table.selectedRowIndexes.isEmpty,"Select all must not reach the hidden file table in map mode")
            mapPanel.reviewSelected();settle()
            precondition(!mapMode && root?.path == bigPath && files.count == 1 && files[0].name == "large.bin" && !scroll.isHidden && mapPanel.isHidden,"Review files here hands the folder to file review")
            showStorageMap();precondition(mapMode && mapPanel.current?.name == "Big" && mapPanel.result != nil,"Return to the map without re-mapping")
            showStorageMap();precondition(!mapMode && root?.path == bigPath,"Back to files")
            // Largest files: the map hands its biggest files to review; Refresh re-measures the map and rebuilds the same view.
            let mapRootPath=mapFolder.resolvingSymlinksInPath().path
            showStorageMap();precondition(mapMode && mapPanel.largestButton.isEnabled && mapPanel.current?.name == "Big");mapPanel.goUp();precondition(mapPanel.current?.name == "map")
            precondition(mapPanel.largestFiles(in:mapPanel.result!.root,directOnly:false).map{$0.url.lastPathComponent}.first == "large.bin" && mapPanel.largestFiles(in:mapPanel.result!.root,directOnly:true).map{$0.url.lastPathComponent} == ["loose.txt"],"Details list the largest files of the folder")
            reviewLargestFiles()
            precondition(!mapMode && reviewSource == .largestFiles && root?.path == mapRootPath && !scroll.isHidden && mapPanel.isHidden,"Largest files opens file review on the map root")
            precondition(files.count == 4 && shown.first?.name == "large.bin" && zip(shown,shown.dropFirst()).allSatisfy{$0.allocatedBytes >= $1.allocatedBytes},"Largest first: \(shown.map(\.name))")
            precondition(folderLabel.stringValue == mapRootPath+" · "+L("largest files","הקבצים הגדולים") && sortPicker.indexOfSelectedItem == ReviewSort.largest.rawValue && mode.indexOfSelectedItem == 0 && table.selectedRow == 0,folderLabel.stringValue)
            precondition(status.stringValue.hasPrefix("4 ") && !spaceLabel.isHidden && !isCurrentRoot(mapFolder),status.stringValue)
            rescanFolder();precondition(busy && pendingLargestReview,"Refresh in the largest-files view re-measures the map");settle()
            precondition(!mapMode && reviewSource == .largestFiles && !pendingLargestReview && files.count == 4 && shown.first?.name == "large.bin" && folderLabel.stringValue.hasSuffix(L("largest files","הקבצים הגדולים")),"Refresh rebuilds the largest-files view")
            // Return on the loose-files row reviews the folder it belongs to, like "Review files here".
            showStorageMap();precondition(mapMode && mapPanel.current?.name == "map")
            mapPanel.table.selectRowIndexes(IndexSet(integer:mapPanel.rows.firstIndex{ !$0.isFolder }!),byExtendingSelection:false)
            let mapReturn=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
            mapPanel.table.keyDown(with:mapReturn);settle()
            precondition(!mapMode && reviewSource == .scan && root?.path == mapRootPath && files.count == 4,"Return on the loose-files row reviews the current folder and a scan resets the source")
            // Stop: a big synthetic tree is scanned, Esc stops it, partial results stay and Refresh comes back.
            let bigTree=temp.appendingPathComponent("many",isDirectory:true)
            for i in 0..<40 { let d=bigTree.appendingPathComponent("d\(i)");try FileManager.default.createDirectory(at:d,withIntermediateDirectories:true);for j in 0..<60 { try Data("x".utf8).write(to:d.appendingPathComponent("f\(j).txt")) } }
            startScan(bigTree);precondition(busy && cancellable && rescanButton.title == L("Stop","עצור") && rescanButton.action == #selector(cancelWork))
            precondition(escapeMonitor != nil,"Esc is wired to Stop");cancelWork();precondition(token.isCancelled && !cancelButton.isEnabled);settle()
            precondition(!busy && rescanButton.title == L("Refresh","רענן") && rescanButton.action == #selector(rescanFolder) && files.count <= 2400,"Stopping keeps partial results and restores Refresh: \(status.stringValue)")
            try FileManager.default.removeItem(at:bigTree)
            startScan(reviewRoot);settle();precondition(!mapMode && root?.path == reviewRoot.resolvingSymlinksInPath().path)
            // Installers & archives: only disk images, packages and archives older than the cutoff; the badge names the family.
            let installerURLs=["old.dmg","old.zip","new.dmg","photo.jpg"].map{ temp.appendingPathComponent($0) }
            for u in installerURLs { try Data("synthetic".utf8).write(to:u) }
            for u in installerURLs.prefix(2) { try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:946684800)],ofItemAtPath:u.path) }
            let installerFixtures=try installerURLs.map{ try FileRecord(url:$0) };files += installerFixtures
            mode.selectItem(at:4);agePicker.selectItem(at:1);modeChanged()
            precondition(Set(shown.map(\.name)) == ["old.dmg","old.zip"] && !agePicker.isHidden && !ageHint.isHidden && ageHint.stringValue == Self.installerHintText,"Installers view: \(shown.map(\.name))")
            table.selectRowIndexes(IndexSet(integer:shown.firstIndex{ $0.name == "old.dmg" }!),byExtendingSelection:false)
            precondition(kindBadge.stringValue.contains(Self.installerTitle(.diskImage).uppercased()) && kindBadge.textColor == .systemIndigo,"Disk image badge: \(kindBadge.stringValue)")
            setMapMode(true);showInstallers();precondition(!mapMode && mode.indexOfSelectedItem == 4 && shown.count == 2,"Installers from the sidebar leaves map mode")
            mode.selectItem(at:0);modeChanged();precondition(ageHint.isHidden && ageHint.stringValue == Self.ageHintText)
            files.removeAll{ f in installerFixtures.contains{ $0.id == f.id } };for u in installerURLs { try FileManager.default.removeItem(at:u) };applyFilters()
            // Reviewed and kept: K toggles, the filter partitions the list, Keep & next remembers, a star outranks the checkmark.
            starFilter.selectItem(at:0);sortPicker.selectItem(at:ReviewSort.name.rawValue);changeSort();reviewed.unmark(files);applyFilters()
            let kKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"k",charactersIgnoringModifiers:"k",isARepeat:false,keyCode:40)!
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);let kept=shown[0];let everyone=shown.count
            table.keyDown(with:kKey);precondition(reviewed.isReviewed(kept) && (preferences.dictionary(forKey:"reviewedFiles") as? [String:String])?[kept.id] != nil,"K marks the selection as reviewed and persists it")
            precondition(selectionLabel.stringValue.hasSuffix(L("reviewed","נסקר")),"Selection label: \(selectionLabel.stringValue)")
            precondition((tableView(table,viewFor:table.tableColumns[0],row:0) as? NSButton)?.contentTintColor == .systemGreen,"Reviewed files show a green checkmark")
            setStar(kept,true);precondition((tableView(table,viewFor:table.tableColumns[0],row:0) as? NSButton)?.contentTintColor == .systemYellow,"A star outranks the reviewed mark");setStar(kept,false)
            starFilter.selectItem(at:4);applyFilters();precondition(shown.map(\.id) == [kept.id],"Reviewed only")
            starFilter.selectItem(at:3);applyFilters();precondition(shown.count == everyone-1 && !shown.contains{ $0.id == kept.id },"Not yet reviewed")
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);let left=shown[0];let follower=shown[1];nextFile()
            precondition(reviewed.isReviewed(left) && shown.count == everyone-2 && table.selectedRow == 0 && shown[0].id == follower.id,"Keep & next marks the file it left and steps to the next unreviewed one")
            starFilter.selectItem(at:0);applyFilters();table.selectRowIndexes(IndexSet(integer:shown.firstIndex{ $0.id == kept.id }!),byExtendingSelection:false)
            table.keyDown(with:kKey);precondition(!reviewed.isReviewed(kept),"K again clears the mark")
            let checkCell=tableView(table,viewFor:table.tableColumns[0],row:shown.firstIndex{ $0.id == left.id }!) as! NSButton
            precondition(checkCell.action == #selector(reviewedClicked(_:)));reviewedClicked(checkCell);precondition(!reviewed.isReviewed(left),"Clicking the checkmark clears the mark")
            precondition(!history.canUndo && !history.canRedo)
            let alert=makeTrashAlert([files[0]]);precondition(alert.showsSuppressionButton && alert.suppressionButton?.state == .off)
            preferences.set(true,forKey:"skipTrashConfirmation")
            sortPicker.selectItem(at:ReviewSort.name.rawValue);changeSort()
            let target=temp.appendingPathComponent("coast-notes.txt").resolvingSymlinksInPath()
            table.selectRowIndexes(IndexSet(integer:shown.firstIndex{$0.url.path == target.path}!),byExtendingSelection:false)
            precondition(selectedFiles[0].url.path == target.path)
            func key(_ code:UInt16,_ flags:NSEvent.ModifierFlags=[],_ repeated:Bool=false) {
                let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeated,keyCode:code)!
                table.keyDown(with:event);settle()
            }
            let targetRecord=selectedFiles[0];reviewed.mark([targetRecord])
            key(51);precondition(!FileManager.default.fileExists(atPath:target.path) && history.canUndo)
            precondition(!reviewed.isReviewed(targetRecord) && (preferences.dictionary(forKey:"reviewedFiles") as? [String:String])?[targetRecord.id] == nil,"Trash forgets the reviewed mark")
            precondition(!spaceLabel.isHidden && totalMovedBytes == targetRecord.allocatedBytes && spaceLabel.stringValue.contains(bytes(targetRecord.allocatedBytes)),"Space summary after Trash: \(spaceLabel.stringValue)")
            precondition(mapStale && !mapPanel.rescanButton.isHidden,"Moving files marks the last map as out of date")
            let count=files.count;key(51,[],true);precondition(files.count == count,"Held Delete must not trash the next file")
            key(6,[.command]);precondition(FileManager.default.fileExists(atPath:target.path) && history.canRedo)
            precondition(spaceLabel.stringValue.contains(L("Nothing moved to Trash yet","עדיין לא הועבר דבר לפח")),"Undo drops the session total: \(spaceLabel.stringValue)")
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
            // Whole-folder move from the map: measured again, moved as one item, undoable from the map, never for bundles or hidden folders.
            startMap(mapFolder);settle();precondition(mapMode)
            mapPanel.table.selectRowIndexes(IndexSet(integer:mapPanel.rows.firstIndex{$0.title == "Small"}!),byExtendingSelection:false)
            precondition(mapPanel.trashableFolder?.name == "Small" && mapPanel.trashButton.isEnabled)
            let smallURL=mapFolder.appendingPathComponent("Small");let mapBytesBefore=mapPanel.result!.root.bytes
            let folderAlert=makeFolderTrashAlert(title:"Small",fresh:try StorageMapper.map(root:smallURL,token:CancellationToken(),limit:0),folder:smallURL,explanation:nil)
            precondition(folderAlert.alertStyle == .critical && folderAlert.buttons.count == 2 && folderAlert.buttons[1].keyEquivalent == "\r" && folderAlert.buttons[0].keyEquivalent.isEmpty,"Folder confirmation is critical and Return cancels")
            preferences.set(true,forKey:"skipTrashConfirmation");folderConfirmationOverride=false
            let mapDeleteKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51)!
            mapPanel.table.keyDown(with:mapDeleteKey);settle();precondition(FileManager.default.fileExists(atPath:smallURL.path) && status.stringValue == L("Nothing moved","שום דבר לא הועבר"),"A declined confirmation moves nothing, even with file confirmations suppressed")
            folderConfirmationOverride=nil
            trashFolderFromMap(mapPanel.trashableFolder!,confirmed:true);settle();settle()
            precondition(!FileManager.default.fileExists(atPath:smallURL.path) && !mapPanel.rows.contains{$0.title == "Small"} && mapPanel.result!.root.bytes < mapBytesBefore && mapStale,"Folder moved and detached from the map")
            precondition(activeHistory.canUndo && !activeHistory.canRedo && undoButton.isEnabled,"Folder moves are undoable from the map")
            undoTrash();settle();precondition(FileManager.default.fileExists(atPath:smallURL.appendingPathComponent("tiny.txt").path) && !activeHistory.canRedo,"Undo brings the folder back; no redo for folders")
            // Blocked folder restore: something new at the original path waits under Retry; retry succeeds once it is gone.
            startMap(mapFolder);settle();precondition(mapPanel.rows.contains{$0.title == "Small"},"Rescan lists the restored folder again")
            trashFolderFromMap(mapPanel.rows.first{$0.title == "Small"}!.node!,confirmed:true);settle();settle();precondition(!FileManager.default.fileExists(atPath:smallURL.path))
            try FileManager.default.createDirectory(at:smallURL,withIntermediateDirectories:true);undoTrash();settle()
            precondition(activeHistory.blockedCount == 1 && !retryButton.isHidden,"A folder whose path was taken waits for retry")
            try FileManager.default.removeItem(at:smallURL);retryRestore();settle();precondition(activeHistory.blockedCount == 0 && FileManager.default.fileExists(atPath:smallURL.appendingPathComponent("tiny.txt").path))
            try FileManager.default.createDirectory(at:mapFolder.appendingPathComponent(".hiddencache/inner"),withIntermediateDirectories:true);try Data("h".utf8).write(to:mapFolder.appendingPathComponent(".hiddencache/inner/x"))
            try FileManager.default.createDirectory(at:mapFolder.appendingPathComponent("Tool.app/Contents"),withIntermediateDirectories:true);try Data("t".utf8).write(to:mapFolder.appendingPathComponent("Tool.app/Contents/x"))
            let locked=mapFolder.appendingPathComponent("Locked/inner");try FileManager.default.createDirectory(at:locked,withIntermediateDirectories:true);try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:locked.path)
            startMap(mapFolder);settle()
            for name in [".hiddencache","Tool.app","Locked"] { mapPanel.table.selectRowIndexes(IndexSet(integer:mapPanel.rows.firstIndex{$0.title == name}!),byExtendingSelection:false);precondition(mapPanel.trashableFolder == nil && !mapPanel.trashButton.isEnabled,"\(name) cannot be moved whole") }
            try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:locked.path)
            mapPanel.table.selectRowIndexes(IndexSet(integer:mapPanel.rows.firstIndex{$0.title == ".hiddencache"}!),byExtendingSelection:false);mapPanel.openSelected()
            precondition(mapPanel.current?.name == ".hiddencache" && mapPanel.trashableFolder == nil,"Folders under a hidden folder are not offered either")
            trashFolder(mapFolder.appendingPathComponent(".hiddencache/inner"),root:mapRoot!,title:"inner",explanation:nil,confirmed:true){ precondition(false,"must not move") }
            precondition(FileManager.default.fileExists(atPath:mapFolder.appendingPathComponent(".hiddencache/inner/x").path) && status.stringValue == L("Nothing moved","שום דבר לא הועבר"))
            try FileManager.default.removeItem(at:mapFolder.appendingPathComponent("Tool.app"));try FileManager.default.removeItem(at:mapFolder.appendingPathComponent("Locked"))
            // Free up space: a synthetic home with known locations, measured on request, moved with the same guarded flow, restored with Undo.
            let fakeHome=temp.appendingPathComponent("home",isDirectory:true)
            try FileManager.default.createDirectory(at:fakeHome.appendingPathComponent("Library/Developer/Xcode/DerivedData/Proj"),withIntermediateDirectories:true)
            try Data(repeating:0x44,count:30_000).write(to:fakeHome.appendingPathComponent("Library/Developer/Xcode/DerivedData/Proj/index.bin"))
            try FileManager.default.createDirectory(at:fakeHome.appendingPathComponent("Library/Caches/com.example.app"),withIntermediateDirectories:true)
            try FileManager.default.createDirectory(at:fakeHome.appendingPathComponent("Library/Mail"),withIntermediateDirectories:true)
            home=fakeHome;showFreeUp();precondition(freeUpMode && sidebarFreeUp.contentTintColor == .controlAccentColor && freeUpPanel.home.path == fakeHome.path)
            precondition(Set(freeUpPanel.rows.map{$0.location.id}) == ["xcode.derivedData","mail","cache.com.example.app","system.caches"],"\(freeUpPanel.rows.map{$0.location.id})")
            freeUpPanel.measureAll();settle()
            let derived=freeUpPanel.rows.first{$0.location.id == "xcode.derivedData"}!;let mailRow=freeUpPanel.rows.first{$0.location.id == "mail"}!
            precondition(derived.measurement?.error == nil && (derived.measurement?.bytes ?? 0) >= 30_000 && mailRow.measurement?.error == nil && mailRow.measurement?.files == 0)
            precondition(!derived.location.url(home:freeUpPanel.home).path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path+"/Library"),"The smoke must never measure the real home folder")
            freeUpPanel.table.selectRowIndexes(IndexSet(integer:freeUpPanel.rows.firstIndex{$0.location.id == "mail"}!),byExtendingSelection:false);precondition(!freeUpPanel.trashButton.isEnabled,"Mail is never offered for Trash")
            freeUpPanel.table.selectRowIndexes(IndexSet(integer:freeUpPanel.rows.firstIndex{$0.location.id == "xcode.derivedData"}!),byExtendingSelection:false);precondition(freeUpPanel.trashButton.isEnabled)
            let derivedURL=fakeHome.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let homeRoot=try FileSafety.root(fakeHome)
            trashLocation(mailRow.location,measured:mailRow.measurement!,confirmed:true);precondition(FileManager.default.fileExists(atPath:fakeHome.appendingPathComponent("Library/Mail").path),"Mail is never moved by the app")
            trashLocation(derived.location,measured:derived.measurement!,confirmed:true);settle();settle()
            precondition(!FileManager.default.fileExists(atPath:derivedURL.path) && freeUpPanel.rows.first{$0.location.id == "xcode.derivedData"}!.moved && historyFor(homeRoot).sessionMovedBytes >= 30_000 && activeHistory === historyFor(homeRoot) && undoButton.isEnabled && !redoButton.isEnabled,"Known location moved as one folder; Undo follows the free-up root")
            undoTrash();settle()
            precondition(FileManager.default.fileExists(atPath:derivedURL.appendingPathComponent("Proj/index.bin").path) && !freeUpPanel.rows.first{$0.location.id == "xcode.derivedData"}!.moved && freeUpPanel.rows.first{$0.location.id == "xcode.derivedData"}!.measurement == nil,"Undo brings the folder back and asks to measure again")
            setFreeUp(false);home=FileManager.default.homeDirectoryForCurrentUser;freeUpPanel.home=home;try FileManager.default.removeItem(at:fakeHome)
            let savedRoot=root!;activateRoot(temp.appendingPathComponent("other"));precondition(!history.canUndo && !history.canRedo);activateRoot(savedRoot);precondition(history.canRedo)
            toggleTrashConfirmation(confirmationMenuItem!);precondition(!preferences.bool(forKey:"skipTrashConfirmation"))
            let languageItems=languageMenuItem!.submenu!.items;precondition(languageItems.map{$0.representedObject as? String} == ["en","he"] && languageItems[0].state == .on)
            chooseLanguage(languageItems[1]);precondition(preferences.string(forKey:"language") == "he" && preferences.stringArray(forKey:"AppleLanguages") == ["he"] && languageItems[1].state == .on && languageItems[0].state == .off)
            precondition(AppLanguage.current == "en" && L("a","ב") == "a","A language choice applies on the next launch, not mid-session")
            precondition(preferences.bool(forKey:"AppleTextDirection"),"Hebrew must switch the layout direction")
            chooseLanguage(languageItems[0]);precondition(preferences.stringArray(forKey:"AppleLanguages") == ["en"] && !preferences.bool(forKey:"AppleTextDirection"))
            precondition(isCurrentRoot(root!) && !isCurrentRoot(temp.appendingPathComponent("map")),"Clicking the loaded location again must not rescan")
            print("UI smoke: storage map, largest files, installers, reviewed marks, session space summary, selection, old-file sorting, preview, confirmation preference, Delete, Undo, Redo, blocked-restore retry and held-key protection passed. No real files changed; no windows shown.")
            cleanup();fflush(stdout);exit(0)
        } catch { fputs("UI smoke failed: \(error)\n",stderr);cleanup();exit(1) }
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { applicationShouldTerminate(NSApplication.shared) == .terminateNow }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{
        if busy && !(token.isCancelled && cancellable){show(L("Operation in progress","פעולה עדיין מתבצעת"),L("Cancel the scan and wait, or let the Trash operation finish before quitting.","בטל את הסריקה והמתן, או אפשר להעברה לפח להסתיים לפני הסגירה."));return .terminateCancel}
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
