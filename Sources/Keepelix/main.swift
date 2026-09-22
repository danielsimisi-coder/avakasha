import Cocoa
import Quartz
import KeepelixCore

func L(_ en: String, _ he: String) -> String { (Locale.preferredLanguages.first ?? "en").hasPrefix("he") ? he : en }
func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

final class FileTable: NSTableView {
    weak var owner: AppController?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { if !event.isARepeat {owner?.trashSelection()};return }
        if event.keyCode == 49 { owner?.togglePreview(); return }
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
    let demoMode = ProcessInfo.processInfo.arguments.contains("--demo")
    var demoFolder: URL?
    let preferences: UserDefaults = {
        if ProcessInfo.processInfo.arguments.contains("--demo") { return UserDefaults(suiteName:"Keepelix.SyntheticDemo")! }
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
    let sortPicker = NSPopUpButton()
    let ageHint = NSTextField(labelWithString:L("Based on last modification — age alone does not mean a file is unused.","לפי השינוי האחרון — גיל הקובץ לא מעיד בהכרח שלא השתמשת בו."))
    let status = NSTextField(labelWithString: "")
    let selectionLabel = NSTextField(labelWithString: "")
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
    var previewOpen = false
    var contextRow = -1
    var history = TrashHistory()
    var folderHistories: [String: TrashHistory] = [:]
    var trashBackend: TrashBackend = SystemTrash()
    var redoButton: NSButton!
    var confirmationMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1320,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.delegate=self; window.title="Keepelix · 0.1.0 beta 2"
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
        func spacer()->NSView {let v=NSView();v.setContentHuggingPriority(.init(1),for:.horizontal);return v}
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
        let sidebarContent=column([brand,label(L("LOCATIONS","מיקומים"),10,.semibold,true),locationList,choose,divider(),olderButton,openBin,sidebarSpacer,privacy],18)
        let sidebar=NSVisualEffectView();sidebar.material = .sidebar;sidebar.blendingMode = .behindWindow;sidebar.state = .followsWindowActiveState
        sidebar.addSubview(sidebarContent);sidebarContent.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([sidebar.widthAnchor.constraint(equalToConstant:216),sidebarContent.leadingAnchor.constraint(equalTo:sidebar.leadingAnchor,constant:20),sidebarContent.trailingAnchor.constraint(equalTo:sidebar.trailingAnchor,constant:-16),sidebarContent.topAnchor.constraint(equalTo:sidebar.topAnchor,constant:24),sidebarContent.bottomAnchor.constraint(equalTo:sidebar.bottomAnchor,constant:-24),locationList.widthAnchor.constraint(equalTo:sidebarContent.widthAnchor)])
        for b in locationButtons { b.widthAnchor.constraint(equalTo:locationList.widthAnchor).isActive=true }
        choose.font = .systemFont(ofSize:11);choose.controlSize = .small
        let resume=button("Resume","המשך סקירה","clock.arrow.circlepath",#selector(resumeFolder))
        let rescan=button("Refresh","רענן","arrow.clockwise",#selector(rescanFolder))
        let heading=column([label(L("Your files","הקבצים שלך"),23,.semibold)],6)
        let header=row([heading,spacer(),resume,rescan])
        folderLabel.font = .monospacedSystemFont(ofSize:11,weight:.regular);folderLabel.textColor = .secondaryLabelColor;folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.stringValue=L("Choose a location from the sidebar to begin","בחר מיקום מהסרגל הצדדי כדי להתחיל")
        search.placeholderString=L("Search files…","חפש קבצים…");search.delegate=self;search.controlSize = .large
        search.widthAnchor.constraint(greaterThanOrEqualToConstant:210).isActive=true
        sizeFilter.addItems(withTitles:[L("All sizes","כל הגדלים"),"> 10 MB","> 100 MB","> 1 GB"]);sizeFilter.selectItem(at:0)
        kindFilter.addItem(withTitle:L("All types","כל הסוגים"));kindFilter.addItems(withTitles:FileKind.allCases.map(\.rawValue))
        for popup in [sizeFilter,kindFilter] {popup.target=self;popup.action = #selector(applyFilters);popup.font = .systemFont(ofSize:12)}
        sortPicker.addItems(withTitles:[L("Largest first","הגדולים תחילה"),L("Smallest first","הקטנים תחילה"),L("Oldest first","הישנים תחילה"),L("Newest first","החדשים תחילה"),L("Name A–Z","שם א–ת"),L("Name Z–A","שם ת–א")]);sortPicker.target=self;sortPicker.action = #selector(changeSort);sortPicker.font = .systemFont(ofSize:12)
        let filters=row([search,sizeFilter,kindFilter,sortPicker]);search.setContentHuggingPriority(.init(1),for:.horizontal)
        mode.addItems(withTitles:[L("All files","כל הקבצים"),L("Exact duplicates","כפילויות זהות"),L("Similar images","תמונות דומות"),L("Older files","קבצים ישנים")]);mode.target=self;mode.action = #selector(modeChanged)
        groupPicker.target=self;groupPicker.action = #selector(applyFilters)
        let exactButton=button("Find duplicates","מצא כפילויות","square.on.square",#selector(findExactDuplicates))
        let similarButton=button("Compare images","השווה תמונות","photo.on.rectangle.angled",#selector(findSimilarImages))
        agePicker.addItems(withTitles:[L("Not modified in 6 months","לא שונו בחצי שנה"),L("Not modified in 1 year","לא שונו בשנה"),L("Not modified in 2 years","לא שונו בשנתיים"),L("Not modified in 5 years","לא שונו בחמש שנים")]);agePicker.selectItem(at:1);agePicker.target=self;agePicker.action = #selector(applyFilters)
        ageHint.font = .systemFont(ofSize:11);ageHint.textColor = .secondaryLabelColor
        let analysis=row([mode,groupPicker,agePicker,spacer(),exactButton,similarButton])
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
        table.frame=NSRect(x:0,y:0,width:540,height:440);table.autoresizingMask=[.width];table.owner=self;table.delegate=self;table.dataSource=self
        table.allowsMultipleSelection=true;table.rowHeight=38;table.intercellSpacing=NSSize(width:12,height:4);table.usesAlternatingRowBackgroundColors=false;table.style = .inset;table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (id,title,width) in [("name",L("Name","שם"),240.0),("size",L("On disk","בדיסק"),80.0),("modified",L("Last modified","שינוי אחרון"),100.0)] {
            let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));c.title=title;c.width=width;c.sortDescriptorPrototype=NSSortDescriptor(key:id,ascending:id != "size");table.addTableColumn(c)
        }
        scroll.documentView=table
        primary=QLPreviewView(frame:NSRect(x:0,y:0,width:330,height:440),style:.normal);primary.autostarts=false
        comparison=QLPreviewView(frame:NSRect(x:0,y:0,width:330,height:440),style:.normal);comparison.autostarts=false
        let previews=row([primary,comparison],8);previews.distribution = .fillEqually
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
        let split=NSSplitView();split.isVertical=true;split.dividerStyle = .thin;split.addArrangedSubview(listHost);split.addArrangedSubview(previewHost)
        listHost.widthAnchor.constraint(greaterThanOrEqualToConstant:480).isActive=true;previewHost.widthAnchor.constraint(greaterThanOrEqualToConstant:270).isActive=true
        let workspace=NSBox();workspace.boxType = .custom;workspace.borderColor = .separatorColor;workspace.borderWidth=0.5;workspace.cornerRadius=12;workspace.fillColor = .controlBackgroundColor;workspace.contentViewMargins = NSSize(width:0,height:0);workspace.contentView=split
        let all=button("Select all","בחר הכול","checkmark.circle",#selector(selectAllFiles))
        extrasButton=button("Select extra copies","בחר עותקים נוספים","checkmark.circle.badge.plus",#selector(selectExtras))
        selectionLabel.font = .systemFont(ofSize:12,weight:.medium);selectionLabel.textColor = .secondaryLabelColor
        let selection=row([all,extrasButton,spacer(),selectionLabel],8)
        let preview=button("Preview","תצוגה מקדימה","eye",#selector(togglePreview));preview.toolTip=L("Space to toggle preview","רווח לפתיחה וסגירה של תצוגה מקדימה")
        let next=button("Keep & next","השאר והמשך","arrow.right",#selector(nextFile))
        let trash=button("Move to Trash…","העבר לפח…","trash",#selector(trashSelection));trash.contentTintColor = .systemRed
        undoButton=button("Undo","שחזר","arrow.uturn.backward",#selector(undoTrash))
        redoButton=button("Redo","בצע שוב","arrow.uturn.forward",#selector(redoTrash))
        let review=row([preview,next,spacer(),undoButton,redoButton,trash])
        cancelButton=NSButton(title:L("Cancel","בטל"),target:self,action:#selector(cancelWork));cancelButton.bezelStyle = .rounded;cancelButton.isEnabled=false
        spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false
        status.font = .systemFont(ofSize:11);status.textColor = .secondaryLabelColor;status.lineBreakMode = .byTruncatingTail
        let footer=row([spinner,status,spacer(),cancelButton],8)
        let tips=label(L("Space · Preview     Delete · Trash     ⌘Z · Undo","רווח · תצוגה     Delete · פח     ⌘Z · שחזור"),11,.regular,true)
        let bottom=row([tips,spacer()])
        let content=column([header,folderLabel,filters,analysis,ageHint,workspace,selection,divider(),review,footer,bottom],12)
        content.setCustomSpacing(20,after:header);content.setCustomSpacing(16,after:folderLabel)
        let host=NSView();host.addSubview(content);content.translatesAutoresizingMaskIntoConstraints=false
        let rootLayout=row([sidebar,host],0);rootLayout.alignment = .top;rootLayout.distribution = .fill;rootLayout.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(rootLayout)
        NSLayoutConstraint.activate([rootLayout.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),rootLayout.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),rootLayout.topAnchor.constraint(equalTo:window.contentView!.topAnchor),rootLayout.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor),sidebar.heightAnchor.constraint(equalTo:rootLayout.heightAnchor),host.widthAnchor.constraint(equalTo:rootLayout.widthAnchor,constant:-216),host.heightAnchor.constraint(equalTo:rootLayout.heightAnchor),content.leadingAnchor.constraint(equalTo:host.leadingAnchor,constant:26),content.trailingAnchor.constraint(equalTo:host.trailingAnchor,constant:-26),content.topAnchor.constraint(equalTo:host.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:host.bottomAnchor,constant:-18),workspace.heightAnchor.constraint(greaterThanOrEqualToConstant:250)])
        for v in [header,folderLabel,filters,analysis,ageHint,workspace,selection,review,footer,bottom] {v.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true}
        makeMenus();modeChanged();updateEnabled();updatePreview()
        status.stringValue=L("Ready — choose a location to start.","מוכן — בחר מיקום כדי להתחיל.")
        if smokeMode {runSmokeTests();return}
        if ProcessInfo.processInfo.arguments.contains("--launch-check") {print("Packaged launch passed: production preferences and interface initialized; no scan started.");fflush(stdout);exit(0)}
        if ProcessInfo.processInfo.arguments.contains("--demo") { prepareDemo() }
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(table);NSApp.activate(ignoringOtherApps:true)
    }
    func prepareDemo() {
        window.title="Keepelix · Read-only demo"
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("Keepelix-Demo-"+UUID().uuidString,isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);demoFolder=folder
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
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1514764800)],ofItemAtPath:folder.appendingPathComponent("Weekend notes.txt").path)
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:1577836800)],ofItemAtPath:folder.appendingPathComponent("Mountain light.png").path)
            root=folder;files=try Scanner.scan(root:folder,token:CancellationToken()).files;sizeFilter.selectItem(at:0);applyFilters()
            folderLabel.stringValue=L("Example collection · generated demo files","אוסף לדוגמה · קבצים מלאכותיים")
            status.stringValue=L("Read-only demo · generated files only","הדגמה לקריאה בלבד · קבצים מלאכותיים בלבד")
            if let row=shown.firstIndex(where:{$0.name == "Coastal morning.png"}) {table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);previewOpen=true;updatePreview()}
        } catch {show("Demo unavailable",error.localizedDescription)}
    }
    func applicationWillTerminate(_ notification:Notification) {
        if let demoFolder=demoFolder {try? FileManager.default.removeItem(at:demoFolder);preferences.removePersistentDomain(forName:"Keepelix.SyntheticDemo")}
    }
    func makeMenus() {
        let main = NSMenu(); let app = NSMenuItem(); main.addItem(app); let menu = NSMenu(); app.submenu = menu
        let about = NSMenuItem(title: L("About Keepelix", "אודות Keepelix"), action: #selector(aboutApp), keyEquivalent: ""); about.target = self; menu.addItem(about)
        menu.addItem(withTitle: L("Quit Keepelix","סגור Keepelix"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "Edit"; main.addItem(edit); edit.submenu = NSMenu(title:"Edit")
        for (title,selector,key) in [(L("Select all","בחר הכול"),#selector(selectAllCommand),"a"),(L("Undo","שחזר"),#selector(undoCommand),"z")] {
            let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target=self; edit.submenu!.addItem(item)
        }
        let redoItem=NSMenuItem(title:L("Redo","בצע שוב"),action:#selector(redoCommand),keyEquivalent:"z");redoItem.keyEquivalentModifierMask=[.command,.shift];redoItem.target=self;edit.submenu!.addItem(redoItem)
        menu.insertItem(.separator(),at:1)
        let confirmation=NSMenuItem(title:L("Confirm before Trash","אישור לפני העברה לפח"),action:#selector(toggleTrashConfirmation(_:)),keyEquivalent:"");confirmation.target=self;confirmation.state=preferences.bool(forKey:"skipTrashConfirmation") ? .off : .on;menu.insertItem(confirmation,at:2);confirmationMenuItem=confirmation
        // Standard text editing remains available in the search field.
        edit.submenu!.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.submenu!.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        NSApp.mainMenu=main
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
            return !busy && !demoMode && history.canUndo
        }
        if item.action == #selector(redoCommand) {
            if let editor=window.firstResponder as? NSTextView {return editor.undoManager?.canRedo ?? false}
            return !busy && !demoMode && history.canRedo
        }
        return true
    }
    @objc func aboutApp() { show(L("Keepelix 0.1.0 beta 2", "Keepelix 0.1.0 בטא 2"), "© 2026 Daniel Siman Tov\n" + L("Contact: ","יצירת קשר: ") + "daniel.simisi@gmail.com\n\n" + L("Offline file review. MIT license. Not affiliated with WhatsApp or Meta. Undo is available for this app session; Finder Trash remains available afterward.","סקירת קבצים מקומית. רישיון MIT. ללא שיוך ל־WhatsApp או Meta. שחזור באפליקציה זמין במהלך ההפעלה הנוכחית; הפח של Finder נשאר זמין לאחר מכן.")) }
    func show(_ title: String, _ detail: String) { let a=NSAlert();a.messageText=title;a.informativeText=detail;a.runModal() }
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
    @objc func chooseLocation(_ sender:NSButton) {
        guard !busy, let suggested=Self.presetURL(sender.tag,home:FileManager.default.homeDirectoryForCurrentUser) else { return }
        let candidate:URL
        if sender.tag == 0, let saved=preferences.string(forKey:"whatsAppMediaFolder") { candidate=URL(fileURLWithPath:saved,isDirectory:true) }
        else { candidate=suggested }
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
    @objc func rescanFolder() { if let root=root, !busy { startScan(root) } }
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
            if b.action == #selector(rescanFolder) { b.isEnabled = !busy && root != nil }
            if demoMode && (b.action == #selector(trashSelection) || b.action == #selector(undoTrash) || b.action == #selector(redoTrash)) { b.isEnabled=false }
            if b.action == #selector(resumeFolder) { b.isEnabled = !busy && preferences.string(forKey:"lastFolder") != nil }
        }; cancelButton?.isEnabled=busy
        [sizeFilter,kindFilter,mode,groupPicker,agePicker,sortPicker].forEach{$0.isEnabled = !busy};search.isEnabled = !busy
        undoButton?.isEnabled = !busy && !demoMode && history.canUndo
        redoButton?.isEnabled = !busy && !demoMode && history.canRedo
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
        do { activateRoot(try FileSafety.root(url)) } catch { show("Cannot scan",error.localizedDescription);return }
        let selectedRoot=root!;preferences.set(selectedRoot.path,forKey:"lastFolder");folderLabel.stringValue=selectedRoot.path
        primary.previewItem=nil;comparison.previewItem=nil;files=[];exact=[];similar=[];guards=[:];mode.selectItem(at:0);modeChanged()
        token=CancellationToken();let jobToken=token;setBusy(true);status.stringValue=L("Scanning file metadata…","סורק שמות וגדלים…")
        work.async {
            do {
                let result=try Scanner.scan(root:selectedRoot,token:jobToken){count in DispatchQueue.main.async{self.status.stringValue=L("Scanning: ","נסרקו: ")+String(count)}}
                DispatchQueue.main.async {
                    self.files=result.files;self.setBusy(false);self.applyFilters()
                    self.status.stringValue="\(result.files.count) files · \(result.skipped) skipped" + (result.cancelled ? " · Cancelled (partial results)" : "")
                    if let last=self.preferences.string(forKey:"lastFile"),let i=self.shown.firstIndex(where:{$0.id==last}) {self.table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);self.table.scrollRowToVisible(i)}
                }
            } catch {DispatchQueue.main.async{self.setBusy(false);self.show("Scan failed",error.localizedDescription)}}
        }
    }
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
        let candidates=mode.indexOfSelectedItem == 3 ? ReviewQuery.older(files,than:cutoff) : files
        shown=candidates.filter { f in
            f.allocatedBytes>=threshold[max(0,sizeFilter.indexOfSelectedItem)] && (query.isEmpty || f.url.path.lowercased().contains(query)) &&
            (kindFilter.indexOfSelectedItem==0 || f.kind == FileKind.allCases[kindFilter.indexOfSelectedItem-1]) && (members==nil || members!.contains(f.id))
        }
        shown=ReviewQuery.sorted(shown,by:ReviewSort(rawValue:sortPicker.indexOfSelectedItem) ?? .largest)
        table.reloadData();table.selectRowIndexes(IndexSet(shown.indices.filter{old.contains(shown[$0].id)}),byExtendingSelection:false)
        updateSelection()
    }
    @objc func showOlderFiles() { guard !busy,root != nil else{return};mode.selectItem(at:3);modeChanged() }
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
        let icon=NSImageView(image:NSImage(systemSymbolName:symbols[f.kind] ?? "doc",accessibilityDescription:nil)!);icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant:18).isActive=true;icon.heightAnchor.constraint(equalToConstant:18).isActive=true
        let cell=NSStackView(views:[icon,v]);cell.spacing=9;cell.toolTip=f.url.path;return cell
    }
    func tableViewSelectionDidChange(_ notification:Notification){updateSelection()}
    func updateSelection(){
        let chosen=selectedFiles;selectionLabel.stringValue="\(chosen.count) / \(shown.count) " + L("selected","נבחרו") + " · " + bytes(chosen.reduce(0){$0+$1.allocatedBytes})
        emptyList?.isHidden = !shown.isEmpty
        emptyListTitle?.stringValue = root == nil ? L("Start somewhere simple","מתחילים בתיקייה אחת") : L("No matching files","אין קבצים מתאימים")
        emptyListDetail?.stringValue = root == nil ? L("Choose a location from the sidebar","בחר מיקום מהסרגל הצדדי") : L("Try another filter or location","נסה מסנן אחר או מיקום אחר")
        if let f=chosen.first{preferences.set(f.id,forKey:"lastFile")};updatePreview();updateEnabled()
    }
    @objc func selectAllCommand(){
        if let text = window.firstResponder as? NSTextView { text.selectAll(nil) } else { selectAllFiles() }
    }
    @objc func selectAllFiles(){
        guard !busy else{return};guards=[:];table.selectAll(nil);updateSelection()
    }
    @objc func deselect(){guard !busy else{return};guards=[:];table.deselectAll(nil);updateSelection()}
    @objc func nextFile(){guard !busy,!shown.isEmpty else{return};let i=min(max(table.selectedRow+1,0),shown.count-1);table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false);table.scrollRowToVisible(i);window.makeFirstResponder(table)}
    @objc func togglePreview(){guard !busy else{return};previewOpen.toggle();updatePreview();window.makeFirstResponder(table)}
    func updatePreview(){
        primary?.previewItem=nil;comparison?.previewItem=nil
        previewPlaceholder?.isHidden = false;primary?.isHidden = true
        guard !busy,previewOpen,let f=selectedFiles.first,let root=root,(try? FileSafety.validate(f,root:root)) != nil else{return}
        previewPlaceholder?.isHidden = true;primary.isHidden = false
        primary.previewItem=f.url as NSURL
        if (mode.indexOfSelectedItem == 1 || mode.indexOfSelectedItem == 2), let group=currentGroups.first(where:{$0.members.contains(where:{$0.id==f.id})}),let other=(mode.indexOfSelectedItem == 2 && f.id != group.anchor.id ? group.anchor : group.members.first(where:{$0.id != f.id})),(try? FileSafety.validate(other,root:root)) != nil{comparison.previewItem=other.url as NSURL}
    }
    @objc func reveal(){guard !busy,contextRow>=0,contextRow<shown.count,let root=root else{return};let f=shown[contextRow];do{try FileSafety.validate(f,root:root);NSWorkspace.shared.activateFileViewerSelecting([f.url])}catch{show("File unavailable",error.localizedDescription)}}
    @objc func findExactDuplicates(){runAnalysis(similar:false)}
    @objc func findSimilarImages(){
        guard !busy,root != nil else{return};let a=NSAlert();a.messageText=L("Compare images?","להשוות תמונות?");a.informativeText=L("Local comparison. Similarity is a suggestion; nothing is selected for deletion.","השוואה מקומית. דמיון הוא הצעה לבדיקה; לא תיבחר מחיקה אוטומטית.");a.addButton(withTitle:L("Compare","השווה"));a.addButton(withTitle:L("Cancel","בטל"));if a.runModal() == .alertFirstButtonReturn{runAnalysis(similar:true)}
    }
    func runAnalysis(similar:Bool){
        guard !busy,let root=root,!files.isEmpty else{return}
        token=CancellationToken();let jobToken=token;let source=files;setBusy(true);primary.previewItem=nil;comparison.previewItem=nil
        work.async{
            do{
                let progress:(Int,Int)->Void={i,total in if i%25==0 || i==total{DispatchQueue.main.async{self.status.stringValue="\(i) / \(total)"}}}
                let result=try similar ? SimilarImages.find(source,root:root,token:jobToken,progress:progress) : ExactDuplicates.find(source,root:root,token:jobToken,progress:progress)
                DispatchQueue.main.async{
                    if similar{self.similar=result.groups}else{self.exact=result.groups}
                    self.setBusy(false);self.mode.selectItem(at:similar ? 2:1);self.sizeFilter.selectItem(at:0);self.kindFilter.selectItem(at:0);self.search.stringValue="";self.modeChanged()
                    self.status.stringValue="\(result.groups.count) groups · \(result.skipped) skipped" + (similar ? " · Review suggestions only" : " · SHA-256 exact copies")
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
        guard !busy,!demoMode,let root=root,!selectedFiles.isEmpty else{return}
        let chosen=selectedFiles
        if !preferences.bool(forKey:"skipTrashConfirmation") {
            let alert=makeTrashAlert(chosen)
            guard alert.runModal() == .alertFirstButtonReturn else{return}
            if alert.suppressionButton?.state == .on {preferences.set(true,forKey:"skipTrashConfirmation");confirmationMenuItem?.state = .off}
        }
        let keepers=guards;let row=table.selectedRow;setBusy(true);cancelButton.isEnabled=false;primary.previewItem=nil;comparison.previewItem=nil
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
        guard !busy,!demoMode,history.canUndo else{return};setBusy(true);cancelButton.isEnabled=false
        work.async {
            let result=self.history.undo(backend:self.trashBackend)
            DispatchQueue.main.async {
                self.setBusy(false);guard let result=result else{return}
                if let root=self.root {
                    for url in result.restored {
                        if let record=try? FileRecord(url:url),(try? FileSafety.validate(record,root:root)) != nil {
                            self.files.removeAll{$0.id == record.id};self.files.append(record)
                        }
                    }
                }
                self.exact=[];self.similar=[];self.mode.selectItem(at:0);self.modeChanged()
                self.status.stringValue="\(result.restored.count) " + L("restored","שוחזרו")
                if !result.failures.isEmpty {self.show(L("Some files could not be restored","חלק מהקבצים לא שוחזרו"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n"))}
                self.window.makeFirstResponder(self.table)
            }
        }
    }
    @objc func redoTrash(){
        guard !busy,!demoMode,history.canRedo else{return};let row=table.selectedRow;setBusy(true);cancelButton.isEnabled=false
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
            togglePreview();precondition(primary.previewItem != nil)
            nextFile();precondition(table.selectedRow == 1 && primary.previewItem != nil)
            togglePreview();precondition(primary.previewItem == nil)
            let oldURL=temp.appendingPathComponent("old-sample.txt")
            try Data("Synthetic old file".utf8).write(to:oldURL)
            try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:946684800)],ofItemAtPath:oldURL.path)
            files.append(try FileRecord(url:oldURL));showOlderFiles()
            precondition(shown.count == 1 && shown[0].url == oldURL && selectedFiles.isEmpty)
            mode.selectItem(at:0);modeChanged();sortPicker.selectItem(at:ReviewSort.oldest.rawValue);changeSort()
            precondition(shown.first?.url == oldURL)
            table.sortDescriptors=[NSSortDescriptor(key:"modified",ascending:false)]
            precondition(shown.last?.url == oldURL)
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
            table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
            let target=selectedFiles[0].url
            func key(_ code:UInt16,_ flags:NSEvent.ModifierFlags=[],_ repeated:Bool=false) {
                let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:repeated,keyCode:code)!
                table.keyDown(with:event)
                let deadline=Date().addingTimeInterval(5)
                while busy && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
                precondition(!busy,"Synthetic keyboard operation timed out")
            }
            key(51);precondition(!FileManager.default.fileExists(atPath:target.path) && history.canUndo)
            let count=files.count;key(51,[],true);precondition(files.count == count,"Held Delete must not trash the next file")
            key(6,[.command]);precondition(FileManager.default.fileExists(atPath:target.path) && history.canRedo)
            key(6,[.command,.shift]);precondition(!FileManager.default.fileExists(atPath:target.path) && history.canUndo)
            key(6,[.command]);precondition(FileManager.default.fileExists(atPath:target.path))
            let savedRoot=root!;activateRoot(temp.appendingPathComponent("other"));precondition(!history.canUndo && !history.canRedo);activateRoot(savedRoot);precondition(history.canRedo)
            toggleTrashConfirmation(confirmationMenuItem!);precondition(!preferences.bool(forKey:"skipTrashConfirmation"))
            print("UI smoke: selection, old-file sorting, preview, confirmation preference, Delete, Undo, Redo and held-key protection passed. No real files changed; no windows shown.")
            cleanup();fflush(stdout);exit(0)
        } catch { fputs("UI smoke failed: \(error)\n",stderr);cleanup();exit(1) }
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { applicationShouldTerminate(NSApplication.shared) == .terminateNow }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{
        if busy && !(token.isCancelled && cancelButton.isEnabled){show(L("Operation in progress","פעולה עדיין מתבצעת"),L("Cancel the scan and wait, or let the Trash operation finish before quitting.","בטל את הסריקה והמתן, או אפשר להעברה לפח להסתיים לפני הסגירה."));return .terminateCancel};return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
let app=NSApplication.shared;app.setActivationPolicy((ProcessInfo.processInfo.arguments.contains("--smoke-test") || ProcessInfo.processInfo.arguments.contains("--launch-check")) ? .prohibited : .regular)
let controller=AppController();app.delegate=controller;app.run()
