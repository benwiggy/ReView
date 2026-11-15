import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Thumbnail sidebar built on NSCollectionView: one column, fixed (user-settable) width,
/// Shift-click ranges, Command-click toggling, drag-to-reorder and drag-out to Finder.
struct ThumbnailCollectionView: NSViewRepresentable {
    @ObservedObject var store: DocumentStore
    
    /// Mid-grey so white pages stand out; a touch darker in Dark Mode.
    static let backgroundGrey = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.28, alpha: 1)
            : NSColor(white: 0.62, alpha: 1)
    }

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 6
        // A huge inter-item gap means two items can never share a row: always one column.
        layout.minimumInteritemSpacing = 10_000

        let collection = ThumbnailCollectionNSView()
        collection.collectionViewLayout = layout
        collection.autoresizingMask = [.width]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [Self.backgroundGrey]
        collection.dataSource = coordinator
        collection.delegate = coordinator
        collection.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
        collection.store = store
        collection.onSelectionChangedByMouse = { [weak coordinator, weak collection] in
            guard let coordinator, let collection else { return }
            coordinator.selectionChangedByUser(collection)
        }

        // Accept drags that originate here (reordering). Local drags move; drags to Finder copy.
        collection.registerForDraggedTypes(
            NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + PageImporter.draggedTypes)
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        collection.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Self.backgroundGrey
        scroll.autohidesScrollers = true

        coordinator.collection = collection
        coordinator.lastPDF = store.pdf
        coordinator.lastRevision = store.pageRevision
        coordinator.lastThumbnailWidth = store.thumbnailWidth
        DispatchQueue.main.async { coordinator.syncSelection(scroll: true) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let collection = coordinator.collection else { return }

        if coordinator.lastPDF !== store.pdf
            || coordinator.lastRevision != store.pageRevision
            || coordinator.lastThumbnailWidth != store.thumbnailWidth {
            coordinator.lastPDF = store.pdf
            coordinator.lastRevision = store.pageRevision
            coordinator.lastThumbnailWidth = store.thumbnailWidth
            coordinator.cache.removeAllObjects()
            collection.collectionViewLayout?.invalidateLayout()
            collection.reloadData()
        }
        coordinator.syncSelection(scroll: true)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout,
                             NSFilePromiseProviderDelegate {
        let store: DocumentStore
        weak var collection: ThumbnailCollectionNSView?
        var lastPDF: PDFDocument?
        var lastRevision = -1
        var lastThumbnailWidth: CGFloat = 0
        let cache = NSCache<NSString, NSImage>()
        private var draggedIndexes = IndexSet()

        init(store: DocumentStore) { self.store = store }

        // MARK: Selection sync

        /// Push the store's selection into the collection view. Programmatic changes don't
        /// call the delegate, so there is no feedback loop.
        func syncSelection(scroll: Bool) {
            guard let collection else { return }
            let count = store.pdf.pageCount
            let wanted = Set(store.selection.filter { $0 < count }.map { IndexPath(item: $0, section: 0) })
            guard collection.selectionIndexPaths != wanted else { return }
            collection.selectionIndexPaths = wanted
            if scroll, wanted.count == 1 {
                collection.scrollToItems(at: wanted, scrollPosition: .nearestVerticalEdge)
            }
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            selectionChangedByUser(collectionView)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            selectionChangedByUser(collectionView)
        }

        func selectionChangedByUser(_ collectionView: NSCollectionView) {
            let indexes = IndexSet(collectionView.selectionIndexPaths.map { $0.item })
            guard store.selection != indexes else { return }
            store.selection = indexes
            // Clicking one page shows it; a multi-selection leaves the PDF view alone.
            if indexes.count == 1, let only = indexes.first { store.goTo(only) }
        }

        // MARK: Data source

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            store.pdf.pageCount
        }

        func collectionView(_ collectionView: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath)
            if let item = item as? ThumbnailItem {
                item.configure(image: image(for: indexPath.item, itemWidth: itemWidth(in: collectionView)),
                               number: indexPath.item + 1)
            }
            return item
        }

        // MARK: Layout

        /// The width set in Settings, shrunk only if the sidebar is narrower than that.
        private func itemWidth(in collectionView: NSCollectionView) -> CGFloat {
            let wanted = store.thumbnailWidth
            let available = collectionView.bounds.width - 16
            return available > 0 ? max(70, min(wanted, available)) : wanted
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> NSSize {
            let width = itemWidth(in: collectionView)
            return NSSize(width: width, height: (width * 1.35).rounded() + 22)
        }

        /// Centre the single column when the sidebar is wider than the thumbnails.
        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            insetForSectionAt section: Int) -> NSEdgeInsets {
            let side = max(8, ((collectionView.bounds.width - itemWidth(in: collectionView)) / 2).rounded(.down))
            return NSEdgeInsets(top: 8, left: side, bottom: 8, right: side)
        }

        private func image(for index: Int, itemWidth: CGFloat) -> NSImage? {
            guard let page = store.pdf.page(at: index) else { return nil }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let box = NSSize(width: (itemWidth - 8) * scale, height: (itemWidth * 1.35) * scale)
            let key = "\(ObjectIdentifier(page).hashValue)-\(page.rotation)-\(Int(box.width))" as NSString
            if let cached = cache.object(forKey: key) { return cached }
            let image = page.thumbnail(of: box, for: .cropBox)
            cache.setObject(image, forKey: key)
            return image
        }

        // MARK: Drag out (reorder, and export to Finder)

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
                            with event: NSEvent) -> Bool { true }

        private func pagesBeingDragged(from item: Int, in collectionView: NSCollectionView) -> [Int] {
            let selected = Set(collectionView.selectionIndexPaths.map { $0.item })
            return selected.contains(item) ? selected.sorted() : [item]
        }

        /// One promise carries the whole selection, so Finder gets a single PDF of those pages
        /// rather than one file per page. Only the first dragged item supplies it.
        func collectionView(_ collectionView: NSCollectionView,
                            pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            let pages = pagesBeingDragged(from: indexPath.item, in: collectionView)
            guard pages.first == indexPath.item else { return nil }
            let provider = NSFilePromiseProvider(fileType: UTType.pdf.identifier, delegate: self)
            provider.userInfo = pages
            return provider
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                            willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
            let first = indexPaths.map { $0.item }.min() ?? 0
            draggedIndexes = IndexSet(pagesBeingDragged(from: first, in: collectionView))
            // Publish the same pages on the collection view, so another window's sidebar can copy them.
            (collectionView as? ThumbnailCollectionNSView)?.draggedPages = draggedIndexes
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                            endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
            draggedIndexes = IndexSet()
            (collectionView as? ThumbnailCollectionNSView)?.draggedPages = IndexSet()
        }

        // MARK: Drop (reorder pages, or insert dropped PDFs and images)

        private func isOwnDrag(_ draggingInfo: NSDraggingInfo, in collectionView: NSCollectionView) -> Bool {
            (draggingInfo.draggingSource as? NSCollectionView) === collectionView
        }
        
        /// Dropping over a thumbnail means "before it" in its top half and "after it" in its bottom half.
        private func snapToGap(_ draggingInfo: NSDraggingInfo, in collectionView: NSCollectionView,
                               proposed: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                               operation: UnsafeMutablePointer<NSCollectionView.DropOperation>) {
            if operation.pointee == .on,
               let frame = collectionView.layoutAttributesForItem(at: proposed.pointee as IndexPath)?.frame {
                let point = collectionView.convert(draggingInfo.draggingLocation, from: nil)
                let inLowerHalf = collectionView.isFlipped ? point.y > frame.midY : point.y < frame.midY
                if inLowerHalf {
                    proposed.pointee = IndexPath(item: proposed.pointee.item + 1, section: 0) as NSIndexPath
                }
            }
            operation.pointee = .before
        }

        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            if isOwnDrag(draggingInfo, in: collectionView) {
                guard !draggedIndexes.isEmpty else { return [] }
                snapToGap(draggingInfo, in: collectionView, proposed: proposedDropIndexPath, operation: proposedDropOperation)
                return .move
            }
            // Pages dragged from another window's sidebar: copied across.
            if let other = draggingInfo.draggingSource as? ThumbnailCollectionNSView {
                guard let otherStore = other.store, otherStore !== store,
                      !other.draggedPages.isEmpty, !otherStore.copyingRestricted else { return [] }
                snapToGap(draggingInfo, in: collectionView, proposed: proposedDropIndexPath, operation: proposedDropOperation)
                return .copy
            }
            guard PageImporter.canImport(from: draggingInfo.draggingPasteboard) else { return [] }
            snapToGap(draggingInfo, in: collectionView, proposed: proposedDropIndexPath, operation: proposedDropOperation)
            return .copy
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            if isOwnDrag(draggingInfo, in: collectionView) {
                guard !draggedIndexes.isEmpty else { return false }
                store.movePages(from: draggedIndexes, toBefore: indexPath.item)
                return true
            }

            let index = min(indexPath.item, store.pdf.pageCount)

            if let other = draggingInfo.draggingSource as? ThumbnailCollectionNSView, let otherStore = other.store {
                // Copies: inserting the originals would pull them out of the other document.
                let pages = other.draggedPages.compactMap { otherStore.pdf.page(at: $0)?.copy() as? PDFPage }
                store.insertPages(pages, at: index)
                return !pages.isEmpty
            }

            // New images are sized to suit the page they're going in beside.
            let neighbour = store.pdf.page(at: min(index, store.pdf.pageCount - 1))
            let reference = neighbour?.bounds(for: .mediaBox).size ?? DocumentStore.defaultPageRect.size
            let result = PageImporter.pages(from: draggingInfo.draggingPasteboard, fitting: reference)
            store.insertPages(result.pages, at: index)
            if !result.skipped.isEmpty {
                DispatchQueue.main.async { PageImporter.reportSkipped(result.skipped) }
            }
            return !result.pages.isEmpty
        }

        // MARK: File promise (drag to Finder)

        func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            let pages = (provider.userInfo as? [Int]) ?? []
            let base = store.document?.displayName ?? "Document"
            guard let first = pages.first, let last = pages.last else { return "\(base).pdf" }
            return first == last
                ? "\(base) - page \(first + 1).pdf"
                : "\(base) - pages \(first + 1)-\(last + 1).pdf"
        }

        func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            let pages = (provider.userInfo as? [Int]) ?? []
            guard !store.copyingRestricted else {
                completionHandler(CocoaError(.fileWriteNoPermission))
                return
            }
            let output = PDFDocument()
            // Copies: inserting the originals would pull them out of the open document.
            for index in pages {
                if let copy = store.pdf.page(at: index)?.copy() as? PDFPage {
                    output.insert(copy, at: output.pageCount)
                }
            }
            completionHandler(output.write(to: url) ? nil : CocoaError(.fileWriteUnknown))
        }

        func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { .main }
    }
}

