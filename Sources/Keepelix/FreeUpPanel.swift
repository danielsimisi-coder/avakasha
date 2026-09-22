import Cocoa
import KeepelixCore

/// Human wording for a catalogue entry: what it is, what happens next time, and how to clean it when the app cannot.
struct LocationText {
    let title: String, what: String, next: String, howTo: String?
}

enum LocationTexts {
    static func text(for location: KnownLocation) -> LocationText {
        if location.id.hasPrefix("cache.") {
            let app = String(location.id.dropFirst(6))
            return LocationText(title: L("App cache: ", "מטמון אפליקציה: ") + app,
                                what: L("Temporary files this app keeps to open faster.", "קבצים זמניים שהאפליקציה שומרת כדי להיפתח מהר יותר."),
                                next: L("The app rebuilds what it needs the next time it runs.", "האפליקציה תבנה מחדש את מה שהיא צריכה בהפעלה הבאה."), howTo: nil)
        }
        switch location.id {
        case "xcode.simulators": return LocationText(title: L("Xcode simulators", "סימולטורים של Xcode"), what: L("Simulated iPhones, iPads and watches with the apps and data installed on them.", "מכשירי iPhone, iPad ושעונים מדומים, עם האפליקציות והנתונים שמותקנים בהם."), next: L("Xcode creates fresh simulators in one click; test data inside them is gone.", "Xcode יוצר סימולטורים חדשים בלחיצה; נתוני בדיקה שבתוכם נמחקים."), howTo: L("Deleting simulators must go through Xcode's tool so it stays consistent. Copy the command and run it in Terminal.", "מחיקת סימולטורים חייבת לעבור דרך הכלי של Xcode כדי להישאר עקבית. העתק את הפקודה והרץ ב־Terminal."))
        case "xcode.simulatorCaches": return LocationText(title: L("Simulator caches", "מטמוני סימולטור"), what: L("Runtime caches for the simulators.", "מטמוני ריצה של הסימולטורים."), next: L("Recreated automatically.", "נוצרים מחדש אוטומטית."), howTo: nil)
        case "xcode.deviceSupport", "xcode.watchDeviceSupport": return LocationText(title: L("Xcode device support files", "קבצי תמיכה במכשירים של Xcode"), what: L("Debug symbols for each iOS version of the devices you connected.", "סמלי דיבאג לכל גרסת iOS של המכשירים שחיברת."), next: L("Xcode downloads them again the next time you connect the device; a few minutes.", "Xcode יוריד אותם שוב בחיבור הבא של המכשיר; כמה דקות."), howTo: nil)
        case "xcode.derivedData": return LocationText(title: L("Xcode DerivedData", "DerivedData של Xcode"), what: L("Build products and indexes for every project you opened.", "תוצרי בנייה ואינדקסים לכל פרויקט שפתחת."), next: L("The next build recreates them; the first build is slower.", "הבנייה הבאה יוצרת אותם מחדש; הבנייה הראשונה איטית יותר."), howTo: nil)
        case "xcode.archives": return LocationText(title: L("Xcode archives", "ארכיוני Xcode"), what: L("Builds you archived for the App Store or for distribution, with their debug symbols.", "גרסאות שארכבת ל־App Store או להפצה, עם סמלי הדיבאג שלהן."), next: L("Old archives cannot be recreated. Keep the ones for versions still in use.", "ארכיונים ישנים לא ניתן לשחזר. שמור את אלה של גרסאות שעדיין בשימוש."), howTo: L("Xcode › Window › Organizer › Archives lets you delete old ones.", "Xcode › Window › Organizer › Archives מאפשר למחוק ישנים."))
        case "xcode.caches": return LocationText(title: L("Xcode cache", "מטמון Xcode"), what: L("Temporary Xcode data.", "נתונים זמניים של Xcode."), next: L("Recreated automatically.", "נוצר מחדש אוטומטית."), howTo: nil)
        case "orbstack", "orbstack.data": return LocationText(title: "OrbStack", what: L("Container images, volumes and Linux machines.", "תמונות קונטיינרים, נפחים ומכונות Linux."), next: L("Images download again; containers and their data do not come back.", "תמונות יורדות שוב; קונטיינרים והנתונים שלהם לא חוזרים."), howTo: L("Delete unused machines and images from OrbStack itself so it stays consistent.", "מחק מכונות ותמונות שאינן בשימוש מתוך OrbStack עצמו כדי שיישאר עקבי."))
        case "docker.vms": return LocationText(title: "Docker Desktop", what: L("The virtual disk that holds all images, containers and volumes.", "הדיסק הווירטואלי שמכיל את כל התמונות, הקונטיינרים והנפחים."), next: L("Images download again; container data does not come back.", "תמונות יורדות שוב; נתוני קונטיינרים לא חוזרים."), howTo: L("Docker Desktop › Settings › Resources › Advanced, or docker system prune.", "Docker Desktop › Settings › Resources › Advanced, או docker system prune."))
        case "npm.cache": return LocationText(title: L("npm cache", "מטמון npm"), what: L("Downloaded packages kept for faster installs.", "חבילות שהורדו ונשמרות להתקנות מהירות יותר."), next: L("Downloaded again on the next install.", "יורדות שוב בהתקנה הבאה."), howTo: L("Use npm's own command so its index stays consistent.", "השתמש בפקודה של npm עצמו כדי שהאינדקס יישאר עקבי."))
        case "pnpm.store": return LocationText(title: L("pnpm store", "מאגר pnpm"), what: L("Shared packages for every pnpm project.", "חבילות משותפות לכל פרויקטי pnpm."), next: L("prune removes only packages no project uses.", "prune מסיר רק חבילות שאף פרויקט לא משתמש בהן."), howTo: nil)
        case "yarn.cache": return LocationText(title: L("Yarn cache", "מטמון Yarn"), what: L("Downloaded packages.", "חבילות שהורדו."), next: L("Downloaded again when needed.", "יורדות שוב בעת הצורך."), howTo: nil)
        case "homebrew.cache": return LocationText(title: L("Homebrew downloads", "הורדות Homebrew"), what: L("Installer bottles kept after installation.", "חבילות התקנה שנשמרו אחרי ההתקנה."), next: L("Downloaded again for upgrades.", "יורדות שוב בשדרוגים."), howTo: nil)
        case "gradle.caches": return LocationText(title: L("Gradle caches", "מטמוני Gradle"), what: L("Dependencies and build caches for Android and Java projects.", "תלויות ומטמוני בנייה לפרויקטי Android ו־Java."), next: L("Downloaded again on the next build.", "יורדים שוב בבנייה הבאה."), howTo: nil)
        case "maven.repository": return LocationText(title: L("Maven repository", "מאגר Maven"), what: L("Downloaded Java dependencies.", "תלויות Java שהורדו."), next: L("Downloaded again on the next build.", "יורדות שוב בבנייה הבאה."), howTo: nil)
        case "cocoapods.cache": return LocationText(title: L("CocoaPods cache", "מטמון CocoaPods"), what: L("Downloaded pods.", "Pods שהורדו."), next: L("Downloaded again on pod install.", "יורדים שוב ב־pod install."), howTo: nil)
        case "pip.cache": return LocationText(title: L("pip cache", "מטמון pip"), what: L("Downloaded Python packages.", "חבילות Python שהורדו."), next: L("Downloaded again when installed.", "יורדות שוב בהתקנה."), howTo: nil)
        case "cargo.registry": return LocationText(title: L("Cargo registry", "מאגר Cargo"), what: L("Downloaded Rust crates.", "Crates של Rust שהורדו."), next: L("Downloaded again on the next build.", "יורדים שוב בבנייה הבאה."), howTo: nil)
        case "go.modcache": return LocationText(title: L("Go module cache", "מטמון מודולים של Go"), what: L("Downloaded Go modules.", "מודולי Go שהורדו."), next: L("Downloaded again on the next build.", "יורדים שוב בבנייה הבאה."), howTo: nil)
        case "codex.cache": return LocationText(title: "Codex", what: L("Sessions and local data of the Codex CLI.", "סשנים ונתונים מקומיים של Codex CLI."), next: L("Session history would be lost.", "היסטוריית הסשנים תאבד."), howTo: L("Review inside the folder; keep what you still need.", "סקור בתוך התיקייה; שמור מה שעדיין נחוץ."))
        case "claude.vmBundles": return LocationText(title: L("Claude Desktop sandbox images", "תמונות הסנדבוקס של Claude Desktop"), what: L("Virtual machine bundles for the local environment.", "חבילות מכונה וירטואלית לסביבה המקומית."), next: L("The app downloads them again; quit Claude first.", "האפליקציה מורידה אותן שוב; סגור את Claude קודם."), howTo: nil)
        case "ai.huggingface": return LocationText(title: L("Hugging Face models", "מודלים של Hugging Face"), what: L("Downloaded AI models and datasets.", "מודלים ומערכי נתונים שהורדו."), next: L("Downloaded again the next time a script uses them.", "יורדים שוב בפעם הבאה שסקריפט משתמש בהם."), howTo: nil)
        case "ai.torch": return LocationText(title: L("PyTorch cache", "מטמון PyTorch"), what: L("Downloaded model weights.", "משקולות מודלים שהורדו."), next: L("Downloaded again when used.", "יורדות שוב בשימוש."), howTo: nil)
        case "ai.whisper": return LocationText(title: L("Whisper models", "מודלים של Whisper"), what: L("Downloaded speech models.", "מודלי דיבור שהורדו."), next: L("Downloaded again when used.", "יורדים שוב בשימוש."), howTo: nil)
        case "ai.ollama": return LocationText(title: L("Ollama models", "מודלים של Ollama"), what: L("Local language models.", "מודלי שפה מקומיים."), next: L("Downloaded again with ollama pull.", "יורדים שוב עם ollama pull."), howTo: nil)
        case "adobe.common": return LocationText(title: L("Adobe media cache", "מטמון מדיה של Adobe"), what: L("Premiere and After Effects render and peak files.", "קבצי רינדור ו־peak של Premiere ו־After Effects."), next: L("Rebuilt when a project opens.", "נבנים מחדש כשפרויקט נפתח."), howTo: L("Premiere › Settings › Media Cache › Delete Unused.", "Premiere › Settings › Media Cache › Delete Unused."))
        case "adobe.installers": return LocationText(title: L("Adobe installers", "קבצי התקנה של Adobe"), what: L("Old installer downloads.", "הורדות התקנה ישנות."), next: L("Creative Cloud downloads what it needs.", "Creative Cloud מוריד מה שצריך."), howTo: nil)
        case "adobe.uxp": return LocationText(title: L("Adobe plug-ins (UXP)", "תוספי Adobe (UXP)"), what: L("Installed plug-ins and their data.", "תוספים מותקנים והנתונים שלהם."), next: L("Plug-ins would need reinstalling.", "יהיה צורך להתקין תוספים מחדש."), howTo: L("Manage plug-ins from the Creative Cloud app.", "נהל תוספים מאפליקציית Creative Cloud."))
        case "wondershare.installer": return LocationText(title: L("Wondershare installer leftovers", "שאריות התקנה של Wondershare"), what: L("Files left by an installer.", "קבצים שנשארו ממתקין."), next: L("Nothing; the installer downloads again if ever needed.", "כלום; המתקין יורד שוב אם יידרש."), howTo: nil)
        case "quicklook.thumbnails": return LocationText(title: L("Quick Look thumbnails", "תמונות ממוזערות של Quick Look"), what: L("Cached previews.", "תצוגות מקדימות שנשמרו."), next: L("Generated again as you browse.", "נוצרות שוב תוך כדי גלישה."), howTo: nil)
        case "system.caches": return LocationText(title: L("All app caches", "כל מטמוני האפליקציות"), what: L("Every app's cache folder. Each one is listed separately below.", "תיקיית המטמון של כל אפליקציה. כל אחת מופיעה בנפרד למטה."), next: L("Apps rebuild their caches.", "אפליקציות בונות מחדש את המטמונים."), howTo: L("Move individual app caches below rather than the whole folder.", "העבר מטמוני אפליקציות בודדים למטה ולא את התיקייה כולה."))
        case "system.logs": return LocationText(title: L("Logs", "יומנים"), what: L("Diagnostic logs from apps and the system.", "יומני אבחון של אפליקציות והמערכת."), next: L("New logs are written as needed.", "יומנים חדשים נכתבים לפי הצורך."), howTo: nil)
        case "system.tempFolders": return LocationText(title: L("System temporary folders", "תיקיות זמניות של המערכת"), what: L("Caches and temporary files macOS manages.", "מטמונים וקבצים זמניים ש־macOS מנהל."), next: L("Cleared on restart.", "מתנקה באתחול."), howTo: L("Restart the Mac.", "הפעל מחדש את המק."))
        case "chrome", "chrome.cache": return LocationText(title: L("Chrome", "Chrome"), what: L("Profiles, extensions and cache.", "פרופילים, תוספים ומטמון."), next: L("Profiles hold logins; only the cache is safe to clear.", "הפרופילים מכילים כניסות; רק המטמון בטוח לניקוי."), howTo: L("Chrome › Clear browsing data › Cached images and files.", "Chrome › Clear browsing data › Cached images and files."))
        case "safari.cache": return LocationText(title: L("Safari cache", "מטמון Safari"), what: L("Cached web content.", "תוכן אינטרנט שנשמר."), next: L("Downloaded again as you browse.", "יורד שוב תוך כדי גלישה."), howTo: L("Safari › Settings › Privacy › Manage Website Data.", "Safari › Settings › Privacy › Manage Website Data."))
        case "whatsapp.media": return LocationText(title: L("WhatsApp media", "מדיה של WhatsApp"), what: L("Photos, videos and files from chats.", "תמונות, סרטונים וקבצים משיחות."), next: L("Not re-downloadable from the Mac; review chat by chat.", "לא ניתן להוריד מחדש מהמק; סקור שיחה־שיחה."), howTo: L("Use the WhatsApp location in the sidebar and the chat filter.", "השתמש במיקום WhatsApp בסרגל הצדדי ובסינון השיחות."))
        case "messages.attachments": return LocationText(title: L("Messages attachments", "קבצים מצורפים של Messages"), what: L("Photos and files from iMessage.", "תמונות וקבצים מ־iMessage."), next: L("Deleting here breaks conversations.", "מחיקה כאן פוגעת בשיחות."), howTo: L("Messages › Settings › General › Keep messages, or delete attachments inside Messages.", "Messages › Settings › General › Keep messages, או מחק קבצים מצורפים בתוך Messages."))
        case "mail": return LocationText(title: L("Mail", "Mail"), what: L("Downloaded mailboxes and attachments.", "תיבות דואר וקבצים מצורפים שהורדו."), next: L("Do not touch the files; Mail rebuilds only from the server.", "אל תיגע בקבצים; Mail משחזר רק מהשרת."), howTo: L("Mail › Settings › Accounts › Download Attachments: Recent or None.", "Mail › Settings › Accounts › Download Attachments: Recent or None."))
        case "iphone.backups": return LocationText(title: L("iPhone and iPad backups", "גיבויי iPhone ו־iPad"), what: L("Full device backups made with Finder.", "גיבויים מלאים של מכשירים שנעשו עם Finder."), next: L("A deleted backup is gone; keep the latest per device.", "גיבוי שנמחק אבוד; שמור את האחרון לכל מכשיר."), howTo: L("Finder › your device › Manage Backups.", "Finder › המכשיר שלך › Manage Backups."))
        case "spotify.cache": return LocationText(title: L("Spotify cache", "מטמון Spotify"), what: L("Streamed music kept for offline playback.", "מוזיקה שהוזרמה ונשמרה לניגון לא מקוון."), next: L("Streams again.", "מוזרמת שוב."), howTo: nil)
        case "slack.cache", "teams.cache": return LocationText(title: L("Chat app cache", "מטמון אפליקציית צ׳אט"), what: L("Cached messages and images.", "הודעות ותמונות שנשמרו."), next: L("Downloaded again from the service.", "יורדות שוב מהשירות."), howTo: nil)
        case "zoom.data": return LocationText(title: "Zoom", what: L("Recordings and cached data.", "הקלטות ונתונים שנשמרו."), next: L("Local recordings would be lost.", "הקלטות מקומיות יאבדו."), howTo: L("Review recordings inside the folder before moving anything.", "סקור הקלטות בתוך התיקייה לפני כל העברה."))
        case "trash": return LocationText(title: L("Trash", "פח האשפה"), what: L("Everything you moved to Trash, from this app or Finder.", "כל מה שהעברת לפח, מהאפליקציה הזו או מ־Finder."), next: L("Space is only freed when Trash is emptied.", "המקום מתפנה רק כשמרוקנים את הפח."), howTo: L("Finder › Empty Trash, after you are sure.", "Finder › Empty Trash, אחרי שאתה בטוח."))
        default: return LocationText(title: location.id, what: "", next: "", howTo: nil)
        }
    }
    static func safetyTitle(_ safety: CleanupSafety) -> String {
        switch safety {
        case .rebuildable: return L("Safe to move to Trash", "בטוח להעביר לפח")
        case .cleanInsideApp: return L("Clean from the app itself", "לנקות מתוך האפליקציה עצמה")
        case .commandOnly: return L("Command in Terminal", "פקודה ב־Terminal")
        case .restartClears: return L("Cleared on restart", "מתנקה באתחול")
        case .keepOrReview: return L("Review before touching", "לסקור לפני שנוגעים")
        }
    }
    static func safetyColor(_ safety: CleanupSafety) -> NSColor {
        switch safety {
        case .rebuildable: return .systemGreen
        case .cleanInsideApp, .commandOnly: return .systemBlue
        case .restartClears: return .systemTeal
        case .keepOrReview: return .systemOrange
        }
    }
}

