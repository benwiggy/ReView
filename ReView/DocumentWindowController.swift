import AppKit
import Combine
import SwiftUI
import PDFKit
import Quartz
import UniformTypeIdentifiers

/// Hosts the SwiftUI content, owns the toolbar, and is the target of every menu and toolbar
/// action (they are sent down the responder chain with a nil target).
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation {

    let store: DocumentStore
    private var searchItem: NSSearchToolbarItem?
    private var imageExporter: ImageExporter?
    private var zoomPopup: NSPopUpButton?
    private var bookmarkSplitter: BookmarkSplitter?
    private let sidebarItem: NSSplitViewItem
    private var cancellables = Set<AnyCancellable>()

    private enum ToolbarID {
        static let sidebar = NSToolbarItem.Identifier("sidebar")
        static let style = NSToolbarItem.Identifier("style")
        static let zoom = NSToolbarItem.Identifier("zoom")
        static let rotateLeft = NSToolbarItem.Identifier("rotateLeft")
        static let rotateRight = NSToolbarItem.Identifier("rotateRight")
        static let addBlank = NSToolbarItem.Identifier("addBlank")
        static let delete = NSToolbarItem.Identifier("delete")
        static let filter = NSToolbarItem.Identifier("filter")
        static let bookmark = NSToolbarItem.Identifier("bookmark")
        static let search = NSToolbarItem.Identifier("search")
    }

    // MARK: Setup

    init(store: DocumentStore) {
        self.store = store

        // Sidebar + PDF live in a real split view, so AppKit remembers the sidebar's width
        // when it is hidden and shown again.
        let sidebarHost = NSHostingController(rootView: SidebarView(store: store))
        let contentHost = NSHostingController(rootView: PDFAreaView(store: store))
        sidebarHost.sizingOptions = []   // the window, not the SwiftUI content, decides the size
        contentHost.sizingOptions = []

        let sidebar = NSSplitViewItem(viewController: sidebarHost)
        sidebar.canCollapse = true
        sidebar.minimumThickness = 170
        sidebar.maximumThickness = 420
        sidebar.holdingPriority = NSLayoutConstraint.Priority(260)   // keep its width when the window resizes
        sidebar.isCollapsed = !store.showSidebar
        let content = NSSplitViewItem(viewController: contentHost)
        content.minimumThickness = 320

        let split = SidebarSplitViewController(store: store, initialSidebarWidth: store.sidebarWidth)
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(content)
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        sidebarItem = sidebar

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // As big as the screen comfortably allows: more of the page shows, and two-page styles fit.
        if let visible = NSScreen.main?.visibleFrame {
            let wanted = NSRect(x: 0, y: 0, width: min(1500, visible.width * 0.85), height: visible.height * 0.9)
            window.setContentSize(window.contentRect(forFrameRect: wanted).size)
        } else {
            window.setContentSize(NSSize(width: 1080, height: 780))
        }
        window.minSize = NSSize(width: 640, height: 400)
        window.toolbarStyle = .unified

        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self

        // Show/hide the sidebar whenever the store's flag changes (menu, toolbar, shortcut).
        store.$showSidebar
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] show in
                guard let item = self?.sidebarItem, item.isCollapsed == show else { return }
                item.animator().isCollapsed = !show
            }
            .store(in: &cancellables)

        // Under the file name: "Page 3 of 120", with a reminder if the saved file will need a password.
        Publishers.CombineLatest3(store.$currentPage, store.$pageRevision, store.$securityRevision)
            .sink { [weak self] page, _, _ in
                guard let self else { return }
                let count = self.store.pageCount
                var text = "Page \(min(page, max(count - 1, 0)) + 1) of \(count)"
                if self.store.isProtected { text += " · Password protected" }
                self.window?.subtitle = text
            }
            .store(in: &cancellables)

        // The toolbar's zoom reads the current zoom; it changes as you zoom, resize, or move to another screen.
        store.$zoomPercent
            .sink { [weak self] percent in
                self?.zoomPopup?.menu?.items.first?.title = "\(percent)%"
                self?.zoomPopup?.synchronizeTitleAndSelectedItem()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: window)
            .sink { [weak store] _ in store?.refreshZoom() }
            .store(in: &cancellables)
        
        let toolbar = NSToolbar(identifier: "ReViewToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Edit > Undo/Redo use the document's undo manager.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.sidebar, ToolbarID.zoom, .space,
         ToolbarID.rotateLeft, ToolbarID.rotateRight, ToolbarID.addBlank, ToolbarID.delete, .space,
         ToolbarID.bookmark, ToolbarID.filter, .flexibleSpace, ToolbarID.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case ToolbarID.sidebar:
            return button(identifier, "Sidebar", "sidebar.left", #selector(toggleSidebarPanel(_:)), "Show or Hide Sidebar (⌃⌘S)")
        case ToolbarID.rotateLeft:
            return button(identifier, "Rotate Left", "rotate.left", #selector(rotateLeft(_:)), "Rotate Left (⌘L)")
        case ToolbarID.rotateRight:
            return button(identifier, "Rotate Right", "rotate.right", #selector(rotateRight(_:)), "Rotate Right (⌘R)")
        case ToolbarID.addBlank:
            return button(identifier, "Add Blank Page", "doc.badge.plus", #selector(addBlankPage(_:)), "Add Blank Page Before Selection (⇧⌘B)")
        case ToolbarID.delete:
            return button(identifier, "Delete Pages", "trash", #selector(deletePages(_:)), "Delete Selected Pages (⌘⌫)")
        case ToolbarID.bookmark:
            return button(identifier, "Add Bookmark", "bookmark", #selector(addBookmark(_:)), "Bookmark This Page (⌘D)")
        case ToolbarID.zoom:
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 84, height: 28), pullsDown: true)
            // In a pull-down, the first item is the title: it always shows the current zoom.
            popup.menu?.addItem(NSMenuItem(title: "\(store.zoomPercent)%", action: nil, keyEquivalent: ""))
            for (title, tag) in [("Fit Page", -1), ("Fit Width", -2), ("Fit Height", -3)] {
                let fit = NSMenuItem(title: title, action: #selector(zoomToPercent(_:)), keyEquivalent: "")
                fit.tag = tag
                popup.menu?.addItem(fit)
            }
            popup.menu?.addItem(.separator())
            for percent in [25, 50, 75, 100, 125, 150, 200, 300, 400] {
                let entry = NSMenuItem(title: percent == 100 ? "100% (Actual Size)" : "\(percent)%",
                                       action: #selector(zoomToPercent(_:)), keyEquivalent: "")
                entry.tag = percent
                popup.menu?.addItem(entry)
            }
            for entry in popup.menu?.items.dropFirst() ?? [] { entry.target = self }
            zoomPopup = popup
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Zoom"
            item.paletteLabel = "Zoom"
            item.toolTip = "Zoom (100% is true size)"
            item.view = popup
            return item
            
        case ToolbarID.style:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "View"
            item.toolTip = "Page Display Style"
            item.image = NSImage(systemSymbolName: "book", accessibilityDescription: "Page display style")
            let menu = NSMenu(title: "View")
            for entry in MenuBuilder.pageStyleItems() { menu.addItem(entry) }
            item.menu = menu
            return item
            
        case ToolbarID.filter:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Filter"
            item.toolTip = "Apply a Quartz Filter"
            item.image = NSImage(systemSymbolName: "camera.filters", accessibilityDescription: "Quartz filter")
            item.menu = QuartzFilterMenuDelegate.makeMenu()
            return item
            
        case ToolbarID.search:
            let item = NSSearchToolbarItem(itemIdentifier: identifier)
            item.label = "Search"
            item.searchField.placeholderString = "Search"
            item.searchField.target = self
            item.searchField.action = #selector(performSearch(_:))
            item.resignsFirstResponderWithCancel = true
            searchItem = item
            return item
        default:
            return nil
        }
    }
    
    @objc func zoomToFitWidth(_ sender: Any?) { store.zoomToFitWidth() }
    @objc func zoomToFitHeight(_ sender: Any?) { store.zoomToFitHeight() }
    /// Toolbar zoom menu: a percentage, or (negative tags) one of the fit commands.
    @objc func zoomToPercent(_ sender: NSMenuItem) {
        switch sender.tag {
        case -1: store.zoomToFit()
        case -2: store.zoomToFitWidth()
        case -3: store.zoomToFitHeight()
        default: store.setZoomPercent(sender.tag)
        }
    }
    
    private func button(_ identifier: NSToolbarItem.Identifier, _ label: String, _ symbol: String,
                        _ action: Selector, _ tip: String) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = nil          // nil target: goes down the responder chain, ends up here
        item.action = action
        item.isBordered = true
        return item
    }

    // MARK: Validation

    private func isEnabled(_ action: Selector?) -> Bool {
        let editingText = window?.firstResponder is NSText
        switch action {
        case #selector(deletePages(_:)):
            // While typing in the search field, ⌘⌫ must keep deleting text.
            return !editingText && store.canDelete(store.targetIndexes)
        case #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(addBlankPage(_:)):
            return store.pageCount > 0
        case #selector(setDirection(_:)):
            // Scroll direction can only be chosen for Single Page Continuous.
            return store.allowsDirectionChoice
        case #selector(goFirst(_:)), #selector(goPrevious(_:)):
            return store.currentPage > 0
        case #selector(goLast(_:)), #selector(goNext(_:)):
            return store.currentPage < store.pageCount - 1
        case #selector(goToPage(_:)):
            return store.pageCount > 1
        case #selector(splitAtBookmarks(_:)):
            return !store.bookmarks.isEmpty && bookmarkSplitter == nil
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !store.searchResults.isEmpty
        case #selector(renameBookmark(_:)), #selector(deleteBookmark(_:)), #selector(addSubBookmark(_:)),
             #selector(indentBookmark(_:)), #selector(outdentBookmark(_:)), #selector(moveBookmarkUp(_:)),
             #selector(moveBookmarkDown(_:)), #selector(setBookmarkDestination(_:)):
            return store.bookmarkSelection != nil
        default:
            return true
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setPageStyle(_:)):
            item.state = MenuBuilder.pageStyleTag(for: store.displayMode) == item.tag ? .on : .off
        case #selector(setDirection(_:)):
            item.state = (item.tag == 0) == (store.effectiveDirection == .vertical) ? .on : .off
        case #selector(toggleBook(_:)):
            item.state = store.displaysAsBook ? .on : .off
        case #selector(togglePageBreaks(_:)):
            item.state = store.displaysPageBreaks ? .on : .off
        case #selector(toggleSidebarPanel(_:)):
            item.title = store.showSidebar ? "Hide Sidebar" : "Show Sidebar"
        case #selector(showThumbnails(_:)):
            item.state = store.showSidebar && store.sidebarTab == .thumbnails ? .on : .off
        case #selector(showBookmarks(_:)):
            item.state = store.showSidebar && store.sidebarTab == .bookmarks ? .on : .off
        default:
            break
        }
        return isEnabled(item.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isEnabled(item.action)
    }

    // MARK: Page actions

    @objc func rotateLeft(_ sender: Any?) { store.rotate(by: -90) }
    @objc func rotateRight(_ sender: Any?) { store.rotate(by: 90) }
    @objc func addBlankPage(_ sender: Any?) { store.addBlankPage() }

    @objc func deletePages(_ sender: Any?) {
        let indexes = store.targetIndexes
        guard store.canDelete(indexes), let window else { NSSound.beep(); return }

        let alert = NSAlert()
        if indexes.count == 1, let only = indexes.first {
            alert.messageText = "Delete Page \(only + 1)?"
        } else {
            alert.messageText = "Delete \(indexes.count) Pages?"
        }
        alert.informativeText = "You can undo this with Edit > Undo until you close the document."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [store] response in
            if response == .alertFirstButtonReturn { store.deletePages(indexes) }
        }
    }

    // MARK: Password protection

    @objc func showPasswordProtection(_ sender: Any?) {
        guard let window else { return }
        let store = self.store
        let showSheet = {
            PasswordProtectionSheet.present(on: window, draft: .init(store.securityForSheet)) {
                store.setSecurity($0)
            }
        }
        if store.needsOwnerPassword {
            PasswordProtectionSheet.askOwnerPassword(on: window, verify: { store.unlockAsOwner($0) }, proceed: showSheet)
        } else {
            showSheet()
        }
    }

    // MARK: Export

    @objc func exportImages(_ sender: Any?) {
        guard let window, imageExporter == nil else { return }
        guard !store.copyingRestricted else {
            let alert = NSAlert()
            alert.messageText = "This document doesn't allow its content to be copied."
            alert.informativeText = "Its owner has restricted copying, so its pages can't be exported."
            alert.beginSheetModal(for: window)
            return
        }
        // The document's name without any .pdf, as the default file-name prefix.
        let name = store.document?.displayName ?? "Pages"
        let base = name.lowercased().hasSuffix(".pdf") ? String(name.dropLast(4)) : name
        let exporter = ImageExporter(store: store, window: window, baseName: base)
        imageExporter = exporter
        exporter.begin { [weak self] in self?.imageExporter = nil }
    }
    
    // MARK: Thumbnail and page commands

    @objc func duplicatePages(_ sender: Any?) { store.duplicatePages() }

    /// Bookmarks the (first) selected page, not the page on screen.
    @objc func addBookmarkAtPage(_ sender: Any?) {
        store.addBookmark(asChild: false, forPage: store.targetIndexes.min())
    }

    @objc func insertPagesFromFile(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Insert Pages"
        panel.message = "Choose PDFs or images to insert after the selected page."
        panel.prompt = "Insert"
        panel.allowedContentTypes = [.pdf, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [store] response in
            guard response == .OK else { return }
            let index = (store.targetIndexes.max() ?? store.pageCount - 1) + 1
            // New images are sized to suit the page they're going in beside.
            let neighbour = store.pdf.page(at: max(0, min(index - 1, store.pageCount - 1)))
            let reference = neighbour?.bounds(for: .mediaBox).size ?? DocumentStore.defaultPageRect.size
            let result = PageImporter.pages(fromURLs: panel.urls, fitting: reference)
            store.insertPages(result.pages, at: index)
            PageImporter.reportSkipped(result.skipped)
        }
    }
    
    // MARK: Go

    @objc func goFirst(_ sender: Any?) { store.goTo(0) }
    @objc func goLast(_ sender: Any?) { store.goTo(store.pageCount - 1) }
    @objc func goPrevious(_ sender: Any?) { store.goTo(max(store.currentPage - 1, 0)) }
    @objc func goNext(_ sender: Any?) { store.goTo(min(store.currentPage + 1, store.pageCount - 1)) }

    @objc func goToPage(_ sender: Any?) {
        guard let window, store.pageCount > 0 else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "1–\(store.pageCount)"
        field.stringValue = "\(store.currentPage + 1)"
        field.alignment = .center

        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Enter a page number from 1 to \(store.pageCount)."
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [store] response in
            guard response == .alertFirstButtonReturn,
                  let number = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            store.goTo(min(max(number, 1), store.pageCount) - 1)
        }
    }

    // MARK: Split

    @objc func splitAtBookmarks(_ sender: Any?) {
        guard let window, bookmarkSplitter == nil else { return }
        let name = store.document?.displayName ?? "Document"
        let base = name.lowercased().hasSuffix(".pdf") ? String(name.dropLast(4)) : name
        let splitter = BookmarkSplitter(store: store, window: window, baseName: base)
        bookmarkSplitter = splitter
        splitter.begin { [weak self] in self?.bookmarkSplitter = nil }
    }
    
    // MARK: Printing

    /// File > Print… (⌘P). Printing goes through PDFView, which shows the standard Print panel
    /// and handles page scaling and rotation. This method catches the menu's printDocument:
    /// before NSDocument's own implementation (which is no longer needed).
    @objc func printDocument(_ sender: Any?) {
        if store.printingRestricted {
            let alert = NSAlert()
            alert.messageText = "This document doesn't allow printing."
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        guard let pdfView = store.pdfView, let printInfo = document?.printInfo else {
            NSSound.beep()
            return
        }
        pdfView.print(with: printInfo, autoRotate: true, pageScaling: .pageScaleDownToFit)
    }

    // MARK: Quartz filters

    @objc func applyQuartzFilter(_ sender: NSMenuItem) {
        guard let filter = sender.representedObject as? QuartzFilter else { return }
        store.applyQuartzFilter(filter, name: QuartzFilterMenuDelegate.name(of: filter))
    }

    @objc func chooseQuartzFilter(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Quartz Filter"
        panel.allowedContentTypes = [UTType(filenameExtension: "qfilter") ?? .data]
        panel.directoryURL = URL(fileURLWithPath: "/System/Library/Filters")
        guard let window else { return }
        panel.beginSheetModal(for: window) { [store] response in
            guard response == .OK, let url = panel.url else { return }
            let filter: QuartzFilter? = QuartzFilter(url: url)
            if let filter {
                store.applyQuartzFilter(filter, name: url.deletingPathExtension().lastPathComponent)
            } else {
                NSSound.beep()
            }
        }
    }

    // MARK: View actions

    @objc func setPageStyle(_ sender: NSMenuItem) {
        store.displayMode = MenuBuilder.pageMode(forTag: sender.tag)
    }

    @objc func setDirection(_ sender: NSMenuItem) {
        store.displayDirection = sender.tag == 0 ? .vertical : .horizontal
    }

    @objc func toggleBook(_ sender: Any?) { store.displaysAsBook.toggle() }
    @objc func togglePageBreaks(_ sender: Any?) { store.displaysPageBreaks.toggle() }

    @objc func zoomIn(_ sender: Any?) { store.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { store.zoomOut() }
    @objc func zoomActualSize(_ sender: Any?) { store.zoomActualSize() }
    @objc func zoomToFit(_ sender: Any?) { store.zoomToFit() }

    @objc func saveViewAsDefault(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(MenuBuilder.pageStyleTag(for: store.displayMode), forKey: AppSettings.Key.pageStyle)
        defaults.set(store.displayDirection == .horizontal ? 1 : 0, forKey: AppSettings.Key.direction)
        defaults.set(store.displaysAsBook, forKey: AppSettings.Key.firstPageIsCover)
        defaults.set(store.displaysPageBreaks, forKey: AppSettings.Key.pageBreaks)
        defaults.set(store.showSidebar, forKey: AppSettings.Key.showSidebar)
        defaults.set(store.sidebarTab.rawValue, forKey: AppSettings.Key.sidebarTab)
        defaults.set(Double(store.sidebarWidth), forKey: AppSettings.Key.sidebarWidth)
    }

    @objc func toggleSidebarPanel(_ sender: Any?) { store.showSidebar.toggle() }

    @objc func showThumbnails(_ sender: Any?) {
        store.sidebarTab = .thumbnails
        store.showSidebar = true
    }

    @objc func showBookmarks(_ sender: Any?) {
        store.sidebarTab = .bookmarks
        store.showSidebar = true
    }

    // MARK: Search

    @objc func focusSearch(_ sender: Any?) {
        guard let searchItem else { NSSound.beep(); return }
        searchItem.beginSearchInteraction()
    }

    @objc func performSearch(_ sender: NSSearchField) { store.search(sender.stringValue) }
    @objc func findNext(_ sender: Any?) { store.nextResult() }
    @objc func findPrevious(_ sender: Any?) { store.previousResult() }

    // MARK: Bookmark actions

    @objc func addBookmark(_ sender: Any?) { store.addBookmark(asChild: false) }
    @objc func addSubBookmark(_ sender: Any?) { store.addBookmark(asChild: true) }
    @objc func renameBookmark(_ sender: Any?) { store.promptRenameSelectedBookmark() }
    @objc func deleteBookmark(_ sender: Any?) { store.deleteSelectedBookmark() }
    @objc func indentBookmark(_ sender: Any?) { store.indentSelectedBookmark() }
    @objc func outdentBookmark(_ sender: Any?) { store.outdentSelectedBookmark() }
    @objc func moveBookmarkUp(_ sender: Any?) { store.moveSelectedBookmark(by: -1) }
    @objc func moveBookmarkDown(_ sender: Any?) { store.moveSelectedBookmark(by: 1) }
    @objc func setBookmarkDestination(_ sender: Any?) { store.setSelectedBookmarkDestinationToCurrentPage() }
}

// MARK: - Split view

/// Keeps the store's sidebar flag and width in step when the user drags the divider
/// (including dragging it closed).
final class SidebarSplitViewController: NSSplitViewController {
    private weak var store: DocumentStore?
    private let initialSidebarWidth: CGFloat
    private var hasAppliedInitialWidth = false

    init(store: DocumentStore, initialSidebarWidth: CGFloat) {
        self.store = store
        self.initialSidebarWidth = initialSidebarWidth
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The divider can only be positioned once the window is on screen and laid out.
    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppliedInitialWidth else { return }
        if let item = splitViewItems.first, !item.isCollapsed {
            splitView.layoutSubtreeIfNeeded()
            splitView.setPosition(initialSidebarWidth, ofDividerAt: 0)
        }
        hasAppliedInitialWidth = true
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        // Ignore the layout passes before the saved width has been applied.
        guard hasAppliedInitialWidth, let store, let item = splitViewItems.first else { return }
        let shown = !item.isCollapsed
        if store.showSidebar != shown { store.showSidebar = shown }
        if shown {
            let width = item.viewController.view.frame.width
            if abs(store.sidebarWidth - width) > 1 { store.sidebarWidth = width }
        }
    }
}
