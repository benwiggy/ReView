import AppKit
import PDFKit

/// Builds the main menu in code. Items whose target is nil are routed down the responder
/// chain to the front window's DocumentWindowController (or to NSDocument / AppKit itself).
/// Only here so `#selector` can produce the standard "undo:" / "redo:" action names,
/// which the responder chain delivers to the window's undo manager.
@objc private protocol MenuUndoActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}

enum MenuBuilder {

    // MARK: Page styles (shared by the View menu and the toolbar's View button)

    static func pageStyleTag(for mode: PDFDisplayMode) -> Int {
        switch mode {
        case .singlePage: return 0
        case .singlePageContinuous: return 1
        case .twoUp: return 2
        case .twoUpContinuous: return 3
        @unknown default: return 1
        }
    }

    static func pageMode(forTag tag: Int) -> PDFDisplayMode {
        switch tag {
        case 0: return .singlePage
        case 2: return .twoUp
        case 3: return .twoUpContinuous
        default: return .singlePageContinuous
        }
    }

    /// Fresh items each call: an NSMenuItem can only live in one menu.
    static func pageStyleItems() -> [NSMenuItem] {
        let action = #selector(DocumentWindowController.setPageStyle(_:))
        return [
            item("Single Page", action, "1", tag: 0),
            item("Single Page Continuous", action, "2", tag: 1),
            item("Two Pages", action, "3", tag: 2),
            item("Two Pages Continuous", action, "4", tag: 3),
            .separator(),
            item("First Page Is Cover", #selector(DocumentWindowController.toggleBook(_:)), "5"),
            item("Show Page Breaks", #selector(DocumentWindowController.togglePageBreaks(_:)), "6")
        ]
    }

    // MARK: Helpers

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        menuItem.tag = tag
        return menuItem
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        for entry in items { menu.addItem(entry) }
        let host = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        host.submenu = menu
        return host
    }

    private static func functionKey(_ code: Int) -> String {
        String(UnicodeScalar(UInt32(code))!)
    }

    private static let backspace = "\u{8}"

    // MARK: Main menu

    static func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        // App
        let app = submenu(appName, [
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")
        ])
        main.addItem(app)

        // File
        main.addItem(submenu("File", [
            item("New from Clipboard", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(NSDocument.save(_:)), "s"),
            item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))),
            item("Password Protection…", #selector(DocumentWindowController.showPasswordProtection(_:))),
            .separator(),
            item("Export as Images…", #selector(DocumentWindowController.exportImages(_:)), "e", [.command, .shift]),
            item("Split at Bookmarks…", #selector(DocumentWindowController.splitAtBookmarks(_:))),
            .separator(),
            item("Print…", #selector(NSDocument.printDocument(_:)), "p")
        ]))

        // Edit
        main.addItem(submenu("Edit", [
            item("Undo", #selector(MenuUndoActions.undo(_:)), "z"),
            item("Redo", #selector(MenuUndoActions.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Find…", #selector(DocumentWindowController.focusSearch(_:)), "f"),
            item("Find Next", #selector(DocumentWindowController.findNext(_:)), "g"),
            item("Find Previous", #selector(DocumentWindowController.findPrevious(_:)), "g", [.command, .shift])
        ]))

        // View
        let view = submenu("View", pageStyleItems() + [
            .separator(),
            item("Vertical Scrolling", #selector(DocumentWindowController.setDirection(_:)), "v", [.command, .shift], tag: 0),
            item("Horizontal Scrolling", #selector(DocumentWindowController.setDirection(_:)), "h", [.command, .shift], tag: 1),
            .separator(),
            item("Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+"),
            item("Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-"),
            item("Actual Size", #selector(DocumentWindowController.zoomActualSize(_:)), "0"),
            item("Zoom to Fit", #selector(DocumentWindowController.zoomToFit(_:)), "9"),
            item("Fit to Width", #selector(DocumentWindowController.zoomToFitWidth(_:))),
            item("Fit to Height", #selector(DocumentWindowController.zoomToFitHeight(_:))),
            .separator(),
            item("Save Current View as Default", #selector(DocumentWindowController.saveViewAsDefault(_:))),
            .separator(),
            item("Hide Sidebar", #selector(DocumentWindowController.toggleSidebarPanel(_:)), "s", [.command, .control]),
            item("Thumbnails", #selector(DocumentWindowController.showThumbnails(_:)), "1", [.command, .control]),
            item("Bookmarks", #selector(DocumentWindowController.showBookmarks(_:)), "2", [.command, .control]),
            .separator(),
            item("Show Inspector", #selector(AppDelegate.toggleInspector(_:)), "i"),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        ])
        main.addItem(view)

        // Go
        main.addItem(submenu("Go", [
            item("First Page", #selector(DocumentWindowController.goFirst(_:)), functionKey(NSUpArrowFunctionKey), [.command, .shift]),
            item("Previous Page", #selector(DocumentWindowController.goPrevious(_:)), functionKey(NSUpArrowFunctionKey)),
            item("Next Page", #selector(DocumentWindowController.goNext(_:)), functionKey(NSDownArrowFunctionKey)),
            item("Last Page", #selector(DocumentWindowController.goLast(_:)), functionKey(NSDownArrowFunctionKey), [.command, .shift]),
            .separator(),
            item("Go to Page…", #selector(DocumentWindowController.goToPage(_:)), "g", [.command, .option])
        ]))
        
        // Pages
        main.addItem(submenu("Pages", [
            item("Rotate Left", #selector(DocumentWindowController.rotateLeft(_:)), "l"),
            item("Rotate Right", #selector(DocumentWindowController.rotateRight(_:)), "r"),
            item("Add Blank Page", #selector(DocumentWindowController.addBlankPage(_:)), "b", [.command, .shift]),
            item("Insert Pages from File…", #selector(DocumentWindowController.insertPagesFromFile(_:))),
            item("Duplicate Pages", #selector(DocumentWindowController.duplicatePages(_:))),
            item("Delete Pages", #selector(DocumentWindowController.deletePages(_:)), backspace),
            .separator(),
            {
                let host = NSMenuItem(title: "Quartz Filter", action: nil, keyEquivalent: "")
                host.submenu = QuartzFilterMenuDelegate.makeMenu()
                return host
            }()
        ]))

        // Bookmarks
        let option: NSEvent.ModifierFlags = [.command, .option]
        main.addItem(submenu("Bookmarks", [
            item("Add Bookmark", #selector(DocumentWindowController.addBookmark(_:)), "d"),
            item("Add Sub-bookmark", #selector(DocumentWindowController.addSubBookmark(_:)), "d", option),
            item("Rename Bookmark…", #selector(DocumentWindowController.renameBookmark(_:)), "r", option),
            item("Set Destination to Current Page", #selector(DocumentWindowController.setBookmarkDestination(_:)), "d", [.command, .shift]),
            .separator(),
            item("Outdent", #selector(DocumentWindowController.outdentBookmark(_:)), functionKey(NSLeftArrowFunctionKey), option),
            item("Indent", #selector(DocumentWindowController.indentBookmark(_:)), functionKey(NSRightArrowFunctionKey), option),
            item("Move Up", #selector(DocumentWindowController.moveBookmarkUp(_:)), functionKey(NSUpArrowFunctionKey), option),
            item("Move Down", #selector(DocumentWindowController.moveBookmarkDown(_:)), functionKey(NSDownArrowFunctionKey), option),
            .separator(),
            item("Delete Bookmark", #selector(DocumentWindowController.deleteBookmark(_:)), backspace, option)
        ]))

        // Window
        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu

        return main
    }
}