final class FreeUpTable: NSTableView {
    var onTrash: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { if !event.isARepeat { onTrash?() }; return }
        super.keyDown(with: event)
    }
}

/// "Free up space": the places macOS lumps into System Data, explained one by one. Sizes are measured on request only.
final class FreeUpPanel: NSView, NSTableViewDataSource, NSTableViewDelegate {
    struct Row { let location: KnownLocation; var measurement: LocationMeasurement?; var moved = false }
    let table = FreeUpTable()
    let measureButton = NSButton(), trashButton = NSButton(), revealButton = NSButton(), copyButton = NSButton()
    let detail = NSStackView()
    private let detailTitle = NSTextField(wrappingLabelWithString: ""), detailSize = NSTextField(labelWithString: ""), detailSafety = NSTextField(labelWithString: "")
    private let detailPath = PathLink(), detailWhat = NSTextField(wrappingLabelWithString: ""), detailNext = NSTextField(wrappingLabelWithString: ""), detailHow = NSTextField(wrappingLabelWithString: "")
    private let detailCommand = NSTextField(wrappingLabelWithString: "")
    private let caveat = NSTextField(wrappingLabelWithString: L("System Data in macOS Storage also counts local Time Machine snapshots and purgeable space, which no file move changes: they shrink on their own or after a restart. Nothing here is measured until you ask, and nothing is moved without a confirmation.", "System Data בהגדרות האחסון של macOS כולל גם תמונות מצב מקומיות של Time Machine ומקום purgeable, ששום העברת קבצים לא משנה: הם מצטמצמים לבד או אחרי אתחול. שום דבר כאן לא נמדד עד שתבקש, ושום דבר לא מועבר בלי אישור."))
    private(set) var rows: [Row] = []
    var home: URL = FileManager.default.homeDirectoryForCurrentUser
    var onMeasure: (([KnownLocation]) -> Void)?
    var onTrash: ((KnownLocation, LocationMeasurement) -> Void)?
    var onReveal: ((URL) -> Void)?
    var onCopyCommand: ((String) -> Void)?
    var onSelectionChange: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (button, en, he, symbol, action) in [(measureButton, "Measure all", "מדוד הכול", "ruler", #selector(measureAll)),
                                                  (revealButton, "Show in Finder", "הצג ב־Finder", "folder", #selector(revealSelected)),
                                                  (copyButton, "Copy command", "העתק פקודה", "doc.on.clipboard", #selector(copyCommand)),
                                                  (trashButton, "Move to Trash…", "העבר לפח…", "trash", #selector(trashSelected))] {
            button.title = L(en, he); button.target = self; button.action = action; button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 13, weight: .medium); button.setAccessibilityLabel(L(en, he))
        }
        trashButton.contentTintColor = .systemRed
        trashButton.toolTip = L("Moves this folder to Trash after measuring it again and confirming. Only for data the owning app rebuilds.", "מעביר את התיקייה לפח אחרי מדידה מחדש ואישור. רק לנתונים שהאפליקציה בונה מחדש.")
        measureButton.toolTip = L("Measures every listed location. Reads names and sizes only.", "מודד את כל המיקומים ברשימה. קורא רק שמות וגדלים.")
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let toolbar = NSStackView(views: [measureButton, spacer, revealButton, copyButton, trashButton]); toolbar.spacing = 8; toolbar.alignment = .centerY
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 12, height: 4); table.usesAlternatingRowBackgroundColors = false; table.style = .inset
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.allowsMultipleSelection = false
        table.setAccessibilityLabel(L("Free up space", "פינוי מקום"))
        for (id, title, width) in [("name", L("What", "מה"), 220.0), ("size", L("On disk", "בדיסק"), 76.0), ("safety", L("Verdict", "מסקנה"), 150.0), ("next", L("Next time", "בפעם הבאה"), 170.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = 56; table.addTableColumn(c)
        }
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = table
        let column = NSStackView(views: [toolbar, scroll]); column.orientation = .vertical; column.alignment = .leading; column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
        NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     toolbar.widthAnchor.constraint(equalTo: column.widthAnchor), scroll.widthAnchor.constraint(equalTo: column.widthAnchor)])
        table.delegate = self; table.dataSource = self
        table.onTrash = { [weak self] in self?.trashSelected() }

        detailTitle.font = .systemFont(ofSize: 17, weight: .medium); detailSize.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        detailSafety.font = .systemFont(ofSize: 12, weight: .semibold)
        for v in [detailWhat, detailNext, detailHow] { v.font = .systemFont(ofSize: 12); v.textColor = .secondaryLabelColor }
        detailCommand.font = .monospacedSystemFont(ofSize: 11, weight: .regular); detailCommand.isSelectable = true; detailCommand.textColor = .labelColor
        detailCommand.wantsLayer = true; detailCommand.layer?.cornerRadius = 6; detailCommand.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        caveat.font = .systemFont(ofSize: 11); caveat.textColor = .tertiaryLabelColor
        detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 10
        for view in [detailSize, detailTitle, detailSafety, detailPath, detailWhat, detailNext, detailHow, detailCommand, caveat] { detail.addArrangedSubview(view) }
        detail.setCustomSpacing(4, after: detailTitle); detail.setCustomSpacing(24, after: detailCommand)
        for view in [detailTitle, detailPath, detailWhat, detailNext, detailHow, detailCommand, caveat] { view.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true }
        detailPath.onOpen = { [weak self] in if let row = self?.selectedRow { self?.onReveal?(row.location.url(home: self!.home)) } }
        detail.setAccessibilityLabel(L("Location details", "פרטי המיקום"))
        updateDetail(); updateButtons()
    }
    required init?(coder: NSCoder) { nil }

