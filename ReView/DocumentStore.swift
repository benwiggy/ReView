import AppKit
import Combine
import PDFKit
import Quartz

enum SidebarTab: Int { case thumbnails, bookmarks, annotations }

/// Everything the UI shows and every edit the user can make. One store per open document.
/// All methods are expected to run on the main thread.
final class DocumentStore: ObservableObject {

    weak var document: NSDocument?
    weak var pdfView: PDFView?

    // MARK: Document state

    @Published private(set) var pdf: PDFDocument
    /// Bumped whenever pages are added, removed, moved or rotated, so views know to refresh.
    @Published private(set) var pageRevision = 0
    @Published var selection = IndexSet()          // selected pages (thumbnail pane)
    @Published var currentPage = 0                 // page showing in the PDF view
    /// Set by edits that should scroll the PDF view somewhere specific. Not published on purpose.
    var pendingPage: Int?
    
    // MARK: Metadata

    struct DocumentMetadata: Equatable {
        var title = "", author = "", creator = "", subject = "", keywords = ""
    }
    /// Edited in the Inspector; written into the PDF's info dictionary when saving.
    @Published private(set) var metadata = DocumentMetadata()

    // MARK: View settings

    @Published var displayMode: PDFDisplayMode = .singlePageContinuous
    @Published var displayDirection: PDFDisplayDirection = .vertical
    @Published var displaysAsBook = false          // "first page is cover" in two-page modes
    @Published var displaysPageBreaks = true
    @Published var showSidebar = true
    @Published var sidebarTab: SidebarTab = .thumbnails
    
    
    // MARK: Annotations

    @Published var markupTool: MarkupTool = .select
    @Published var markupColor: MarkupColor = .yellow
    /// The Markup strip is hidden until asked for; hiding it also puts the Select tool back.
    @Published var showMarkupStrip = false {
        didSet { if !showMarkupStrip { markupTool = .select } }
    }
    /// Bumped when annotations are added or removed, so the Annotations list refreshes.
    @Published var annotationRevision = 0
    /// The row selected in the Annotations list (see AnnotationRow.id).
    @Published var selectedAnnotationID: String?
    /// Set when the app itself selects a row, so the page doesn't scroll to it.
    var suppressRevealFor: String?
    /// The markup selected on the page itself (text box, later shapes).
    @Published var selectedMarkup: PlacedAnnotation?
    var authorName: String { AppSettings.authorName }
    /// The file's owner has forbidden commenting (and we haven't replaced its protection).
    var commentingRestricted: Bool { security == nil && opened.restrictsCommenting }
    
    
    @Published var sidebarWidth: CGFloat = 230
    @Published var thumbnailWidth: CGFloat = AppSettings.thumbnailWidth

    /// Scroll direction can only be chosen for Single Page Continuous; other styles are always vertical.
    var allowsDirectionChoice: Bool { displayMode == .singlePageContinuous }
    var effectiveDirection: PDFDisplayDirection { allowsDirectionChoice ? displayDirection : .vertical }

    // MARK: Bookmarks

    @Published var bookmarks: [BookmarkNode] = []
    @Published var bookmarkSelection: UUID?

    // MARK: Search

    @Published private(set) var searchResults: [PDFSelection] = []
    @Published private(set) var searchIndex = 0
    @Published private(set) var isSearching = false

    @Published var isBusy = false
    
    // MARK: Security
    struct OpenedProtection {
        var password: String?            // what the user typed to open it
        var restrictsPrinting = false
        var restrictsCopying = false
        var restrictsCommenting = false
        var ownerUnlocked = true
        var hasRestrictions: Bool { restrictsPrinting || restrictsCopying }
        var passwordIsOwner = false
    }
    private(set) var opened = OpenedProtection()
    @Published private(set) var security: SecuritySettings?   // nil = user hasn't chosen anything
    @Published private(set) var securityRevision = 0
    private var knownOwnerPassword: String?