// MARK: - Collection view with Shift-click range selection

/// NSCollectionView treats Shift-click like Command-click. This adds the usual behaviour:
/// click sets an anchor, Shift-click selects everything from the anchor to the clicked page,
/// Command-click toggles one page (and moves the anchor), Command-Shift-click adds a range.
final class ThumbnailCollectionNSView: NSCollectionView {
    var onSelectionChangedByMouse: (() -> Void)?
    /// The document this sidebar shows, and the pages being dragged out of it right now,
    /// so another window's sidebar can copy them directly.
    weak var store: DocumentStore?
    var draggedPages = IndexSet()
    private var anchor: Int?

    /// Right-click (or Control-click) on a page. As in the Finder, a page outside the selection
    /// becomes the selection first; the commands then apply to the whole selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let path = indexPathForItem(at: point) else { return nil }
        if !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
            anchor = path.item
            onSelectionChangedByMouse?()
        }
        return ThumbnailContextMenu.make(selection: IndexSet(selectionIndexPaths.map { $0.item }))    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let clicked = indexPathForItem(at: point) else {
            super.mouseDown(with: event)   // empty space
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let count = numberOfItems(inSection: 0)
        let start = anchor.flatMap { $0 < count ? $0 : nil } ?? selectionIndexPaths.map { $0.item }.min()

        if flags.contains(.shift), let start {
            let range = min(start, clicked.item)...max(start, clicked.item)
            var selection = Set(range.map { IndexPath(item: $0, section: 0) })
            if flags.contains(.command) { selection.formUnion(selectionIndexPaths) }
            selectionIndexPaths = selection      // programmatic, so tell the owner ourselves
            onSelectionChangedByMouse?()
            return
        }

        anchor = clicked.item
        super.mouseDown(with: event)
    }
}

