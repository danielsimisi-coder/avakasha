import Cocoa
import AvakashaCore

/// The optional menu bar item: free space on the startup disk at a glance, what can go (as Free up space last measured it),
/// and the weekly check. It reads volume attributes only; it never measures folders by itself.
final class MenuBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?
    /// What can go, as the app last knew it: "Can go to Trash now: 7.9 GB", or the weekly check's total with its date.
    var canGoLine: () -> String? = { nil }
    /// "Floor 40 GB · reached in about 23 days", when a floor is set.
    var guardLine: () -> String? = { nil }
    var weeklyOn: () -> Bool = { false }
    var loginOn: () -> Bool = { false }
    var onOpen: (() -> Void)?
    var onCheck: (() -> Void)?
    var onToggleWeekly: (() -> Void)?
    var onToggleLogin: (() -> Void)?
    var isShown: Bool { item != nil }

    func setShown(_ on: Bool) {
        if on, item == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            status.button?.image = symbol("internaldrive", 13); status.button?.imagePosition = .imageLeading
            status.button?.setAccessibilityLabel(L("Avakasha: free space", "Avakasha: מקום פנוי"))
            let menu = NSMenu(); menu.delegate = self; status.menu = menu
            item = status; refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.refresh() }
        } else if !on, let status = item {
            NSStatusBar.system.removeStatusItem(status); item = nil; timer?.invalidate(); timer = nil
        }
    }
    /// The title is the startup disk's free space, the number people check most.
    func refresh() {
        guard let startup = Volumes.mounted().first(where: \.isStartup) else { item?.button?.title = ""; return }
        item?.button?.title = " " + bytes(startup.available)
        item?.button?.toolTip = startup.name + ": " + bytes(startup.available) + L(" free", " פנויים")
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh(); menu.removeAllItems()
        for volume in Volumes.mounted() {
            let line = NSMenuItem(title: volume.name + " · " + bytes(volume.available) + L(" free of ", " פנויים מתוך ") + bytes(volume.total), action: nil, keyEquivalent: ""); line.isEnabled = false; menu.addItem(line)
        }
        if let text = guardLine() { let line = NSMenuItem(title: text, action: nil, keyEquivalent: ""); line.isEnabled = false; menu.addItem(line) }
        menu.addItem(.separator())
        if let text = canGoLine() { let line = NSMenuItem(title: text, action: nil, keyEquivalent: ""); line.isEnabled = false; menu.addItem(line) }
        add(menu, L("Check What Can Go…", "בדוק מה אפשר לפנות…"), #selector(check))
        add(menu, L("Open Avakasha", "פתח את Avakasha"), #selector(open))
        menu.addItem(.separator())
        add(menu, L("Weekly Check & Low-Space Alerts", "בדיקה שבועית והתראה על מקום נמוך"), #selector(toggleWeekly)).state = weeklyOn() ? .on : .off
        add(menu, L("Open at Login", "פתיחה בהתחברות"), #selector(toggleLogin)).state = loginOn() ? .on : .off
        menu.addItem(.separator())
        add(menu, L("Quit Avakasha", "צא מ־Avakasha"), #selector(quit))
    }
    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry); return entry
    }
    @objc private func open() { onOpen?() }
    @objc private func check() { onCheck?() }
    @objc private func toggleWeekly() { onToggleWeekly?() }
    @objc private func toggleLogin() { onToggleLogin?() }
    /// Brought forward first, so a "still working" or "restores waiting" question is not hidden behind other apps.
    @objc private func quit() { NSApp.activate(ignoringOtherApps: true); NSApp.terminate(nil) }
}