    var copyingRestricted: Bool { security.map { !$0.allowsCopying } ?? opened.restrictsCopying }
    var printingRestricted: Bool { security.map { !$0.allowsPrinting } ?? opened.restrictsPrinting }
    var isProtected: Bool {
        security.map { !$0.isUnprotected } ?? (opened.password != nil || opened.hasRestrictions)
    }
    var needsOwnerPassword: Bool { security == nil && opened.hasRestrictions && !opened.ownerUnlocked }
    var requiresOpenPassword: Bool { security.map { $0.openPassword != nil } ?? (opened.password != nil) }

    // MARK: - Lifecycle

    private let findDelegate = FindDelegate()
    private var defaultsObserver: NSObjectProtocol?

    var undoManager: UndoManager? { document?.undoManager }
    
    init() {
        pdf = Self.blankDocument()
        findDelegate.store = self
        pdf.delegate = findDelegate
        applyDefaults()

        // Thumbnail width changes in Settings apply to open windows straight away.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let width = AppSettings.thumbnailWidth
            if self.thumbnailWidth != width { self.thumbnailWidth = width }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    /// Start with the user's saved view options (Settings window / Save Current View as Default).
    private func applyDefaults() {
        AppSettings.registerDefaults()   // so unset keys read as their defaults (e.g. sidebar shown), whatever main.swift does
        let defaults = UserDefaults.standard
        displayMode = MenuBuilder.pageMode(forTag: defaults.integer(forKey: AppSettings.Key.pageStyle))
        displayDirection = defaults.integer(forKey: AppSettings.Key.direction) == 1 ? .horizontal : .vertical
        displaysAsBook = defaults.bool(forKey: AppSettings.Key.firstPageIsCover)
        displaysPageBreaks = defaults.bool(forKey: AppSettings.Key.pageBreaks)
        showSidebar = defaults.bool(forKey: AppSettings.Key.showSidebar)
        sidebarTab = SidebarTab(rawValue: defaults.integer(forKey: AppSettings.Key.sidebarTab)) ?? .thumbnails
        let width = defaults.double(forKey: AppSettings.Key.sidebarWidth)
        sidebarWidth = CGFloat(min(max(width, 170), 420))
        thumbnailWidth = AppSettings.thumbnailWidth
    }

    nonisolated static var defaultPageRect: CGRect {
        // A4 unless the Mac is set to US units.
        Locale.current.measurementSystem == .us
            ? CGRect(x: 0, y: 0, width: 612, height: 792)
            : CGRect(x: 0, y: 0, width: 595, height: 842)
    }

    nonisolated static func blankDocument() -> PDFDocument {
        let doc = PDFDocument()
        let page = PDFPage()
        page.setBounds(defaultPageRect, for: .mediaBox)
        doc.insert(page, at: 0)
        return doc
    }

    /// Replace the whole document (open or revert).
    func load(_ newPDF: PDFDocument, openPassword password: String? = nil) {
        opened = OpenedProtection(password: password,
                                  restrictsPrinting: !newPDF.allowsPrinting,
                                  restrictsCopying: !newPDF.allowsCopying,
                                  restrictsCommenting: !newPDF.allowsCommenting,
                                  ownerUnlocked: newPDF.permissionsStatus == .owner,
                                  passwordIsOwner: password != nil && newPDF.permissionsStatus == .owner)
        security = nil
        knownOwnerPassword = nil
        securityRevision += 1
        metadata = Self.readMetadata(newPDF)
        cancelSearch()
        newPDF.delegate = findDelegate
        pdf = newPDF
        bookmarks = newPDF.outlineRoot.map(Self.readOutline) ?? []
        bookmarkSelection = nil
        selection = newPDF.pageCount > 0 ? IndexSet(integer: 0) : IndexSet()
        currentPage = 0
        pendingPage = nil
        pageRevision += 1
    }
    
    // MARK: - Metadata

    private static func readMetadata(_ pdf: PDFDocument) -> DocumentMetadata {
        let attributes = pdf.documentAttributes ?? [:]
        var result = DocumentMetadata()
        result.title = attributes[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        result.author = attributes[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        result.subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        result.creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        if let words = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            result.keywords = words.joined(separator: ", ")
        } else if let text = attributes[PDFDocumentAttribute.keywordsAttribute] as? String {
            result.keywords = text
        }
        return result
    }

    /// Undoable.
    func setMetadata(_ new: DocumentMetadata) {
        guard new != metadata else { return }
        let before = metadata
        metadata = new
        undoManager?.registerUndo(withTarget: self) { store in store.setMetadata(before) }
        undoManager?.setActionName("Edit Metadata")
    }

    /// Write the edited metadata into the PDF so it is included when the document is saved.
    func commitMetadata() {
        var attributes = pdf.documentAttributes ?? [:]
        func set(_ key: PDFDocumentAttribute, _ value: Any?) {
            if let value { attributes[key] = value } else { attributes.removeValue(forKey: key) }
        }
        set(.titleAttribute, metadata.title.isEmpty ? nil : metadata.title)
        set(.authorAttribute, metadata.author.isEmpty ? nil : metadata.author)
        set(.subjectAttribute, metadata.subject.isEmpty ? nil : metadata.subject)
        set(.creatorAttribute, metadata.creator.isEmpty ? nil : metadata.creator)
        let words = metadata.keywords
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        set(.keywordsAttribute, words.isEmpty ? nil : words)
        pdf.documentAttributes = attributes
    }

    // MARK: - Password protection

    func makeUnprotected() {
        opened = OpenedProtection()
        security = SecuritySettings()
        securityRevision += 1
    }

    /// The file needs a password to open, but it was opened with its owner password, so the open password isn't known.
    var openPasswordIsUnknown: Bool { security == nil && opened.passwordIsOwner }

    var securityForSheet: SecuritySettings {
        if security == nil, opened.passwordIsOwner {
            return SecuritySettings(openPassword: nil, ownerPassword: opened.password,
                                    allowsPrinting: !opened.restrictsPrinting,
                                    allowsCopying: !opened.restrictsCopying)
        }
        return security ?? SecuritySettings(openPassword: opened.password, ownerPassword: knownOwnerPassword,
                                            allowsPrinting: !opened.restrictsPrinting,
                                            allowsCopying: !opened.restrictsCopying)
    }

    func unlockAsOwner(_ password: String) -> Bool {
        guard pdf.unlock(withPassword: password), pdf.permissionsStatus == .owner else { return false }
        opened.ownerUnlocked = true
        knownOwnerPassword = password
        return true
    }

    func setSecurity(_ new: SecuritySettings?) {
        let before = security
        guard new != before else { return }
        security = new
        securityRevision += 1
        undoManager?.registerUndo(withTarget: self) { store in store.setSecurity(before) }
        undoManager?.setActionName("Change Password Protection")
    }

    // MARK: Writing

    func encodedData() throws -> Data {
        guard let security else { return try untouchedData() }
        return try explicitData(security)
    }

    private func untouchedData() throws -> Data {
        guard let data = pdf.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        guard let check = PDFDocument(data: data) else { throw SaveVerificationError() }
        if let password = opened.password {
            guard check.isLocked, check.unlock(withPassword: password) else { throw SaveVerificationError() }
        } else {
            guard !check.isLocked else { throw SaveVerificationError() }
        }
        guard check.pageCount == pdf.pageCount,
              check.allowsPrinting == !opened.restrictsPrinting,
              check.allowsCopying == !opened.restrictsCopying else { throw SaveVerificationError() }
        return data
    }

    private func explicitData(_ settings: SecuritySettings) throws -> Data {
        func matches(_ data: Data) -> Bool {
            guard let check = PDFDocument(data: data) else { return false }
            if let password = settings.openPassword {
                guard check.isLocked, check.unlock(withPassword: password) else { return false }
            } else if check.isLocked {
                return false
            }
            if settings.isUnprotected && check.isEncrypted { return false }
            return check.pageCount == pdf.pageCount
                && check.allowsPrinting == settings.allowsPrinting
                && check.allowsCopying == settings.allowsCopying
        }

        var options: [AnyHashable: Any] = [:]
        if let open = settings.openPassword { options[PDFDocumentWriteOption.userPasswordOption] = open }
        if let owner = settings.ownerPassword ?? settings.openPassword {
            options[PDFDocumentWriteOption.ownerPasswordOption] = owner
        }
        if !settings.isUnprotected {
            options[PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsPrinting as String)] = settings.allowsPrinting
            options[PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsCopying as String)] = settings.allowsCopying
        }

        if let data = pdf.dataRepresentation(options: options), matches(data) { return data }

        if settings.isUnprotected, let fresh = cleanCopy(),
           let data = fresh.dataRepresentation(), matches(data) {
            return data
        }
        throw SaveVerificationError()
    }

