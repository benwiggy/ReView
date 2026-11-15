import AppKit
import Quartz

/// Fills a menu with the Quartz filters installed on this Mac, each time it opens.
/// Used for both the Page menu's "Quartz Filter" submenu and the toolbar button.
final class QuartzFilterMenuDelegate: NSObject, NSMenuDelegate {

    static let shared = QuartzFilterMenuDelegate()   // NSMenu.delegate is weak, so keep it alive here

    static func makeMenu(title: String = "Quartz Filter") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.delegate = shared
        return menu
    }

    /// Every filter Quartz knows about (system, /Library and ~/Library), via QuartzFilterManager.
    static func installedFilters() -> [QuartzFilter] {
        let all = (QuartzFilterManager.filters(inDomains: nil) as? [QuartzFilter]) ?? []
        return all.sorted {
            name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending
        }
    }

    static func name(of filter: QuartzFilter) -> String {
        let name: String? = filter.localizedName()
        return name ?? "Untitled Filter"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let filters = Self.installedFilters()
        if filters.isEmpty {
            let none = NSMenuItem(title: "No Filters Found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for filter in filters {
            let item = NSMenuItem(title: Self.name(of: filter),
                                  action: #selector(DocumentWindowController.applyQuartzFilter(_:)),
                                  keyEquivalent: "")
            item.representedObject = filter
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Choose Filter File…",
                                action: #selector(DocumentWindowController.chooseQuartzFilter(_:)),
                                keyEquivalent: ""))
    }
}
