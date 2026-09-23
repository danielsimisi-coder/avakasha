import Cocoa
import AvakashaCore

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
        case "xcode.simulators": return LocationText(title: L("Xcode simulators", "סימולטורים של Xcode"), what: L("Simulated iPhones, iPads and watches with the apps and data installed on them.", "מכשירי iPhone, iPad ושעונים מדומים, עם האפליקציות והנתונים שמותקנים בהם."), next: L("The command removes only simulators whose runtime is no longer installed; the rest and their data stay.", "הפקודה מסירה רק סימולטורים שסביבת הריצה שלהם כבר לא מותקנת; השאר והנתונים שלהם נשארים."), howTo: L("To remove more, delete devices in Xcode › Window › Devices and Simulators. Copy the command and run it in Terminal yourself.", "להסרה נוספת מוחקים מכשירים ב־Xcode › Window › Devices and Simulators. מעתיקים את הפקודה ומריצים אותה ב־Terminal."))
        case "xcode.simulatorCaches": return LocationText(title: L("Simulator caches", "מטמוני סימולטור"), what: L("Runtime caches for the simulators.", "מטמוני ריצה של הסימולטורים."), next: L("Recreated automatically.", "נוצרים מחדש אוטומטית."), howTo: nil)
        case "xcode.deviceSupport": return LocationText(title: L("iOS device support files", "קבצי תמיכה במכשירי iOS"), what: L("Debug symbols for each iOS version of the iPhones and iPads you connected.", "סמלי דיבאג לכל גרסת iOS של מכשירי iPhone ו־iPad שחיברת."), next: L("Xcode downloads them again the next time you connect the device; a few minutes.", "Xcode יוריד אותם שוב בחיבור הבא של המכשיר; כמה דקות."), howTo: nil)
        case "xcode.watchDeviceSupport": return LocationText(title: L("watchOS device support files", "קבצי תמיכה במכשירי watchOS"), what: L("Debug symbols for each iOS version of the devices you connected.", "סמלי דיבאג לכל גרסת iOS של המכשירים שחיברת."), next: L("Xcode downloads them again the next time you connect the device; a few minutes.", "Xcode יוריד אותם שוב בחיבור הבא של המכשיר; כמה דקות."), howTo: nil)
        case "xcode.derivedData": return LocationText(title: L("Xcode DerivedData", "DerivedData של Xcode"), what: L("Build products and indexes for every project you opened.", "תוצרי בנייה ואינדקסים לכל פרויקט שפתחת."), next: L("The next build recreates them; the first build is slower.", "הבנייה הבאה יוצרת אותם מחדש; הבנייה הראשונה איטית יותר."), howTo: nil)
        case "xcode.archives": return LocationText(title: L("Xcode archives", "ארכיוני Xcode"), what: L("Builds you archived for the App Store or for distribution, with their debug symbols.", "גרסאות שארכבת ל־App Store או להפצה, עם סמלי הדיבאג שלהן."), next: L("Old archives cannot be recreated. Keep the ones for versions still in use.", "ארכיונים ישנים אי אפשר ליצור מחדש. כדאי לשמור את אלה של גרסאות שעדיין בשימוש."), howTo: L("Xcode › Window › Organizer › Archives lets you delete old ones.", "Xcode › Window › Organizer › Archives מאפשר למחוק ישנים."))
        case "xcode.caches": return LocationText(title: L("Xcode cache", "מטמון Xcode"), what: L("Temporary Xcode data.", "נתונים זמניים של Xcode."), next: L("Recreated automatically.", "נוצר מחדש אוטומטית."), howTo: nil)
        case "orbstack": return LocationText(title: "OrbStack", what: L("Container images, volumes and Linux machines.", "אימג׳ים של קונטיינרים, נפחים ומכונות Linux."), next: L("Images download again; containers and their data do not come back.", "אימג׳ים יורדים שוב; קונטיינרים והנתונים שלהם לא חוזרים."), howTo: L("Delete unused machines and images from OrbStack itself so it stays consistent.", "מוחקים מכונות ואימג׳ים שאינם בשימוש מתוך OrbStack עצמו כדי שיישאר עקבי."))
        case "orbstack.data": return LocationText(title: L("OrbStack data", "נתוני OrbStack"), what: L("OrbStack's own configuration and machine state.", "ההגדרות ומצב המכונות של OrbStack עצמו."), next: L("Images download again; containers and their data do not come back.", "אימג׳ים יורדים שוב; קונטיינרים והנתונים שלהם לא חוזרים."), howTo: L("Delete unused machines and images from OrbStack itself so it stays consistent.", "מוחקים מכונות ואימג׳ים שאינם בשימוש מתוך OrbStack עצמו כדי שיישאר עקבי."))
        case "docker.vms": return LocationText(title: "Docker Desktop", what: L("The virtual disk that holds all images, containers and volumes.", "הדיסק הווירטואלי שמכיל את כל האימג׳ים, הקונטיינרים והנפחים."), next: L("Images download again; container data does not come back.", "אימג׳ים יורדים שוב; נתוני קונטיינרים לא חוזרים."), howTo: L("Docker Desktop › Settings › Resources › Advanced, or docker system prune.", "Docker Desktop › Settings › Resources › Advanced, או docker system prune."))
        case "npm.cache": return LocationText(title: L("npm cache", "מטמון npm"), what: L("Downloaded packages kept for faster installs.", "חבילות שהורדו ונשמרות להתקנות מהירות יותר."), next: L("Downloaded again on the next install.", "יורדות שוב בהתקנה הבאה."), howTo: L("Use npm's own command so its index stays consistent.", "משתמשים בפקודה של npm עצמו כדי שהאינדקס יישאר עקבי."))
        case "pnpm.store": return LocationText(title: L("pnpm store", "מאגר pnpm"), what: L("Shared packages for every pnpm project.", "חבילות משותפות לכל פרויקטי pnpm."), next: L("prune removes only packages no project uses.", "prune מסיר רק חבילות שאף פרויקט לא משתמש בהן."), howTo: nil)
        case "yarn.cache": return LocationText(title: L("Yarn cache", "מטמון Yarn"), what: L("Downloaded packages.", "חבילות שהורדו."), next: L("Downloaded again when needed.", "יורדות שוב בעת הצורך."), howTo: nil)
        case "homebrew.cache": return LocationText(title: L("Homebrew downloads", "הורדות Homebrew"), what: L("Installer bottles kept after installation.", "חבילות התקנה שנשמרו אחרי ההתקנה."), next: L("Downloaded again for upgrades.", "יורדות שוב בשדרוגים."), howTo: nil)
        case "gradle.caches": return LocationText(title: L("Gradle caches", "מטמוני Gradle"), what: L("Dependencies and build caches for Android and Java projects.", "תלויות ומטמוני בנייה לפרויקטי Android ו־Java."), next: L("Downloaded again on the next build.", "יורדים שוב בבנייה הבאה."), howTo: nil)
        case "maven.repository": return LocationText(title: L("Maven repository", "מאגר Maven"), what: L("Downloaded Java dependencies.", "תלויות Java שהורדו."), next: L("Downloaded again on the next build.", "יורדות שוב בבנייה הבאה."), howTo: nil)
        case "cocoapods.cache": return LocationText(title: L("CocoaPods cache", "מטמון CocoaPods"), what: L("Downloaded pods.", "Pods שהורדו."), next: L("Downloaded again on pod install.", "יורדים שוב ב־pod install."), howTo: nil)
        case "pip.cache": return LocationText(title: L("pip cache", "מטמון pip"), what: L("Downloaded Python packages.", "חבילות Python שהורדו."), next: L("Downloaded again when installed.", "יורדות שוב בהתקנה."), howTo: nil)
        case "cargo.registry": return LocationText(title: L("Cargo registry", "מאגר Cargo"), what: L("Downloaded Rust crates.", "Crates של Rust שהורדו."), next: L("Downloaded again on the next build.", "יורדים שוב בבנייה הבאה."), howTo: nil)
        case "go.modcache": return LocationText(title: L("Go module cache", "מטמון מודולים של Go"), what: L("Downloaded Go modules.", "מודולי Go שהורדו."), next: L("Downloaded again on the next build.", "יורדים שוב בבנייה הבאה."), howTo: nil)
        case "codex.cache": return LocationText(title: "Codex", what: L("Sessions and local data of the Codex CLI.", "סשנים ונתונים מקומיים של Codex CLI."), next: L("Session history would be lost.", "היסטוריית הסשנים תאבד."), howTo: L("Review inside the folder; keep what you still need.", "סוקרים בתוך התיקייה ושומרים מה שעדיין נחוץ."))
        case "claude.vmBundles": return LocationText(title: L("Claude Desktop sandbox images", "אימג׳ים של הסנדבוקס של Claude Desktop"), what: L("Virtual machine bundles for the local environment.", "חבילות מכונה וירטואלית לסביבה המקומית."), next: L("The app downloads them again; quit Claude first.", "האפליקציה מורידה אותן שוב; כדאי לסגור את Claude קודם."), howTo: nil)
        case "ai.huggingface": return LocationText(title: L("Hugging Face models", "מודלים של Hugging Face"), what: L("Downloaded AI models and datasets.", "מודלים ומערכי נתונים שהורדו."), next: L("Downloaded again the next time a script uses them.", "יורדים שוב בפעם הבאה שסקריפט משתמש בהם."), howTo: nil)
        case "ai.torch": return LocationText(title: L("PyTorch cache", "מטמון PyTorch"), what: L("Downloaded model weights.", "משקולות מודלים שהורדו."), next: L("Downloaded again when used.", "יורדות שוב בשימוש."), howTo: nil)
        case "ai.whisper": return LocationText(title: L("Whisper models", "מודלים של Whisper"), what: L("Downloaded speech models.", "מודלי דיבור שהורדו."), next: L("Downloaded again when used.", "יורדים שוב בשימוש."), howTo: nil)
        case "ai.ollama": return LocationText(title: L("Ollama models", "מודלים של Ollama"), what: L("Local language models.", "מודלי שפה מקומיים."), next: L("Downloaded again with ollama pull.", "יורדים שוב עם ollama pull."), howTo: nil)
        case "adobe.common": return LocationText(title: L("Adobe media cache", "מטמון מדיה של Adobe"), what: L("Premiere and After Effects render and peak files.", "קבצי רינדור ו־peak של Premiere ו־After Effects."), next: L("Rebuilt when a project opens.", "נבנים מחדש כשפרויקט נפתח."), howTo: L("Premiere › Settings › Media Cache › Delete Unused.", "Premiere › Settings › Media Cache › Delete Unused."))
        case "adobe.installers": return LocationText(title: L("Adobe installers", "קבצי התקנה של Adobe"), what: L("Old installer downloads.", "הורדות התקנה ישנות."), next: L("Creative Cloud downloads what it needs.", "Creative Cloud מוריד מה שצריך."), howTo: nil)
        case "adobe.uxp": return LocationText(title: L("Adobe plug-ins (UXP)", "תוספי Adobe (UXP)"), what: L("Installed plug-ins and their data.", "תוספים מותקנים והנתונים שלהם."), next: L("Plug-ins would need reinstalling.", "יהיה צורך להתקין תוספים מחדש."), howTo: L("Manage plug-ins from the Creative Cloud app.", "את התוספים מנהלים מאפליקציית Creative Cloud."))
        case "wondershare.installer": return LocationText(title: L("Wondershare installer leftovers", "שאריות התקנה של Wondershare"), what: L("Files left by an installer.", "קבצים שנשארו ממתקין."), next: L("Nothing is lost; the installer downloads again if ever needed.", "שום דבר לא אובד; המתקין יורד שוב אם יידרש."), howTo: nil)
        case "quicklook.thumbnails": return LocationText(title: L("Quick Look thumbnails", "תמונות ממוזערות של Quick Look"), what: L("Cached previews.", "תצוגות מקדימות שנשמרו."), next: L("Generated again as you browse.", "נוצרות שוב תוך כדי גלישה."), howTo: nil)
        case "system.caches": return LocationText(title: L("All app caches", "כל מטמוני האפליקציות"), what: L("Every app's cache folder. Each one is listed separately below.", "תיקיית המטמון של כל אפליקציה. כל אחת מופיעה בנפרד למטה."), next: L("Apps rebuild their caches.", "אפליקציות בונות מחדש את המטמונים."), howTo: L("Move individual app caches below rather than the whole folder.", "עדיף להעביר מטמוני אפליקציות בודדים למטה ולא את התיקייה כולה."))
        case "system.logs": return LocationText(title: L("Logs", "יומנים"), what: L("Diagnostic logs from apps and the system.", "יומני אבחון של אפליקציות והמערכת."), next: L("New logs are written as needed.", "יומנים חדשים נכתבים לפי הצורך."), howTo: nil)
        case "system.tempFolders": return LocationText(title: L("System temporary folders", "תיקיות זמניות של המערכת"), what: L("Caches and temporary files macOS manages.", "מטמונים וקבצים זמניים ש־macOS מנהל."), next: L("Cleared on restart.", "מתנקה באתחול."), howTo: L("Restart the Mac.", "מפעילים מחדש את ה־Mac."))
        case "chrome.cache": return LocationText(title: L("Chrome cache", "מטמון Chrome"), what: L("Cached pages and images.", "דפים ותמונות שנשמרו."), next: L("Downloaded again as you browse.", "יורדים שוב תוך כדי גלישה."), howTo: L("Chrome › Clear browsing data › Cached images and files.", "Chrome › Clear browsing data › Cached images and files."))
        case "chrome": return LocationText(title: L("Chrome profiles", "פרופילי Chrome"), what: L("Profiles, extensions and cache.", "פרופילים, תוספים ומטמון."), next: L("Profiles hold logins; only the cache is safe to clear.", "הפרופילים מכילים כניסות; רק המטמון בטוח לניקוי."), howTo: L("Chrome › Clear browsing data › Cached images and files.", "Chrome › Clear browsing data › Cached images and files."))
        case "safari.cache": return LocationText(title: L("Safari cache", "מטמון Safari"), what: L("Cached web content.", "תוכן אינטרנט שנשמר."), next: L("Downloaded again as you browse.", "יורד שוב תוך כדי גלישה."), howTo: L("Safari › Settings › Privacy › Manage Website Data.", "Safari › Settings › Privacy › Manage Website Data."))
        case "whatsapp.media": return LocationText(title: L("WhatsApp media", "מדיה של WhatsApp"), what: L("Photos, videos and files from chats.", "תמונות, סרטונים וקבצים משיחות."), next: L("Not re-downloadable from the Mac; review chat by chat.", "לא ניתן להוריד מחדש מה־Mac; סוקרים שיחה־שיחה."), howTo: L("Use the WhatsApp location in the sidebar and the chat filter.", "משתמשים במיקום WhatsApp בסרגל הצד ובסינון השיחות."))
        case "messages.attachments": return LocationText(title: L("Messages attachments", "קבצים מצורפים של Messages"), what: L("Photos and files from iMessage.", "תמונות וקבצים מ־iMessage."), next: L("Moving these breaks conversations in Messages.", "העברה מכאן פוגעת בשיחות ב־Messages."), howTo: L("Messages › Settings › General › Keep messages, or delete attachments inside Messages.", "Messages › Settings › General › Keep messages, או מחיקת קבצים מצורפים בתוך Messages."))
        case "mail": return LocationText(title: L("Mail", "Mail"), what: L("Downloaded mailboxes and attachments.", "תיבות דואר וקבצים מצורפים שהורדו."), next: L("Leave these files alone; Mail can only rebuild them from the server.", "עדיף לא לגעת בקבצים; Mail משחזר אותם רק מהשרת."), howTo: L("Mail › Settings › Accounts › Download Attachments: Recent or None.", "Mail › Settings › Accounts › Download Attachments: Recent or None."))
        case "iphone.backups": return LocationText(title: L("iPhone and iPad backups", "גיבויי iPhone ו־iPad"), what: L("Full device backups made with Finder.", "גיבויים מלאים של מכשירים שנעשו עם Finder."), next: L("A backup that is emptied from Trash cannot be recreated; keep the latest for each device.", "גיבוי שרוקן מהפח אי אפשר ליצור מחדש; כדאי לשמור את האחרון לכל מכשיר."), howTo: L("Finder › your device › Manage Backups.", "Finder › המכשיר שלך › Manage Backups."))
        case "spotify.cache": return LocationText(title: L("Spotify cache", "מטמון Spotify"), what: L("Streamed music kept for offline playback.", "מוזיקה שהוזרמה ונשמרה לניגון לא מקוון."), next: L("Streams again.", "מוזרמת שוב."), howTo: nil)
        case "slack.cache": return LocationText(title: L("Slack cache", "מטמון Slack"), what: L("Cached messages and images.", "הודעות ותמונות שנשמרו."), next: L("Downloaded again from the service.", "יורדות שוב מהשירות."), howTo: nil)
        case "teams.cache": return LocationText(title: L("Teams cache", "מטמון Teams"), what: L("Cached messages and images.", "הודעות ותמונות שנשמרו."), next: L("Downloaded again from the service.", "יורדות שוב מהשירות."), howTo: nil)
        case "zoom.data": return LocationText(title: "Zoom", what: L("Recordings and cached data.", "הקלטות ונתונים שנשמרו."), next: L("Local recordings would be lost.", "הקלטות מקומיות יאבדו."), howTo: L("Review recordings inside the folder before moving anything.", "סוקרים את ההקלטות בתוך התיקייה לפני כל העברה."))
        case "trash": return LocationText(title: L("Trash", "פח האשפה"), what: L("Everything you moved to Trash, from this app or Finder.", "כל מה שהעברת לפח, מהאפליקציה הזו או מ־Finder."), next: L("Space is only freed when Trash is emptied.", "המקום מתפנה רק כשמרוקנים את הפח."), howTo: L("Finder › Empty Trash, after you are sure.", "Finder › Empty Trash, כשברור לך שאפשר."))
        default: return LocationText(title: location.id, what: "", next: "", howTo: nil)
        }
    }
    static func safetyTitle(_ safety: CleanupSafety) -> String {
        switch safety {
        case .rebuildable: return L("Rebuildable · can go to Trash", "נבנה מחדש · אפשר להעביר לפח")
        case .cleanInsideApp: return L("Clean from the app itself", "לנקות מתוך האפליקציה עצמה")
        case .commandOnly: return L("Command in Terminal", "פקודה ב־Terminal")
        case .restartClears: return L("Cleared on restart", "מתנקה באתחול")
        case .keepOrReview: return L("Review before moving", "לסקור לפני העברה")
        }
    }
    /// Three states, shown as a dot beside the word: green may go, orange review first, grey is handled elsewhere (the app, Terminal, a restart).
    static func safetyColor(_ safety: CleanupSafety) -> NSColor {
        switch safety {
        case .rebuildable: return .systemGreen
        case .keepOrReview: return .systemOrange
        case .cleanInsideApp, .commandOnly, .restartClears: return .secondaryLabelColor
        }
    }
    /// The 9-pt dot that carries the safety colour; the word next to it carries the meaning, so the dot is silent for VoiceOver.
    static func safetyDot(_ safety: CleanupSafety) -> NSImageView {
        let dot = NSImageView(image: symbol("circle.fill", 9) ?? NSImage()); dot.contentTintColor = safetyColor(safety); dot.setAccessibilityElement(false)
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true; dot.heightAnchor.constraint(equalToConstant: 10).isActive = true; return dot
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
    /// Under the big number: "Not measured yet", "Not measurable" or "Moved to Trash", so the display slot only ever holds a size or a dash.
    private let detailState = NSTextField(labelWithString: "")
    private let detailSafetyRow = NSStackView()
    private let detailPath = PathLink(), detailWhat = NSTextField(wrappingLabelWithString: ""), detailNext = NSTextField(wrappingLabelWithString: ""), detailHow = NSTextField(wrappingLabelWithString: "")
    private let detailCommand = NSTextField(wrappingLabelWithString: "")
    /// One line on screen; the full explanation opens from the ⓘ.
    private let caveat = NSTextField(labelWithString: L("System Data also counts snapshots and purgeable space.", "נתוני מערכת כוללים גם תמונות מצב ומקום שניתן לפינוי."))
    private let caveatInfo = InfoButton(L("More about System Data", "עוד על נתוני המערכת"), L("System Data in macOS Storage also counts local Time Machine snapshots and purgeable space, which no file move changes: they shrink on their own or after a restart. Nothing here is measured until you ask, and nothing is moved without a confirmation.", "נתוני מערכת (System Data) בהגדרות האחסון של macOS כוללים גם תמונות מצב מקומיות של Time Machine ומקום שניתן לפינוי, ששום העברת קבצים לא משנה: הם מצטמצמים לבד או אחרי אתחול. שום דבר כאן לא נמדד בלי בקשה מפורשת, ושום דבר לא מועבר בלי אישור."))
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
            button.font = Type.bodyMedium; button.setAccessibilityLabel(L(en, he))
        }
        trashButton.image = symbol("trash", 13, .medium, color: .systemRed) // red on the glyph only
        trashButton.toolTip = L("Moves this folder to Trash after measuring it again and confirming. Only for data the owning app rebuilds.", "מעביר את התיקייה לפח אחרי מדידה מחדש ואישור. רק לנתונים שהאפליקציה בונה מחדש.")
        measureButton.toolTip = L("Measures every listed location. Reads names and sizes only.", "מודד את כל המיקומים ברשימה. קורא רק שמות וגדלים.")
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let toolbar = NSStackView(views: [measureButton, spacer, revealButton, copyButton, trashButton]); toolbar.spacing = 8; toolbar.alignment = .centerY
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 12, height: 4); table.usesAlternatingRowBackgroundColors = false; table.style = .inset
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.allowsMultipleSelection = false
        table.setAccessibilityLabel(L("Free up space", "פינוי מקום"))
        for (id, title, width) in [("name", L("Location", "מיקום"), 220.0), ("size", L("On disk", "בדיסק"), 76.0), ("safety", L("Advice", "המלצה"), 150.0), ("next", L("What happens next", "מה קורה אחר כך"), 170.0)] {
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

        detailTitle.font = Type.headline; detailSize.font = Type.display
        detailState.font = Type.subhead; detailState.textColor = .secondaryLabelColor
        detailSafety.font = .systemFont(ofSize: 12, weight: .semibold); detailSafety.textColor = .labelColor
        detailSafetyRow.spacing = 6; detailSafetyRow.alignment = .centerY; detailSafetyRow.addArrangedSubview(detailSafety)
        for v in [detailWhat, detailNext, detailHow] { v.font = Type.subhead; v.textColor = .secondaryLabelColor }
        detailCommand.font = .monospacedSystemFont(ofSize: 11, weight: .regular); detailCommand.isSelectable = true; detailCommand.textColor = .labelColor
        detailCommand.wantsLayer = true; detailCommand.layer?.cornerRadius = 6; detailCommand.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        caveat.font = Type.subhead; caveat.textColor = .secondaryLabelColor; caveat.lineBreakMode = .byTruncatingTail; caveat.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let caveatRow = NSStackView(views: [caveat, caveatInfo]); caveatRow.spacing = 4; caveatRow.alignment = .centerY
        detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 8
        for view in [detailSize, detailState, detailTitle, detailSafetyRow, detailPath, detailWhat, detailNext, detailHow, detailCommand, caveatRow] { detail.addArrangedSubview(view) }
        detail.setCustomSpacing(2, after: detailSize); detail.setCustomSpacing(4, after: detailTitle); detail.setCustomSpacing(16, after: detailPath); detail.setCustomSpacing(24, after: detailCommand)
        for view in [detailTitle, detailPath, detailWhat, detailNext, detailHow, detailCommand, caveatRow] { view.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true }
        detailPath.setAccessibilityLabel(L("Folder path", "נתיב התיקייה")); detailPath.setAccessibilityHelp(L("Opens the folder in Finder. Right-click copies the path.", "פותח את התיקייה ב־Finder. לחיצה ימנית מעתיקה את הנתיב."))
        detailPath.onOpen = { [weak self] in if let row = self?.selectedRow { self?.onReveal?(row.location.url(home: self!.home)) } }
        detail.setAccessibilityLabel(L("Location details", "פרטי המיקום"))
        updateDetail(); updateButtons()
    }
    required init?(coder: NSCoder) { nil }

    var selectedRow: Row? { table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil }
    /// Rows nested inside another listed row (per-app caches under Library/Caches) are not counted twice.
    var measuredTotal: Int64 {
        rows.filter { r in !r.moved && !rows.contains { o in o.location.id != r.location.id && r.location.relativePath.hasPrefix(o.location.relativePath + "/") } }
            .reduce(0) { $0 + ($1.measurement?.bytes ?? 0) }
    }
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
            let v = NSTextField(labelWithString: row.moved ? L("moved", "הועבר") : (row.measurement.map { $0.error == nil ? bytes($0.bytes) : "?" } ?? "—"))
            v.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); v.textColor = .secondaryLabelColor; v.alignment = .right
            let cell = NSStackView(views: [v]); cell.alignment = .centerY; v.widthAnchor.constraint(equalTo: cell.widthAnchor).isActive = true; return cell
        case "safety":
            let v = NSTextField(labelWithString: LocationTexts.safetyTitle(row.location.safety)); v.font = .systemFont(ofSize: 11, weight: .semibold); v.textColor = .labelColor; v.lineBreakMode = .byTruncatingTail
            let cell = NSStackView(views: [LocationTexts.safetyDot(row.location.safety), v]); cell.spacing = 6; cell.alignment = .centerY; return cell
        case "next":
            let v = NSTextField(labelWithString: text.next); v.font = Type.caption; v.textColor = .secondaryLabelColor; v.lineBreakMode = .byTruncatingTail; v.toolTip = text.next
            let cell = NSStackView(views: [v]); cell.alignment = .centerY; v.widthAnchor.constraint(equalTo: cell.widthAnchor).isActive = true; return cell
        default:
            let name: String = { switch row.location.category { case KnownLocations.developer: return "hammer"; case KnownLocations.ai: return "brain"; case KnownLocations.browser: return "safari"; case KnownLocations.messaging: return "message"; case KnownLocations.backups: return "externaldrive.badge.timemachine"; case KnownLocations.installers: return "shippingbox"; case KnownLocations.system: return "gearshape"; default: return "app" } }()
            let icon = NSImageView(image: symbol(name, 14) ?? NSImage()); icon.contentTintColor = row.moved ? .tertiaryLabelColor : .secondaryLabelColor; icon.setAccessibilityElement(false)
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true; icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let v = NSTextField(labelWithString: text.title); v.font = Type.bodyMedium; v.lineBreakMode = .byTruncatingMiddle
            if row.moved { v.textColor = .secondaryLabelColor; v.attributedStringValue = NSAttributedString(string: text.title, attributes: [.font: Type.bodyMedium, .foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]) } // moved, still undoable: readable, struck through
            let cell = NSStackView(views: [icon, v]); cell.spacing = 9; cell.toolTip = row.location.url(home: home).path; return cell
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateDetail(); updateButtons(); onSelectionChange?() }

    private func updateDetail() {
        guard let row = selectedRow else {
            detailSize.stringValue = ""; detailState.stringValue = ""; detailState.isHidden = true; detailTitle.stringValue = L("Free up space", "פינוי מקום"); detailSafety.stringValue = ""; detailSafetyRow.isHidden = true
            detailPath.stringValue = ""; detailWhat.stringValue = rows.isEmpty ? L("Nothing from the known list exists in this home folder.", "לא נמצא כאן דבר מהרשימה המוכרת.") : L("Select a location to see what it is and what happens after it goes to Trash.", "בוחרים מיקום כדי לראות מה הוא ומה קורה אחרי שהוא עובר לפח.")
            detailNext.stringValue = ""; detailHow.stringValue = ""; detailHow.isHidden = true; detailCommand.isHidden = true; return
        }
        let text = LocationTexts.text(for: row.location)
        let size = row.measurement.map { $0.error == nil ? bytes($0.bytes) : "—" } ?? "—"
        detailSize.attributedStringValue = NSAttributedString(string: size, attributes: row.moved ? [.font: Type.display, .foregroundColor: NSColor.labelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue] : [.font: Type.display, .foregroundColor: NSColor.labelColor])
        detailState.stringValue = row.moved ? L("Moved to Trash", "הועבר לפח") : (row.measurement.map { $0.error == nil ? "" : L("Not measurable", "לא ניתן למדוד") } ?? L("Not measured yet", "טרם נמדד"))
        detailState.textColor = row.moved ? NSColor.systemGreen.blended(withFraction: 0.45, of: .labelColor) ?? .labelColor : .secondaryLabelColor; detailState.isHidden = detailState.stringValue.isEmpty
        detailTitle.stringValue = text.title
        detailSafety.stringValue = LocationTexts.safetyTitle(row.location.safety); detailSafetyRow.isHidden = false
        detailSafetyRow.arrangedSubviews.filter { $0 !== detailSafety }.forEach { $0.removeFromSuperview() }; detailSafetyRow.insertArrangedSubview(LocationTexts.safetyDot(row.location.safety), at: 0)
        detailPath.stringValue = (row.location.url(home: home).path as NSString).abbreviatingWithTildeInPath; detailPath.toolTip = row.location.url(home: home).path
        detailWhat.stringValue = text.what
        detailNext.stringValue = L("Afterwards: ", "אחר כך: ") + text.next
        if let measurement = row.measurement, let error = measurement.error { detailHow.stringValue = error }
        else if let how = text.howTo { detailHow.stringValue = how }
        else { detailHow.stringValue = row.location.safety == .rebuildable ? L("Measure, then Move to Trash. Undo with ⌘Z in this session.", "מודדים, ואז מעבירים לפח. אפשר לבטל עם ⌘Z בהפעלה זו.") : (row.location.safety == .commandOnly ? L("Copy the command and run it in Terminal yourself. The app never runs commands, and the tool deletes immediately, without Trash or Undo.", "מעתיקים את הפקודה ומריצים אותה ב־Terminal. האפליקציה לעולם לא מריצה פקודות, והכלי מוחק מיד, בלי פח ובלי ביטול.") : "") }
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