    private func cleanCopy() -> PDFDocument? {
        let fresh = PDFDocument()
        var map: [ObjectIdentifier: PDFPage] = [:]
        for index in 0..<pdf.pageCount {
            guard let old = pdf.page(at: index), let copy = old.copy() as? PDFPage else { return nil }
            fresh.insert(copy, at: index)
            map[ObjectIdentifier(old)] = copy
        }
        if let attributes = pdf.documentAttributes { fresh.documentAttributes = attributes }
        let marks = bookmarks.remapped { page in page.flatMap { map[ObjectIdentifier($0)] } }
        fresh.outlineRoot = buildOutline(marks, in: fresh)
        return fresh
    }
    
    // MARK: - Page selection helpers

    var pageCount: Int { pdf.pageCount }

    /// The pages an action applies to: the thumbnail selection, or the page on screen if none.
    var targetIndexes: IndexSet {
        let valid = selection.filteredIndexSet { $0 < pdf.pageCount }
        if !valid.isEmpty { return valid }
        return pdf.pageCount > 0 ? IndexSet(integer: min(currentPage, pdf.pageCount - 1)) : IndexSet()
    }

    func canDelete(_ indexes: IndexSet) -> Bool {
        !indexes.isEmpty && indexes.count < pdf.pageCount
    }

