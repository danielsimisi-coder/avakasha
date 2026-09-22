import Cocoa
import Quartz
import FileTriageCore

func L(_ en: String, _ he: String) -> String { (Locale.preferredLanguages.first ?? "en").hasPrefix("he") ? he : en }
func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

final class FileTable: NSTableView {
    weak var owner: AppController?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { owner?.togglePreview(); return }
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 51 { owner?.trashSelection(); return }
            if event.keyCode == 0 { owner?.selectAllFiles(); return }
            if event.keyCode == 6 { owner?.undoTrash(); return }
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

final class AppController: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let smokeMode = ProcessInfo.processInfo.arguments.contains("--smoke-test")
    let preferences = UserDefaults(suiteName: ProcessInfo.processInfo.arguments.contains("--smoke-test") ? "FileTriage.SyntheticSmoke" : "io.github.danielsimisi-coder.FileTriage")!
    var window: NSWindow!
    let table = FileTable()
    let search = NSSearchField()
    let sizeFilter = NSPopUpButton()
    let kindFilter = NSPopUpButton()
    let mode = NSPopUpButton()
    let groupPicker = NSPopUpButton()
    let status = NSTextField(labelWithString: "")
    let selectionLabel = NSTextField(labelWithString: "")
    let folderLabel = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    var primary: QLPreviewView!
    var comparison: QLPreviewView!
    var buttons: [NSButton] = []
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
    let work = DispatchQueue(label: "FileTriage.background", qos: .userInitiated)
    var busy = false
    var previewOpen = false
    var contextRow = -1
    var undoBatches: [(URL, [RestoreTicket])] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "FileTriage · 0.1.0 beta"; window.minSize = NSSize(width: 1040, height: 660); window.center()
        func button(_ en: String, _ he: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: L(en, he), target: self, action: action); buttons.append(b); return b
        }
        let choose = button("Choose folder…", "בחר תיקייה…", #selector(chooseFolder))
        let resume = button("Resume", "המשך מהמקום שעצרתי", #selector(resumeFolder))
        let rescan = button("Rescan", "סרוק שוב", #selector(rescanFolder))
        let findExact = button("Exact duplicates", "כפילויות זהות", #selector(findExactDuplicates))
        let findSimilar = button("Similar images…", "תמונות דומות…", #selector(findSimilarImages))
        cancelButton = NSButton(title: L("Cancel", "בטל סריקה"), target: self, action: #selector(cancelWork)); cancelButton.isEnabled = false
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let actions = NSStackView(views: [choose,resume,rescan,findExact,findSimilar,cancelButton,spinner]); actions.spacing = 8
        folderLabel.lineBreakMode = .byTruncatingMiddle
        search.placeholderString = L("Filter by file name or path", "חפש שם קובץ או מיקום"); search.delegate = self
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        sizeFilter.addItems(withTitles: [L("All sizes","כל הגדלים"), "> 10 MB", "> 100 MB", "> 1 GB"]); sizeFilter.selectItem(at: 1)
        kindFilter.addItem(withTitle: L("All types","כל הסוגים")); kindFilter.addItems(withTitles: FileKind.allCases.map(\.rawValue))
        mode.addItems(withTitles: [L("All files","כל הקבצים"), L("Exact duplicates","כפילויות זהות"), L("Similar images","תמונות דומות")])
        for popup in [sizeFilter,kindFilter] { popup.target = self; popup.action = #selector(applyFilters) }
        mode.target = self; mode.action = #selector(modeChanged)
        groupPicker.target = self; groupPicker.action = #selector(applyFilters)
        let filters = NSStackView(views: [search,sizeFilter,kindFilter,mode,groupPicker]); filters.spacing = 8
        let all = button("Select all", "בחר הכול", #selector(selectAllFiles))
        let none = button("Deselect", "בטל בחירה", #selector(deselect))
        extrasButton = button("Select extra copies", "בחר עותקים נוספים", #selector(selectExtras))
        let preview = button("Preview · Space", "צפה · רווח", #selector(togglePreview))
        let next = button("Keep & next ↓", "השאר והבא ↓", #selector(nextFile))
        let trash = button("Move selected to Trash…", "העבר בחירה לפח…", #selector(trashSelection))
        undoButton = button("Undo Trash · ⌘Z", "שחזר מהפח · ⌘Z", #selector(undoTrash))
        let review = NSStackView(views: [all,none,extrasButton,preview,next,trash,undoButton]); review.spacing = 8
        let hint = NSTextField(wrappingLabelWithString: L("⌘-click: add/remove · Shift-click: range · ⌘A: select filtered files · Right-click: Finder. FileTriage has no uploads; previews use macOS Quick Look.", "⌘ ולחיצה: הוספה/הסרה · Shift ולחיצה: רצף · ⌘A: כל הרשימה המסוננת · לחצן ימני: Finder. אין העלאה דרך FileTriage; התצוגה משתמשת ב־Quick Look."))
        let warning = NSTextField(wrappingLabelWithString: L("Trash only — never permanent deletion. Removing app-managed media can leave missing attachments. Similar images are suggestions, not confirmed duplicates. Disk space is released after you empty Trash yourself.", "העברה לפח בלבד. הסרת מדיה של אפליקציה עלולה להשאיר קבצים חסרים בשיחות. תמונות דומות הן הצעות לבדיקה. המקום יתפנה אחרי שתרוקן את הפח בעצמך."))
        warning.textColor = .secondaryLabelColor
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        table.frame = NSRect(x: 0, y: 0, width: 560, height: 480); table.autoresizingMask = [.width]
        table.owner = self; table.delegate = self; table.dataSource = self; table.allowsMultipleSelection = true; table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        for (id,title,width) in [("name",L("Name","שם"),310.0),("size",L("On disk","בדיסק"),100.0),("kind",L("Type","סוג"),85.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; table.addTableColumn(c)
        }
        scroll.documentView = table
        primary = QLPreviewView(frame: NSRect(x:0,y:0,width:330,height:460), style: .normal); primary.autostarts = false
        comparison = QLPreviewView(frame: NSRect(x:0,y:0,width:330,height:460), style: .normal); comparison.autostarts = false
        let previews = NSStackView(views: [primary,comparison]); previews.orientation = .horizontal; previews.distribution = .fillEqually
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin; split.addArrangedSubview(scroll); split.addArrangedSubview(previews)
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 440).isActive = true
        previews.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        let stack = NSStackView(views: [actions,folderLabel,filters,review,selectionLabel,hint,warning,status,split]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16), split.widthAnchor.constraint(equalTo: stack.widthAnchor), split.heightAnchor.constraint(greaterThanOrEqualToConstant: 280), hint.widthAnchor.constraint(equalTo: stack.widthAnchor), warning.widthAnchor.constraint(equalTo: stack.widthAnchor), folderLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        makeMenus(); modeChanged(); updateEnabled()
        status.stringValue = L("Choose a folder to start. No folder is scanned automatically.","בחר תיקייה כדי להתחיל. הסריקה אינה מתחילה אוטומטית.")
        if smokeMode { runSmokeTests(); return }
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(table); NSApp.activate(ignoringOtherApps: true)
    }
    func makeMenus() {
        let main = NSMenu(); let app = NSMenuItem(); main.addItem(app); let menu = NSMenu(); app.submenu = menu
        let about = NSMenuItem(title: L("About FileTriage", "אודות FileTriage"), action: #selector(aboutApp), keyEquivalent: ""); about.target = self; menu.addItem(about)
        menu.addItem(withTitle: L("Quit FileTriage","סגור FileTriage"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); edit.title = "Edit"; main.addItem(edit); edit.submenu = NSMenu(title:"Edit")
        for (title,selector,key) in [(L("Select all","בחר הכול"),#selector(selectAllCommand),"a"),(L("Undo Trash","שחזר מהפח"),#selector(undoTrash),"z")] {
            let item = NSMenuItem(title:title,action:selector,keyEquivalent:key); item.target=self; edit.submenu!.addItem(item)
        }
        // Standard text editing remains available in the search field.
        edit.submenu!.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        edit.submenu!.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        NSApp.mainMenu=main
    }
    @objc func aboutApp() { show(L("FileTriage 0.1.0 beta", "FileTriage 0.1.0 בטא"), "© 2026 Daniel Siman Tov\n" + L("Contact: ","יצירת קשר: ") + "daniel.simisi@gmail.com\n\n" + L("Offline file review. MIT license. Not affiliated with WhatsApp or Meta. Undo is available for this app session; Finder Trash remains available afterward.","סקירת קבצים מקומית. רישיון MIT. ללא שיוך ל־WhatsApp או Meta. שחזור באפליקציה זמין במהלך ההפעלה הנוכחית; הפח של Finder נשאר זמין לאחר מכן.")) }
    func show(_ title: String, _ detail: String) { let a=NSAlert();a.messageText=title;a.informativeText=detail;a.runModal() }
    @objc func chooseFolder() {
        guard !busy else { return }; let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.allowsMultipleSelection=false
        p.message=L("Choose only the folder you want to review. No files are uploaded.","בחר רק את התיקייה שתרצה לבדוק. שום קובץ לא מועלה לרשת.")
        if p.runModal() == .OK, let u=p.url { startScan(u) }
    }
    @objc func resumeFolder() {
        guard !busy else { return }
        if let path=preferences.string(forKey:"lastFolder") { startScan(URL(fileURLWithPath:path)) } else { chooseFolder() }
    }
    @objc func rescanFolder() { if let root=root, !busy { startScan(root) } }
    @objc func cancelWork() { token.cancel();status.stringValue=L("Cancelling…","מבטל…") }
    func setBusy(_ value: Bool) { busy=value;updateEnabled();if value{spinner.startAnimation(nil)}else{spinner.stopAnimation(nil)} }
    func updateEnabled() {
        buttons.forEach{$0.isEnabled = !busy}; cancelButton?.isEnabled=busy
        [sizeFilter,kindFilter,mode,groupPicker].forEach{$0.isEnabled = !busy};search.isEnabled = !busy
        undoButton?.isEnabled = !busy && !undoBatches.isEmpty
        extrasButton?.isEnabled = !busy && mode.indexOfSelectedItem == 1 && !exact.isEmpty
    }
    func startScan(_ url: URL) {
        guard !busy else{return}
        do { root=try FileSafety.root(url) } catch { show("Cannot scan",error.localizedDescription);return }
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
    var currentGroups: [DuplicateGroup] {mode.indexOfSelectedItem == 1 ? exact : similar}
    @objc func modeChanged() {
        groupPicker.removeAllItems();groupPicker.addItem(withTitle:L("All groups","כל הקבוצות"))
        for (i,g) in currentGroups.enumerated(){groupPicker.addItem(withTitle:"\(i+1) · \(g.members.count) files")}
        groupPicker.isHidden=mode.indexOfSelectedItem==0;comparison.isHidden=mode.indexOfSelectedItem==0
        guards=[:];applyFilters();updateEnabled()
    }
    @objc func applyFilters() {
        let old=Set(selectedFiles.map(\.id));let threshold:[Int64]=[0,10_000_000,100_000_000,1_000_000_000]
        let groupIndex=groupPicker.indexOfSelectedItem-1
        let groups=currentGroups
        let members:Set<String>? = mode.indexOfSelectedItem==0 ? nil : Set((groupIndex>=0 && groupIndex<groups.count ? groups[groupIndex].members : groups.flatMap(\.members)).map(\.id))
        let query=search.stringValue.lowercased()
        shown=files.filter { f in
            f.allocatedBytes>=threshold[max(0,sizeFilter.indexOfSelectedItem)] && (query.isEmpty || f.url.path.lowercased().contains(query)) &&
            (kindFilter.indexOfSelectedItem==0 || f.kind == FileKind.allCases[kindFilter.indexOfSelectedItem-1]) && (members==nil || members!.contains(f.id))
        }.sorted{$0.allocatedBytes == $1.allocatedBytes ? $0.id<$1.id : $0.allocatedBytes>$1.allocatedBytes}
        table.reloadData();table.selectRowIndexes(IndexSet(shown.indices.filter{old.contains(shown[$0].id)}),byExtendingSelection:false)
        updateSelection()
    }
    func controlTextDidChange(_ obj: Notification){applyFilters()}
    var selectedFiles:[FileRecord]{table.selectedRowIndexes.compactMap{$0<shown.count ? shown[$0]:nil}}
    func numberOfRows(in tableView:NSTableView)->Int{shown.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        let f=shown[row];let text:String
        switch tableColumn?.identifier.rawValue{case "size":text=bytes(f.allocatedBytes);case "kind":text=f.kind.rawValue;default:text=f.name}
        let v=NSTextField(labelWithString:text);v.lineBreakMode = .byTruncatingMiddle;v.toolTip=f.url.path;return v
    }
    func tableViewSelectionDidChange(_ notification:Notification){updateSelection()}
    func updateSelection(){
        let chosen=selectedFiles;selectionLabel.stringValue="\(chosen.count) / \(shown.count) " + L("selected","נבחרו") + " · " + bytes(chosen.reduce(0){$0+$1.allocatedBytes})
        if let f=chosen.first{preferences.set(f.id,forKey:"lastFile")};updatePreview()
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
        guard !busy,previewOpen,let f=selectedFiles.first,let root=root,(try? FileSafety.validate(f,root:root)) != nil else{return}
        primary.previewItem=f.url as NSURL
        if mode.indexOfSelectedItem != 0, let group=currentGroups.first(where:{$0.members.contains(where:{$0.id==f.id})}),let other=(mode.indexOfSelectedItem == 2 && f.id != group.anchor.id ? group.anchor : group.members.first(where:{$0.id != f.id})),(try? FileSafety.validate(other,root:root)) != nil{comparison.previewItem=other.url as NSURL}
    }
    @objc func reveal(){guard !busy,contextRow>=0,contextRow<shown.count,let root=root else{return};let f=shown[contextRow];do{try FileSafety.validate(f,root:root);NSWorkspace.shared.activateFileViewerSelecting([f.url])}catch{show("File unavailable",error.localizedDescription)}}
    @objc func findExactDuplicates(){runAnalysis(similar:false)}
    @objc func findSimilarImages(){
        guard !busy,root != nil else{return};let a=NSAlert();a.messageText=L("Compare images on this Mac?","להשוות תמונות במחשב?");a.informativeText=L("This reads image contents locally. Nothing is uploaded. Similarity can be wrong; no files are automatically selected or deleted.","הפעולה קוראת תמונות מקומית בלבד. דבר לא מועלה לרשת. דמיון אינו הוכחה לכפילות; שום קובץ לא יסומן או יימחק אוטומטית.");a.addButton(withTitle:L("Compare","השווה"));a.addButton(withTitle:L("Cancel","בטל"));if a.runModal() == .alertFirstButtonReturn{runAnalysis(similar:true)}
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
    @objc func trashSelection(){
        guard !busy,let root=root,!selectedFiles.isEmpty else{return};let chosen=selectedFiles
        let a=NSAlert();a.alertStyle = .warning;a.messageText=L("Move selected files to Trash?","להעביר את הבחירה לפח?")
        a.informativeText="\(chosen.count) files · \(bytes(chosen.reduce(0){$0+$1.allocatedBytes}))\n"+chosen.prefix(5).map{ $0.url.path }.joined(separator:"\n") + (chosen.count > 5 ? "\n+ \(chosen.count-5) more (all paths listed below)" : "")+"\n\n"+L("No permanent deletion. App-managed media may become unavailable in its original app. You can undo during this session or restore from Finder Trash.","אין מחיקה לצמיתות. מדיה של אפליקציה עלולה להפסיק להיפתח בה. אפשר לשחזר במהלך ההפעלה הנוכחית או מהפח ב־Finder.")
        let list = NSTextView(frame:NSRect(x:0,y:0,width:650,height:180));list.isEditable=false;list.string=chosen.map{ $0.url.path }.joined(separator:"\n")
        let scroll=NSScrollView(frame:list.frame);scroll.hasVerticalScroller=true;scroll.documentView=list;a.accessoryView=scroll
        a.addButton(withTitle:L("Move to Trash","העבר לפח"));a.addButton(withTitle:L("Cancel","בטל"));guard a.runModal() == .alertFirstButtonReturn else{return}
        let keepers=guards;let row=table.selectedRow;setBusy(true);cancelButton.isEnabled=false;primary.previewItem=nil;comparison.previewItem=nil
        work.async{
            let result=TrashService.move(chosen,root:root,keepers:keepers)
            DispatchQueue.main.async{
                if !result.tickets.isEmpty{self.undoBatches.append((root,result.tickets))}
                let moved=Set(result.tickets.map{$0.original.path});self.files.removeAll{moved.contains($0.id)};self.exact=[];self.similar=[];self.guards=[:];self.mode.selectItem(at:0);self.setBusy(false);self.modeChanged()
                if !self.shown.isEmpty{let next=min(max(row,0),self.shown.count-1);self.table.selectRowIndexes(IndexSet(integer:next),byExtendingSelection:false);self.table.scrollRowToVisible(next)}
                self.status.stringValue="\(result.tickets.count) moved to Trash · \(result.failures.count) not moved"
                if !result.failures.isEmpty{self.show(L("Some files were not moved","חלק מהקבצים לא הועברו"),result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n"))}
                self.window.makeFirstResponder(self.table)
            }
        }
    }
    @objc func undoTrash(){
        guard !busy,let batch=undoBatches.popLast() else{return};setBusy(true);cancelButton.isEnabled=false
        work.async{
            let result=TrashService.undo(batch.1,root:batch.0)
            DispatchQueue.main.async{
                if !result.pending.isEmpty{self.undoBatches.append((batch.0,result.pending))};self.setBusy(false)
                self.show(L("Restore result","תוצאות השחזור"),"\(result.restored.count) restored · \(result.pending.count) not restored\n"+result.failures.map{$0.url.lastPathComponent+": "+$0.message}.joined(separator:"\n"))
                self.rescanFolder()
            }
        }
    }
    func runSmokeTests() {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("filetriage-smoke-" + UUID().uuidString)
        func cleanup() { try? FileManager.default.removeItem(at: temp); preferences.removePersistentDomain(forName:"FileTriage.SyntheticSmoke") }
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            for (name, text) in [("coast-notes.txt", "Synthetic duplicate fixture"), ("coast-notes-copy.txt", "Synthetic duplicate fixture"), ("readme.txt", "Unrelated synthetic example")] {
                try Data(text.utf8).write(to: temp.appendingPathComponent(name))
            }
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
            precondition(undoBatches.isEmpty)
            print("UI smoke: multi-select, filtered Select All, no implicit selection, keeper selection, context menu, preview, navigation passed. No real files changed; no windows shown.")
            cleanup();fflush(stdout);exit(0)
        } catch { fputs("UI smoke failed: \(error)\n",stderr);cleanup();exit(1) }
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { applicationShouldTerminate(NSApplication.shared) == .terminateNow }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply{
        if busy && !(token.isCancelled && cancelButton.isEnabled){show(L("Operation in progress","פעולה עדיין מתבצעת"),L("Cancel the scan and wait, or let the Trash operation finish before quitting.","בטל את הסריקה והמתן, או אפשר להעברה לפח להסתיים לפני הסגירה."));return .terminateCancel};return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}
let app=NSApplication.shared;app.setActivationPolicy(ProcessInfo.processInfo.arguments.contains("--smoke-test") ? .prohibited : .regular)
let controller=AppController();app.delegate=controller;app.run()