    var selectedRow: Row? { table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil }
    var measuredTotal: Int64 { rows.reduce(0) { $0 + ($1.moved ? 0 : ($1.measurement?.bytes ?? 0)) } }
    var rebuildableTotal: Int64 { rows.filter { $0.location.safety == .rebuildable && !$0.moved }.reduce(0) { $0 + ($1.measurement?.bytes ?? 0) } }
    var unmeasured: [KnownLocation] { rows.filter { $0.measurement == nil && !$0.moved }.map(\.location) }

    /// Lists what exists on this Mac. Reads directory names only.
    func reload(keepMeasurements: Bool = false) {
        let old = Dictionary(rows.map { ($0.location.id, $0) }, uniquingKeysWith: { a, _ in a })
        let locations = KnownLocations.present(in: home) + KnownLocations.cacheFolders(in: home)
        rows = locations.map { Row(location: $0, measurement: keepMeasurements ? old[$0.id]?.measurement : nil, moved: keepMeasurements ? (old[$0.id]?.moved ?? false) : false) }
        sortRows(); table.reloadData(); if !rows.isEmpty, table.selectedRow < 0 { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateDetail(); updateButtons(); onSelectionChange?()
    }
    private func sortRows() {
        rows.sort { a, b in
            let ab = a.moved ? -1 : (a.measurement?.bytes ?? -1), bb = b.moved ? -1 : (b.measurement?.bytes ?? -1)
            if ab != bb { return ab > bb }
            return LocationTexts.text(for: a.location).title.localizedStandardCompare(LocationTexts.text(for: b.location).title) == .orderedAscending
        }
    }
    func apply(_ measurement: LocationMeasurement) {
        guard let index = rows.firstIndex(where: { $0.location.id == measurement.location.id }) else { return }
        let selected = selectedRow?.location.id
        rows[index].measurement = measurement; sortRows(); table.reloadData()
        if let id = selected, let i = rows.firstIndex(where: { $0.location.id == id }) { table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false) }
        updateDetail(); updateButtons(); onSelectionChange?()
    }
    func markMoved(_ location: KnownLocation) {
        guard let index = rows.firstIndex(where: { $0.location.id == location.id }) else { return }
        rows[index].moved = true; sortRows(); table.reloadData(); updateDetail(); updateButtons(); onSelectionChange?()
    }
    func setEnabled(_ enabled: Bool) { table.isEnabled = enabled; if enabled { updateButtons() } else { [measureButton, trashButton, revealButton, copyButton].forEach { $0.isEnabled = false } } }
    /// A folder came back from Trash: it is present again and needs measuring again.
    func restored(_ url: URL) {
        guard let index = rows.firstIndex(where: { $0.location.url(home: home).standardizedFileURL.path == url.standardizedFileURL.path }) else { return }
        rows[index].moved = false; rows[index].measurement = nil; sortRows(); table.reloadData(); updateDetail(); updateButtons(); onSelectionChange?()
    }