    func goTo(_ index: Int) {
        guard let page = pdf.page(at: index) else { return }
        pdfView?.go(to: page)
    }

    /// Called (asynchronously) when the PDF view's current page changes.
    func pageDidChange(to index: Int) {
        if currentPage != index { currentPage = index }
        // Follow scrolling only while the selection is a single page, so a deliberate
        // multi-page selection isn't thrown away.
        if selection.count <= 1, selection != IndexSet(integer: index) {
            selection = IndexSet(integer: index)
        }
    }

    // MARK: - Page edits (all undoable)

    private struct PageSnapshot {
        var pages: [PDFPage]
        var rotations: [Int]
    }

    private func snapshot() -> PageSnapshot {
        let pages = (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
        return PageSnapshot(pages: pages, rotations: pages.map { $0.rotation })
    }

    private func restore(_ snap: PageSnapshot) {
        while pdf.pageCount > 0 { pdf.removePage(at: pdf.pageCount - 1) }
        for (i, page) in snap.pages.enumerated() {
            page.rotation = snap.rotations[i]
            pdf.insert(page, at: i)
        }
        pagesDidChange()
    }

    /// Registers an undo that restores `target`; when run, it registers the matching redo.
    private func registerRestore(_ target: PageSnapshot, name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            let now = store.snapshot()
            store.restore(target)
            store.registerRestore(now, name: name)
        }
        undoManager.setActionName(name)
    }

    private func performPageEdit(_ name: String, _ body: () -> Void) {
        let before = snapshot()
        body()
        registerRestore(before, name: name)
        pagesDidChange()
    }

    private func pagesDidChange() {
        cancelSearch()   // stored matches may point at moved or deleted pages
        selection = selection.filteredIndexSet { $0 < pdf.pageCount }
        pageRevision += 1
    }

    func rotate(by degrees: Int) {
        let indexes = targetIndexes
        guard !indexes.isEmpty else { return }
        performPageEdit("Rotate Pages") {
            for i in indexes {
                guard let page = pdf.page(at: i) else { continue }
                page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
            }
        }
    }