// MARK: - Item

final class ThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem")

    private let thumbnail = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(thumbnail)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            thumbnail.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            thumbnail.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            thumbnail.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            label.heightAnchor.constraint(equalToConstant: 15)
        ])
        view = container
        updateAppearance()
    }

    func configure(image: NSImage?, number: Int) {
        thumbnail.image = image
        label.stringValue = "\(number)"
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        view.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - Context menu

/// Items have no target: they travel down the responder chain to the window's
/// DocumentWindowController, which also enables and disables them.
enum ThumbnailContextMenu {
    static func make(selection: IndexSet) -> NSMenu {
        let count = selection.count
        let noun = count == 1 ? "Page" : "\(count) Pages"
        let first = (selection.min() ?? 0) + 1
        let last = (selection.max() ?? 0) + 1
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            menu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: ""))
        }
        add("Rotate \(noun) Left", #selector(DocumentWindowController.rotateLeft(_:)))
        add("Rotate \(noun) Right", #selector(DocumentWindowController.rotateRight(_:)))
        menu.addItem(.separator())
        add("Add Blank Page Before Page \(first)", #selector(DocumentWindowController.addBlankPage(_:)))
        add("Insert Pages from File After Page \(last)…", #selector(DocumentWindowController.insertPagesFromFile(_:)))
        add("Duplicate \(noun)", #selector(DocumentWindowController.duplicatePages(_:)))
        menu.addItem(.separator())
        add("Add Bookmark for Page \(first)", #selector(DocumentWindowController.addBookmarkAtPage(_:)))
        menu.addItem(.separator())
        add("Delete \(noun)", #selector(DocumentWindowController.deletePages(_:)))
        return menu
    }
}