    @objc func measureAll() { let pending = unmeasured; if !pending.isEmpty { onMeasure?(pending) } }
    @objc func revealSelected() { if let row = selectedRow { onReveal?(row.location.url(home: home)) } }
    @objc func copyCommand() { if let command = selectedRow?.location.command { onCopyCommand?(command) } }
    @objc func trashSelected() {
        guard let row = selectedRow, row.location.safety == .rebuildable, !row.moved, let measurement = row.measurement, measurement.error == nil else { NSSound.beep(); return }
        onTrash?(row.location, measurement)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        let row = rows[index]; let text = LocationTexts.text(for: row.location)
        switch tableColumn?.identifier.rawValue {
        case "size":
            let v = NSTextField(labelWithString: row.moved ? L("moved", "הועבר") : (row.measurement.map { $0.error == nil ? bytes($0.bytes) + ($0.cancelled ? " ·…" : "") : "?" } ?? "—"))
            v.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); v.textColor = .secondaryLabelColor; v.alignment = .right; return v
        case "safety":
            let v = NSTextField(labelWithString: LocationTexts.safetyTitle(row.location.safety)); v.font = .systemFont(ofSize: 11, weight: .semibold); v.textColor = LocationTexts.safetyColor(row.location.safety); v.lineBreakMode = .byTruncatingTail; return v
        case "next":
            let v = NSTextField(labelWithString: text.next); v.font = .systemFont(ofSize: 11); v.textColor = .secondaryLabelColor; v.lineBreakMode = .byTruncatingTail; v.toolTip = text.next; return v
        default:
            let symbol: String = { switch row.location.category { case KnownLocations.developer: return "hammer"; case KnownLocations.ai: return "brain"; case KnownLocations.browser: return "safari"; case KnownLocations.messaging: return "message"; case KnownLocations.backups: return "externaldrive.badge.timemachine"; case KnownLocations.installers: return "shippingbox"; case KnownLocations.system: return "gearshape"; default: return "app" } }()
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()); icon.contentTintColor = row.moved ? .tertiaryLabelColor : LocationTexts.safetyColor(row.location.safety)
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true; icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let v = NSTextField(labelWithString: text.title); v.font = .systemFont(ofSize: 13, weight: .medium); v.lineBreakMode = .byTruncatingMiddle; if row.moved { v.textColor = .tertiaryLabelColor }
            let cell = NSStackView(views: [icon, v]); cell.spacing = 9; cell.toolTip = row.location.url(home: home).path; return cell
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail(); updateButtons(); onSelectionChange?() }

    private func updateDetail() {
        guard let row = selectedRow else {
            detailSize.stringValue = ""; detailTitle.stringValue = L("Free up space", "פינוי מקום"); detailSafety.stringValue = ""
            detailPath.stringValue = ""; detailWhat.stringValue = L("Nothing known found in this home folder.", "לא נמצא כאן דבר מהרשימה המוכרת."); detailNext.stringValue = ""; detailHow.stringValue = ""; detailCommand.isHidden = true; return
        }
        let text = LocationTexts.text(for: row.location)
        detailSize.stringValue = row.moved ? L("Moved to Trash", "הועבר לפח") : (row.measurement.map { $0.error == nil ? bytes($0.bytes) : L("Not measurable", "לא ניתן למדוד") } ?? L("Not measured yet", "טרם נמדד"))
        detailTitle.stringValue = text.title
        detailSafety.stringValue = LocationTexts.safetyTitle(row.location.safety); detailSafety.textColor = LocationTexts.safetyColor(row.location.safety)
        detailPath.stringValue = (row.location.url(home: home).path as NSString).abbreviatingWithTildeInPath; detailPath.toolTip = row.location.url(home: home).path
        detailWhat.stringValue = text.what
        detailNext.stringValue = L("Next time: ", "בפעם הבאה: ") + text.next
        if let measurement = row.measurement, let error = measurement.error { detailHow.stringValue = error }
        else if let how = text.howTo { detailHow.stringValue = how } else { detailHow.stringValue = row.location.safety == .rebuildable ? L("Measure, then Move to Trash. Undo with ⌘Z in this session.", "מדוד, ואז העבר לפח. שחזור עם ⌘Z בהפעלה זו.") : "" }
        detailHow.isHidden = detailHow.stringValue.isEmpty
        detailCommand.stringValue = row.location.command.map { "  " + $0 + "  " } ?? ""; detailCommand.isHidden = row.location.command == nil
    }
    private func updateButtons() {
        let row = selectedRow
        measureButton.isEnabled = !unmeasured.isEmpty
        revealButton.isEnabled = row != nil && row?.moved == false
        copyButton.isEnabled = row?.location.command != nil; copyButton.isHidden = row?.location.command == nil
        trashButton.isEnabled = row.map { $0.location.safety == .rebuildable && !$0.moved && $0.measurement != nil && $0.measurement?.error == nil } ?? false
        trashButton.isHidden = row?.location.safety != .rebuildable
    }
}