    func deletePages(_ indexes: IndexSet) {
        guard canDelete(indexes), let first = indexes.first else { return }
        performPageEdit("Delete Pages") {
            for i in indexes.reversed() { pdf.removePage(at: i) }
        }
        let landing = min(first, pdf.pageCount - 1)
        selection = IndexSet(integer: landing)
        pendingPage = landing
        pageRevision += 1
    }

    /// Inserts a blank page before the first target page, matching its size and rotation.
    func addBlankPage() {
        let index = targetIndexes.min() ?? 0
        let reference = pdf.page(at: index)
        let blank = PDFPage()
        blank.setBounds(reference?.bounds(for: .mediaBox) ?? Self.defaultPageRect, for: .mediaBox)
        if let crop = reference?.bounds(for: .cropBox) { blank.setBounds(crop, for: .cropBox) }
        blank.rotation = reference?.rotation ?? 0
        performPageEdit("Add Blank Page") { pdf.insert(blank, at: index) }
        selection = IndexSet(integer: index)
        pendingPage = index
        pageRevision += 1
    }

    /// Inserts pages (already copies) so the first sits at `index`, and selects them.
    func insertPages(_ pages: [PDFPage], at index: Int, actionName: String? = nil) {
        guard !pages.isEmpty else { return }
        let at = min(max(index, 0), pdf.pageCount)
        performPageEdit(actionName ?? (pages.count == 1 ? "Insert Page" : "Insert Pages")) {
            for (offset, page) in pages.enumerated() { pdf.insert(page, at: at + offset) }
        }
        selection = IndexSet(integersIn: at..<(at + pages.count))
        pendingPage = at
        pageRevision += 1
    }
    
    /// Copies the selected pages and puts the copies straight after the last of them.
    func duplicatePages() {
        let indexes = targetIndexes
        guard let last = indexes.max() else { return }
        let copies = indexes.compactMap { pdf.page(at: $0)?.copy() as? PDFPage }
        insertPages(copies, at: last + 1, actionName: indexes.count == 1 ? "Duplicate Page" : "Duplicate Pages")
    }
    
    /// Moves pages so they sit immediately before the page currently at `destination`
    /// (`destination == pageCount` means the end).
    func movePages(from indexes: IndexSet, toBefore destination: Int) {
        let pages = indexes.compactMap { pdf.page(at: $0) }
        guard !pages.isEmpty else { return }
        let removedBefore = indexes.filter { $0 < destination }.count
        let insertAt = destination - removedBefore
        if insertAt == indexes.first, indexes.count == (indexes.last ?? 0) - (indexes.first ?? 0) + 1 {
            return   // dropped back where it came from
        }
        performPageEdit("Reorder Pages") {
            for i in indexes.reversed() { pdf.removePage(at: i) }
            for (offset, page) in pages.enumerated() { pdf.insert(page, at: insertAt + offset) }
        }
        selection = IndexSet(integersIn: insertAt..<(insertAt + pages.count))
        pendingPage = insertAt
        pageRevision += 1
    }

    // MARK: - View commands

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    /// Zoom to Fit: the whole page (in two-page styles, the whole spread) fits in the window.
    func zoomToFit() { fit(width: true, height: true) }
    func zoomToFitWidth() { fit(width: true, height: false) }
    func zoomToFitHeight() { fit(width: false, height: true) }

    /// PDFKit's own fit (`autoScales`) only fits the width, so this works the scale out from the
    /// page (or spread) on screen and the size of the viewing area. It does not follow later window
    /// resizing: choose it again after resizing.
    private func fit(width fitWidth: Bool, height fitHeight: Bool) {
        guard let pdfView, pdf.pageCount > 0,
              let scroll = pdfView.documentView?.enclosingScrollView else { return }
        let current = min(max(currentPage, 0), pdf.pageCount - 1)

        // The pages that sit side by side with the current one.
        var indexes = [current]
        if pdfView.displayMode == .twoUp || pdfView.displayMode == .twoUpContinuous {
            let start = displaysAsBook
                ? (current == 0 ? 0 : (current % 2 == 1 ? current : current - 1))   // the cover stands alone
                : current - current % 2
            indexes = [start]
            if !(displaysAsBook && start == 0), start + 1 < pdf.pageCount { indexes.append(start + 1) }
        }

        let margins = displaysPageBreaks ? pdfView.pageBreakMargins : NSEdgeInsets()
        var width: CGFloat = 0, height: CGFloat = 0
        for index in indexes {
            guard let page = pdf.page(at: index) else { continue }
            var size = page.bounds(for: pdfView.displayBox).size
            if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            width += size.width + margins.left + margins.right
            height = max(height, size.height + margins.top + margins.bottom)
        }
        guard width > 0, height > 0 else { return }

        let available = scroll.contentSize
        let widthScale = available.width / width
        let heightScale = available.height / height
        let scale = fitWidth && fitHeight ? min(widthScale, heightScale) : (fitWidth ? widthScale : heightScale)
        guard scale.isFinite, scale > 0 else { return }

        pdfView.autoScales = false
        pdfView.scaleFactor = scale
        refreshZoom()
        if let page = pdf.page(at: current) { pdfView.go(to: page) }   // bring it back into view
    }
    /// Zoom as shown in the toolbar: 100% is true size, where an inch on the page is an inch on the screen.
    @Published private(set) var zoomPercent = 100

    /// PDFView scale factor at which a page is shown at its true printed size on this window's screen.
    /// (A factor of 1 only means one page point per screen point, which is why 100% looked too small.)
    var actualSizeScale: CGFloat {
        Self.pointsPerInch(of: pdfView?.window?.screen ?? NSScreen.main) / 72
    }

    /// How many screen points make a physical inch, from the display's reported size.
    /// If the display doesn't report a believable size, fall back to the traditional 72.
    private static func pointsPerInch(of screen: NSScreen?) -> CGFloat {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return 72 }
        let display = CGDirectDisplayID(number.uint32Value)
        let millimetres = CGDisplayScreenSize(display).width
        guard millimetres > 0 else { return 72 }
        let ppi = CGDisplayBounds(display).width / (millimetres / 25.4)   // bounds are in points
        return (50...400).contains(ppi) ? ppi : 72
    }

    func setZoomPercent(_ percent: Int) {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = actualSizeScale * CGFloat(percent) / 100
        refreshZoom()
    }

    func zoomActualSize() { setZoomPercent(100) }

    /// Re-read the PDF view's scale (it also changes by itself in fit-to-window mode and on other screens).
    func refreshZoom() {
        guard let pdfView else { return }
        let percent = Int((pdfView.scaleFactor / actualSizeScale * 100).rounded())
        if zoomPercent != percent { zoomPercent = percent }
    }

    // MARK: - Search

    func search(_ text: String) {
        cancelSearch()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        pdf.beginFindString(trimmed, withOptions: [.caseInsensitive])
    }

    func cancelSearch() {
        pdf.cancelFindString()
        if !searchResults.isEmpty || isSearching {
            searchResults = []
            searchIndex = 0
            isSearching = false
            pdfView?.highlightedSelections = nil
            pdfView?.clearSelection()
        }
    }

    fileprivate func foundMatch(_ match: PDFSelection) {
        guard isSearching else { return }
        match.color = NSColor.systemYellow.withAlphaComponent(0.6)
        searchResults.append(match)
        if searchResults.count == 1 { showResult(0) }
        if searchResults.count % 25 == 0 { pdfView?.highlightedSelections = searchResults }
    }

    fileprivate func findFinished() {
        guard isSearching else { return }
        isSearching = false
        pdfView?.highlightedSelections = searchResults
        if searchResults.isEmpty { NSSound.beep() }
    }

    func showResult(_ index: Int) {
        guard searchResults.indices.contains(index) else { return }
        searchIndex = index
        let match = searchResults[index]
        pdfView?.setCurrentSelection(match, animate: true)
        pdfView?.go(to: match)
    }

    func nextResult() {
        guard !searchResults.isEmpty else { return }
        showResult((searchIndex + 1) % searchResults.count)
    }

    func previousResult() {
        guard !searchResults.isEmpty else { return }
        showResult((searchIndex - 1 + searchResults.count) % searchResults.count)
    }

    // MARK: - Quartz filters

    /// Applies a .qfilter to the whole document in memory so the effect is visible before saving.
    /// Undo restores the original; saving writes whatever is on screen.
    func applyQuartzFilter(_ filter: QuartzFilter, name filterName: String) {
        isBusy = true
        // Let the spinner appear before the (blocking) filter run.
        DispatchQueue.main.async { [self] in
            defer { isBusy = false }
            commitBookmarks()
            let options: [AnyHashable: Any] = ["QuartzFilter": filter]
            guard let data = pdf.dataRepresentation(options: options),
                  let filtered = PDFDocument(data: data),
                  filtered.pageCount == pdf.pageCount else {
                presentError("The filter couldn't be applied to this document.")
                return
            }
            let oldPDF = pdf
            // Bookmarks point at page objects, and the filtered copy has new ones: re-anchor by index.
            let remapped = bookmarks.remapped { page in
                guard let page, page.document === oldPDF else { return nil }
                return filtered.page(at: oldPDF.index(for: page))
            }
            // The filtered copy is a new, unencrypted document: carry a known open password over explicitly.
            if security == nil, !opened.hasRestrictions, let password = opened.password {
                security = SecuritySettings(openPassword: password)
            }
            replaceDocument(with: filtered, bookmarks: remapped,
                            name: "Apply \(filterName)")
        }
    }

     func replaceDocument(with newPDF: PDFDocument, bookmarks newMarks: [BookmarkNode], name: String) {
        let oldPDF = pdf
        let oldMarks = bookmarks
        cancelSearch()
        newPDF.delegate = findDelegate
        pdf = newPDF
        bookmarks = newMarks
        selection = selection.filteredIndexSet { $0 < newPDF.pageCount }
        pageRevision += 1
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { store in
                store.replaceDocument(with: oldPDF, bookmarks: oldMarks, name: name)
            }
            undoManager.setActionName(name)
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    // MARK: - Bookmarks (PDF outline)

    private func performBookmarkEdit(_ name: String, _ body: () -> Void) {
        let before = bookmarks
        body()
        registerBookmarkRestore(before, name: name)
    }

    private func registerBookmarkRestore(_ target: [BookmarkNode], name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            let now = store.bookmarks
            store.bookmarks = target
            store.registerBookmarkRestore(now, name: name)
        }
        undoManager.setActionName(name)
    }

    private var selectedBookmarkPath: [Int]? {
        bookmarkSelection.flatMap { bookmarks.path(of: $0) }
    }

    func addBookmark(asChild: Bool, forPage pageIndex: Int? = nil) {
        let index = pageIndex ?? currentPage
        guard let page = pdf.page(at: index) else { return }
        let node = BookmarkNode(title: "Page \(index + 1)", page: page)
        performBookmarkEdit(asChild ? "Add Sub-bookmark" : "Add Bookmark") {
            if let path = selectedBookmarkPath {
                if asChild {
                    let childCount = bookmarks.node(at: path).children.count
                    bookmarks.insertNode(node, at: path + [childCount])
                } else {
                    bookmarks.insertNode(node, at: Array(path.dropLast()) + [path.last! + 1])
                }
            } else {
                bookmarks.append(node)
            }
        }
        bookmarkSelection = node.id
        sidebarTab = .bookmarks
        showSidebar = true
    }

    func deleteSelectedBookmark() {
        guard let path = selectedBookmarkPath else { return }
        performBookmarkEdit("Delete Bookmark") { bookmarks.removeNode(at: path) }
        bookmarkSelection = nil
    }

    func promptRenameSelectedBookmark() {
        guard let path = selectedBookmarkPath else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Bookmark"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = bookmarks.node(at: path).title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        performBookmarkEdit("Rename Bookmark") {
            bookmarks.mutateNode(at: path) { $0.title = title }
        }
    }

    func setSelectedBookmarkDestinationToCurrentPage() {
        guard let path = selectedBookmarkPath, let page = pdf.page(at: currentPage) else { return }
        performBookmarkEdit("Set Bookmark Destination") {
            bookmarks.mutateNode(at: path) { $0.page = page }
        }
    }

    /// Make the bookmark a child of the sibling above it.
    func indentSelectedBookmark() {
        guard let path = selectedBookmarkPath, let index = path.last, index > 0 else { return }
        performBookmarkEdit("Indent Bookmark") {
            let node = bookmarks.removeNode(at: path)
            let newParent = Array(path.dropLast()) + [index - 1]
            let position = bookmarks.node(at: newParent).children.count
            bookmarks.insertNode(node, at: newParent + [position])
        }
    }

    /// Move the bookmark up a level, to just after its parent.
    func outdentSelectedBookmark() {
        guard let path = selectedBookmarkPath, path.count >= 2 else { return }
        performBookmarkEdit("Outdent Bookmark") {
            let node = bookmarks.removeNode(at: path)
            let parent = Array(path.dropLast())
            bookmarks.insertNode(node, at: Array(parent.dropLast()) + [parent.last! + 1])
        }
    }

    func moveSelectedBookmark(by offset: Int) {
        guard let path = selectedBookmarkPath, let index = path.last else { return }
        let target = index + offset
        guard target >= 0, target < bookmarks.siblingCount(at: path) else { return }
        performBookmarkEdit(offset < 0 ? "Move Bookmark Up" : "Move Bookmark Down") {
            let node = bookmarks.removeNode(at: path)
            bookmarks.insertNode(node, at: Array(path.dropLast()) + [target])
        }
    }

    func goToBookmark(_ id: UUID) {
        guard let path = bookmarks.path(of: id) else { return }
        let node = bookmarks.node(at: path)
        guard let page = node.page, page.document === pdf else { return }
        pdfView?.go(to: page)
    }

    func pageNumber(for node: BookmarkNode) -> Int? {
        guard let page = node.page, page.document === pdf else { return nil }
        let index = pdf.index(for: page)
        return index == NSNotFound ? nil : index + 1
    }

    // MARK: Outline <-> bookmark tree

    private nonisolated static func readOutline(_ outline: PDFOutline) -> [BookmarkNode] {
        (0..<outline.numberOfChildren).compactMap { outline.child(at: $0) }.map { child in
            let page = child.destination?.page ?? (child.action as? PDFActionGoTo)?.destination.page
            return BookmarkNode(title: child.label ?? "Untitled", page: page, children: readOutline(child))
        }
    }

    private func buildOutline(_ marks: [BookmarkNode]? = nil, in document: PDFDocument? = nil) -> PDFOutline? {
        let marks = marks ?? bookmarks
        let target = document ?? pdf
        guard !marks.isEmpty else { return nil }
        func add(_ nodes: [BookmarkNode], to parent: PDFOutline) {
            for (i, node) in nodes.enumerated() {
                let item = PDFOutline()
                item.label = node.title
                if let page = node.page, page.document === target {
                    let box = page.bounds(for: .cropBox)
                    item.destination = PDFDestination(page: page, at: CGPoint(x: box.minX, y: box.maxY))
                }
                parent.insertChild(item, at: i)
                add(node.children, to: item)
            }
        }
        let root = PDFOutline()
        add(marks, to: root)
        return root
    }

    /// Write the bookmark tree into the PDF so it's included when the document is saved.
    func commitBookmarks() {
        pdf.outlineRoot = buildOutline()
    }
}

// MARK: - Search delegate

/// PDFKit reports find results through PDFDocumentDelegate, which must be an NSObject.
final class FindDelegate: NSObject, PDFDocumentDelegate {
    weak var store: DocumentStore?

    func didMatchString(_ instance: PDFSelection) {
        guard let copy = instance.copy() as? PDFSelection else { return }
        DispatchQueue.main.async { [weak self] in self?.store?.foundMatch(copy) }
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.store?.findFinished() }
    }
}
