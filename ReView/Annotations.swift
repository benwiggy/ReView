import AppKit
import PDFKit
import SwiftUI

// MARK: - Tools and colours

enum MarkupTool: Int, CaseIterable, Identifiable {
    case select, highlight, underline, strikeOut, note, text, rectangle, oval, line
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikeOut: return "Strikethrough"
        case .note: return "Note"
        case .text: return "Text"
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .line: return "Line"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikeOut: return "strikethrough"
        case .note: return "note.text"
        case .text: return "textbox"
        case .rectangle: return "rectangle"
        case .oval: return "circle"
        case .line: return "line.diagonal"
        }
    }

    /// Tools that are used by dragging out a box or line on the page.
    var createsByDragging: Bool {
        self == .text || self == .rectangle || self == .oval || self == .line
    }

    /// The tools that mark up selected text.
    var isTextMarkup: Bool { self == .highlight || self == .underline || self == .strikeOut }

    var subtype: PDFAnnotationSubtype? {
        switch self {
        case .select, .note, .text, .rectangle, .oval, .line: return nil
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        }
    }

    var markupType: PDFMarkupType {
        switch self {
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        default: return .highlight
        }
    }
}

enum MarkupColor: Int, CaseIterable, Identifiable {
    case yellow, green, blue, pink, orange, purple
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .purple: return "Purple"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.90, blue: 0.10, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.40, green: 0.85, blue: 0.35, alpha: 1)
        case .blue:   return NSColor(srgbRed: 0.35, green: 0.70, blue: 1.00, alpha: 1)
        case .pink:   return NSColor(srgbRed: 1.00, green: 0.45, blue: 0.70, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.62, blue: 0.15, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.70, green: 0.50, blue: 0.95, alpha: 1)
        }
    }
}

enum TextColor: Int, CaseIterable, Identifiable {
    case black, red, blue, green, orange, gray, white
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .black: return "Black"
        case .red: return "Red"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .gray: return "Gray"
        case .white: return "White"
        }
    }
    var nsColor: NSColor {
        switch self {
        case .black:  return .black
        case .red:    return NSColor(srgbRed: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        case .blue:   return NSColor(srgbRed: 0.10, green: 0.30, blue: 0.85, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.10, green: 0.55, blue: 0.20, alpha: 1)
        case .orange: return NSColor(srgbRed: 0.95, green: 0.50, blue: 0.05, alpha: 1)
        case .gray:   return .darkGray
        case .white:  return .white
        }
    }
}

enum TextFonts {
    /// Every installed font family.
    static let names: [String] = NSFontManager.shared.availableFontFamilies
    static let sizes: [Double] = [9, 10, 12, 14, 18, 24, 36, 48, 72]
}

struct PlacedAnnotation {
    let page: PDFPage
    let annotation: PDFAnnotation
}

/// One line of the Annotations list.
struct AnnotationRow: Identifiable {
    let page: PDFPage
    let pageIndex: Int
    let annotation: PDFAnnotation
    /// Stable across refreshes (PDFKit may hand back new objects), so the list keeps its selection.
    var id: String {
        let b = annotation.bounds
        return "\(pageIndex)|\(Self.rawType(annotation))|\(Int(b.minX.rounded())),\(Int(b.minY.rounded())),\(Int(b.width.rounded())),\(Int(b.height.rounded()))"
    }

    /// "Highlight", "Note", … (PDFKit's subtype names, tidied up).
    var kind: String {
        switch Self.rawType(annotation) {
        case "highlight": return "Highlight"
        case "underline": return "Underline"
        case "strikeout": return "Strikethrough"
        case "text": return "Note"
        case "freetext": return "Text Box"
        case "square": return "Rectangle"
        case "circle": return "Oval"
        case "line": return "Line"
        case "ink": return "Drawing"
        case "stamp": return "Stamp"
        default: return annotation.type ?? "Annotation"
        }
    }

    var symbol: String {
        switch Self.rawType(annotation) {
        case "highlight": return "highlighter"
        case "underline": return "underline"
        case "strikeout": return "strikethrough"
        case "text": return "note.text"
        case "freetext": return "textbox"
        case "square": return "rectangle"
        case "circle": return "circle"
        case "line": return "line.diagonal"
        case "ink": return "scribble"
        case "stamp": return "signature"
        default: return "pencil.tip"
        }
    }

    /// The note typed on this annotation (for a highlight it is the highlight's own comment, not a separate object).
    var note: String {
        if Self.rawType(annotation) == "freetext" { return "" }
        return annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// For text markup, the words it covers.
    var quote: String {
        if Self.rawType(annotation) == "freetext" {
            return annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard ["highlight", "underline", "strikeout"].contains(Self.rawType(annotation)),
              let text = page.selection(for: annotation.bounds)?.string?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "" }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    /// PDFKit reports "Highlight" on some systems and "/Highlight" on others.
    static func rawType(_ annotation: PDFAnnotation) -> String {
        (annotation.type ?? "").replacingOccurrences(of: "/", with: "").lowercased()
    }

    /// What the Annotations list shows: highlights, underlines, strikethroughs and notes. Like Preview, text boxes,
    /// shapes and drawings are left out.
    static func isListed(_ annotation: PDFAnnotation) -> Bool {
        ["highlight", "underline", "strikeout", "text"].contains(rawType(annotation))
    }

    /// Links, form fields and the pop-ups PDFKit attaches to notes aren't "annotations" to the user.
    static func isMarkup(_ annotation: PDFAnnotation) -> Bool {
        !["link", "widget", "popup", ""].contains(rawType(annotation))
    }
}

// MARK: - Store: annotation edits (all undoable)

extension DocumentStore {

    /// The file forbids commenting (set by its owner password); the tools stay off.
    var canComment: Bool { !commentingRestricted }

    var hasTextSelection: Bool {
        guard let text = pdfView?.currentSelection?.string else { return false }
        return !text.isEmpty
    }

    func markupSelection(_ tool: MarkupTool) {
        guard let selection = pdfView?.currentSelection, hasTextSelection else { return }
        applyMarkup(tool, to: selection)
        pdfView?.clearSelection()
    }

    /// One annotation per page covered by the selection, with one quadrilateral per line.
    func applyMarkup(_ tool: MarkupTool, to selection: PDFSelection) {
        guard let subtype = tool.subtype, canComment else { return }

        var rects: [PDFPage: [CGRect]] = [:]
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let rect = line.bounds(for: page)
                if rect.width > 0, rect.height > 0 { rects[page, default: []].append(rect) }
            }
        }

        var placed: [PlacedAnnotation] = []
        for page in rects.keys.sorted(by: { pdf.index(for: $0) < pdf.index(for: $1) }) {
            guard let lines = rects[page], let first = lines.first else { continue }
            let union = lines.dropFirst().reduce(first) { $0.union($1) }

            let annotation = PDFAnnotation(bounds: union, forType: subtype, withProperties: nil)
            annotation.markupType = tool.markupType
            annotation.color = tool == .highlight ? markupColor.nsColor.withAlphaComponent(0.55) : markupColor.nsColor
            annotation.userName = authorName
            annotation.modificationDate = Date()
            // Corner points are relative to the annotation's own origin: top-left, top-right, bottom-left, bottom-right.
            annotation.quadrilateralPoints = lines.flatMap { rect -> [NSValue] in
                let x = rect.minX - union.minX, y = rect.minY - union.minY
                return [NSValue(point: CGPoint(x: x, y: y + rect.height)),
                        NSValue(point: CGPoint(x: x + rect.width, y: y + rect.height)),
                        NSValue(point: CGPoint(x: x, y: y)),
                        NSValue(point: CGPoint(x: x + rect.width, y: y))]
            }
            placed.append(PlacedAnnotation(page: page, annotation: annotation))
        }
        guard !placed.isEmpty else { return }
        addAnnotations(placed, name: tool.title)
    }

    func addAnnotations(_ items: [PlacedAnnotation], name: String) {
        for item in items {
            item.page.addAnnotation(item.annotation)
            // A note on a highlight has a pop-up of its own; put it back too.
            if let popup = item.annotation.popup, !item.page.annotations.contains(where: { $0 === popup }) {
                item.page.addAnnotation(popup)
            }
            pdfView?.annotationsChanged(on: item.page)
        }
        annotationRevision += 1
        // The new annotation becomes the selected row (without scrolling the page to it).
        if let last = items.last, AnnotationRow.isListed(last.annotation) {
            let id = AnnotationRow(page: last.page, pageIndex: pdf.index(for: last.page), annotation: last.annotation).id
            suppressRevealFor = id
            selectedAnnotationID = id
        }
        undoManager?.registerUndo(withTarget: self) { $0.removeAnnotations(items, name: name) }
        undoManager?.setActionName(name)
    }

    func removeAnnotations(_ items: [PlacedAnnotation], name: String) {
        for item in items {
            if let popup = item.annotation.popup { item.page.removeAnnotation(popup) }
            item.page.removeAnnotation(item.annotation)
            pdfView?.annotationsChanged(on: item.page)
        }
        annotationRevision += 1
        if let selected = selectedMarkup, items.contains(where: { $0.annotation === selected.annotation }) {
            selectedMarkup = nil
        }
        undoManager?.registerUndo(withTarget: self) { $0.addAnnotations(items, name: name) }
        undoManager?.setActionName(name)
    }

    func deleteAnnotation(_ row: AnnotationRow) {
        guard canComment else { NSSound.beep(); return }
        removeAnnotations([PlacedAnnotation(page: row.page, annotation: row.annotation)], name: "Delete \(row.kind)")
    }

    func deleteSelectedAnnotation() {
        if let item = selectedMarkup {
            guard canComment else { NSSound.beep(); return }
            removeAnnotations([item], name: "Delete Annotation")
            return
        }
        guard let id = selectedAnnotationID, let row = annotationRows().first(where: { $0.id == id }) else {
            NSSound.beep(); return
        }
        deleteAnnotation(row)
    }

    /// Opens a note editor at a click. The note is only added to the page (one undo step) if some text is typed.
    func placeNote(on page: PDFPage, at point: CGPoint, in view: PDFView) {
        guard canComment else { return }
        let size: CGFloat = 24
        let box = page.bounds(for: .cropBox)
        let origin = CGPoint(x: min(max(point.x, box.minX), box.maxX - size),
                             y: min(max(point.y - size, box.minY), box.maxY - size))
        let annotation = VectorNoteAnnotation(bounds: CGRect(origin: origin, size: CGSize(width: size, height: size)),
                                              forType: .text, withProperties: nil)
        annotation.color = markupColor.nsColor
        annotation.userName = authorName
        annotation.modificationDate = Date()

        let anchor = view.convert(annotation.bounds, from: page)
        DispatchQueue.main.async { [weak self, weak view] in
            guard let view else { return }
            NoteEditor.shared.show(text: "", near: anchor, in: view) { text in
                guard let self, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                annotation.contents = text
                self.addAnnotations([PlacedAnnotation(page: page, annotation: annotation)], name: "Add Note")
            }
        }
    }

    /// Draws a text box from a drag (or a click: a default-sized box) and opens the editor.
    /// Like notes, it is only added (one undo step) if some text is typed.
    func placeTextBox(on page: PDFPage, from start: CGPoint, to end: CGPoint?, in view: PDFView) {
        guard canComment else { return }
        var rect: CGRect
        if let end, abs(end.x - start.x) >= 30, abs(end.y - start.y) >= 16 {
            rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        } else {
            rect = CGRect(x: start.x, y: start.y - 60, width: 200, height: 60)
        }
        let box = page.bounds(for: .cropBox)
        rect.size.width = min(rect.width, box.width)
        rect.size.height = min(rect.height, box.height)
        rect.origin.x = min(max(rect.minX, box.minX), box.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, box.minY), box.maxY - rect.height)

        let defaults = UserDefaults.standard
        let size = defaults.double(forKey: "textFontSize")
        let pointSize = CGFloat(size > 0 ? size : 14)
        let font = TextFonts.font(family: defaults.string(forKey: "textFontName") ?? "Helvetica", size: pointSize,
                                  bold: defaults.bool(forKey: "textBold"), italic: defaults.bool(forKey: "textItalic"))
        let color = StoredColor.color(defaults.string(forKey: "textColorHex"), fallback: .black)

        let annotation = VectorTextAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        annotation.setRotation(page.rotation)   // reads upright now; turns with the page if it's rotated later
        annotation.font = font
        annotation.fontColor = color
        annotation.color = .clear
        annotation.alignment = .left
        annotation.border = nil
        annotation.userName = authorName
        annotation.modificationDate = Date()

        let anchor = view.convert(rect, from: page)
        DispatchQueue.main.async { [weak self, weak view] in
            guard let view else { return }
            NoteEditor.shared.show(text: "", near: anchor, in: view) { text in
                guard let self, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                annotation.contents = text
                self.addAnnotations([PlacedAnnotation(page: page, annotation: annotation)], name: "Add Text Box")
            }
        }
    }

    /// Add Note from the menu: beside the selected text if there is any, otherwise in the middle of the view.
    func addNoteNearSelectionOrCentre() {
        guard canComment, let view = pdfView else { return }
        if hasTextSelection, let selection = view.currentSelection,
           let line = selection.selectionsByLine().first, let page = line.pages.first {
            let rect = line.bounds(for: page)
            view.clearSelection()
            placeNote(on: page, at: CGPoint(x: rect.minX - 28, y: rect.maxY), in: view)
            return
        }
        let centre = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        guard let page = view.page(for: centre, nearest: true) else { return }
        placeNote(on: page, at: view.convert(centre, to: page), in: view)
    }

    /// Edits the note on any annotation (a sticky note's text, or the comment on a highlight).
    func editNote(_ item: PlacedAnnotation) {
        guard canComment, let view = pdfView else { return }
        let old = item.annotation.contents ?? ""
        let anchor = view.convert(item.annotation.bounds, from: item.page)
        DispatchQueue.main.async { [weak self, weak view] in
            guard let view else { return }
            NoteEditor.shared.show(text: old, near: anchor, in: view) { text in
                self?.setNoteText(text, for: item, old: old)
            }
        }
    }

    func setNoteText(_ text: String, for item: PlacedAnnotation, old: String) {
        guard text != old else { return }
        item.annotation.contents = text
        item.annotation.modificationDate = Date()
        pdfView?.annotationsChanged(on: item.page)
        annotationRevision += 1
        undoManager?.registerUndo(withTarget: self) { $0.setNoteText(old, for: item, old: text) }
        undoManager?.setActionName("Edit Note")
    }

    /// Every user-visible annotation, in page order.
    func annotationRows() -> [AnnotationRow] {
        var rows: [AnnotationRow] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            for annotation in page.annotations where AnnotationRow.isListed(annotation) {
                rows.append(AnnotationRow(page: page, pageIndex: index, annotation: annotation))
            }
        }
        return rows
    }

    /// PDFKit's own commands (such as Add Note on the right-click menu) change annotations without telling us,
    /// so after clicks, keys and closed menus the Annotations list is refreshed a moment later.
    func scheduleAnnotationRefresh() {
        guard showSidebar, sidebarTab == .annotations else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.annotationRevision += 1
        }
    }

    func reveal(_ row: AnnotationRow) {
        guard let pdfView else { return }
        pdfView.go(to: row.annotation.bounds.insetBy(dx: -40, dy: -40), on: row.page)
    }
}

// MARK: - Note editor

/// A small popover with a text box. `commit` gets the text when the popover closes.
final class NoteEditor: NSObject, NSPopoverDelegate {
    static let shared = NoteEditor()
    private var popover: NSPopover?
    private var textView: NSTextView?
    private var commit: ((String) -> Void)?

    func show(text: String, near rect: CGRect, in view: NSView, commit: @escaping (String) -> Void) {
        finish()

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 150))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = NSTextView(frame: scroll.bounds)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scroll.documentView = textView

        let controller = NSViewController()
        controller.view = scroll
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self

        self.popover = popover
        self.textView = textView
        self.commit = commit
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        popover.contentViewController?.view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    /// Closes any open editor, delivering its text.
    private func finish() {
        guard let popover else { return }
        let text = textView?.string ?? ""
        let deliver = commit
        self.popover = nil; textView = nil; commit = nil
        popover.delegate = nil
        popover.close()
        deliver?(text)
    }

    func popoverDidClose(_ notification: Notification) { finish() }
}

// MARK: - The PDF view

/// PDFView; also the home of the Highlight / Underline / Strikethrough context-menu items.
final class MarkupPDFView: PDFView {
    weak var store: DocumentStore?
    private static let menuTag = 7001

    /// Where the last right-click landed on a page, for "Add Note Here".
    static var contextNoteSpot: (page: PDFPage, point: CGPoint)?

    /// Adds an "Annotate" submenu at the end of `menu` (after PDFKit's own items), replacing any earlier copy.
    static func addMarkupItems(to menu: NSMenu, hasSelection: Bool) {
        for old in menu.items where old.tag == menuTag { menu.removeItem(old) }

        let submenu = NSMenu(title: "Annotate")
        if hasSelection {
            submenu.addItem(NSMenuItem(title: "Highlight", action: #selector(DocumentWindowController.highlightSelection(_:)), keyEquivalent: ""))
            submenu.addItem(NSMenuItem(title: "Underline", action: #selector(DocumentWindowController.underlineSelection(_:)), keyEquivalent: ""))
            submenu.addItem(NSMenuItem(title: "Strikethrough", action: #selector(DocumentWindowController.strikeOutSelection(_:)), keyEquivalent: ""))
            submenu.addItem(.separator())
        }
        submenu.addItem(NSMenuItem(title: "Add Note Here", action: #selector(DocumentWindowController.addNoteHere(_:)), keyEquivalent: ""))

        let host = NSMenuItem(title: "Annotate", action: nil, keyEquivalent: "")
        host.submenu = submenu
        host.tag = menuTag
        if let last = menu.items.last, !last.isSeparatorItem {
            let separator = NSMenuItem.separator()
            separator.tag = menuTag
            menu.addItem(separator)
        }
        menu.addItem(host)
    }
}

/// Listens to events for one PDF view (PDFView's mouse handling lives in an inner view that a subclass never sees):
/// - while a markup tool is active, releasing the mouse after selecting text marks it up, and Escape returns to Select;
/// - right-clicking selected text shows PDFKit's own menu with the markup commands added;
/// - clicks, keys and closed menus schedule a refresh of the Annotations list.
final class MarkupEventMonitor {
    private var monitor: Any?
    private var menuObserver: NSObjectProtocol?
    private var scaleObserver: NSObjectProtocol?
    private let selection: MarkupSelectionHandler
    private static var dragStart: (page: PDFPage, point: CGPoint)?
    private static var dragStartView: CGPoint?

    init(view: PDFView, store: DocumentStore) {
        let selection = MarkupSelectionHandler(view: view, store: store)
        self.selection = selection
        let kinds: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .keyUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: kinds) { [weak view, weak store] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                guard let view, let store, event.window != nil, event.window === view.window else { return }
                let point = view.convert(event.locationInWindow, from: nil)
                let inside = view.bounds.contains(point)

                switch event.type {
                case .rightMouseDown, .leftMouseDown:
                    let isContextClick = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
                    if isContextClick {
                        if inside, Self.showMarkupMenu(in: view, store: store, event: event, at: point) { result = nil }
                    } else if inside, store.canComment,
                              store.markupTool.createsByDragging
                                || event.modifierFlags.intersection([.command, .option, .shift]).isEmpty {
                        if store.markupTool.createsByDragging {
                            // The box or line is made when the mouse is released.
                            if let spot = Self.pageLocation(at: point, in: view) {
                                Self.dragStart = spot
                                Self.dragStartView = point
                                result = nil
                            }
                        } else if store.markupTool == .note, let spot = Self.pageLocation(at: point, in: view) {
                            store.placeNote(on: spot.page, at: spot.point, in: view)
                            store.markupTool = .select
                            result = nil
                        } else if store.markupTool == .select, selection.mouseDown(event: event, at: point) {
                            result = nil          // selected, started moving, or edited a note
                        }
                    }
                case .keyDown:
                    if event.keyCode == 53 {   // Escape
                        if store.markupTool != .select {
                            store.markupTool = .select
                            result = nil
                        } else if store.selectedMarkup != nil {
                            store.selectedMarkup = nil
                            result = nil
                        }
                    }
                case .leftMouseDragged:
                    if selection.mouseDragged(at: point, shift: event.modifierFlags.contains(.shift)) {
                        result = nil
                    } else if store.markupTool.createsByDragging, let start = Self.dragStartView {
                        let tool = store.markupTool
                        let end = event.modifierFlags.contains(.shift)
                            ? ShapeConstraint.apply(tool, from: start, to: point) : point
                        selection.rubber = RubberBand(tool: tool, from: start, to: end)
                        result = nil
                    }
                case .leftMouseUp:
                    if selection.mouseUp(at: point) {
                        result = nil
                    } else if store.markupTool.createsByDragging, let start = Self.dragStart {
                        Self.dragStart = nil
                        Self.dragStartView = nil
                        selection.rubber = nil
                        let tool = store.markupTool
                        if tool == .text {
                            let end = Self.pageLocation(at: point, in: view)
                            store.placeTextBox(on: start.page, from: start.point,
                                               to: end?.page === start.page ? end?.point : nil, in: view)
                        } else {
                            // The end may be off the page; it is clamped to the page where the shape starts.
                            var end = view.convert(point, to: start.page)
                            if event.modifierFlags.contains(.shift) {
                                end = ShapeConstraint.apply(tool, from: start.point, to: end)
                            }
                            store.placeShape(tool, on: start.page, from: start.point, to: end, in: view)
                        }
                        store.markupTool = .select
                        result = nil
                    } else if inside, store.markupTool.isTextMarkup {
                        // After PDFView has finished with the click, so the selection is final.
                        DispatchQueue.main.async { [weak store] in
                            guard let store, store.markupTool.isTextMarkup, store.canComment, store.hasTextSelection else { return }
                            store.markupSelection(store.markupTool)
                        }
                    }
                    store.scheduleAnnotationRefresh()
                case .keyUp:
                    store.scheduleAnnotationRefresh()
                default:
                    break
                }
            }
            return result
        }

        scaleObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged, object: view, queue: .main
        ) { _ in
            MainActor.assumeIsolated { selection.scaleChanged() }
        }

        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak store] _ in
            MainActor.assumeIsolated { store?.scheduleAnnotationRefresh() }
        }
    }

    /// Pops up PDFKit's own context menu with an Annotate submenu added at the end. Returns false (do nothing)
    /// when the click is on an existing annotation, which keeps PDFKit's menu (with its Add Note).
    private static func showMarkupMenu(in view: PDFView, store: DocumentStore, event: NSEvent, at point: CGPoint) -> Bool {
        guard store.canComment, let documentView = view.documentView else { return false }
        MarkupPDFView.contextNoteSpot = nil
        if let page = view.page(for: point, nearest: false) {
            let pagePoint = view.convert(point, to: page)
            if let annotation = page.annotation(at: pagePoint), AnnotationRow.isMarkup(annotation) { return false }
            MarkupPDFView.contextNoteSpot = (page, pagePoint)
        }
        let hasSelection = store.hasTextSelection

        // Shown on the next pass of the run loop rather than inside the event monitor.
        DispatchQueue.main.async { [weak view, weak documentView] in
            guard let view, let documentView else { return }
            let menu = nativeMenu(for: event, in: view) ?? {
                // PDFKit gave us nothing to build on: at least keep Copy.
                let fallback = NSMenu()
                fallback.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
                return fallback
            }()
            MarkupPDFView.addMarkupItems(to: menu, hasSelection: hasSelection)
            NSMenu.popUpContextMenu(menu, with: event, for: documentView)
        }
        return true
    }

    private static func pageLocation(at point: CGPoint, in view: PDFView) -> (page: PDFPage, point: CGPoint)? {
        guard let page = view.page(for: point, nearest: false) else { return nil }
        return (page, view.convert(point, to: page))
    }

    /// PDFKit's own context menu, asked of the view under the mouse and then of each view above it up to the PDFView.
    private static func nativeMenu(for event: NSEvent, in view: PDFView) -> NSMenu? {
        var candidates: [NSView] = []
        var hit = view.window?.contentView?.hitTest(event.locationInWindow)
        while let current = hit {
            candidates.append(current)
            if current === view { break }
            hit = current.superview
        }
        if let documentView = view.documentView, !candidates.contains(where: { $0 === documentView }) {
            candidates.append(documentView)
        }
        if !candidates.contains(where: { $0 === view }) { candidates.append(view) }
        for candidate in candidates {
            if let menu = candidate.menu(for: event), menu.numberOfItems > 0 { return menu }
        }
        return nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) }
    }
}

// MARK: - Markup strip

struct MarkupStrip: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MarkupTool.allCases) { tool in
                if tool == .highlight || tool == .note || tool == .rectangle {
                    Divider().frame(height: 18).padding(.horizontal, 4)
                }
                Button { store.markupTool = tool } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(store.markupTool == tool ? Color.accentColor.opacity(0.28) : .clear)
                        )
                }
                .buttonStyle(.borderless)
                .help(tool == .select ? "Select (Esc)"
                      : tool == .note ? "Note — click the page to add one"
                      : tool == .text ? "Text — drag on the page to draw a box, or click"
                      : tool.createsByDragging ? "\(tool.title) — drag on the page"
                      : "\(tool.title) — stays on until you press Esc")
                .disabled(tool != .select && !store.canComment)
            }

            Divider().frame(height: 18).padding(.horizontal, 6)

            if store.markupTool == .text {
                TextOptions()
            } else if store.markupTool == .rectangle || store.markupTool == .oval {
                ShapeDefaultsOptions(showsFill: true)
            } else if store.markupTool == .line {
                ShapeDefaultsOptions(showsFill: false)
            } else if [.highlight, .underline, .strikeOut, .note].contains(store.markupTool) {
            ForEach(MarkupColor.allCases) { color in
                Button { store.markupColor = color } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(.primary.opacity(store.markupColor == color ? 0.8 : 0.15),
                                                       lineWidth: store.markupColor == color ? 2 : 1))
                }
                .buttonStyle(.borderless)
                .help(color.title)
            }
            }

            if store.markupTool != .select {
                // The options above belong to the active tool.
            } else if let item = store.selectedMarkup, AnnotationRow.rawType(item.annotation) == "freetext" {
                Divider().frame(height: 18).padding(.horizontal, 6)
                SelectedTextOptions(store: store, item: item)
            } else if let item = store.selectedMarkup, ["square", "circle", "line"].contains(AnnotationRow.rawType(item.annotation)) {
                Divider().frame(height: 18).padding(.horizontal, 6)
                SelectedShapeOptions(store: store, item: item)
            }

            Spacer()

            if !store.canComment {
                Label("This document doesn’t allow comments", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

/// Font, size and colour for the next text box (remembered between launches).
struct TextOptions: View {
    @AppStorage("textFontName") private var fontName = "Helvetica"
    @AppStorage("textFontSize") private var fontSize = 14.0
    @AppStorage("textColorHex") private var colorHex = "000000FF"
    @AppStorage("textBold") private var bold = false
    @AppStorage("textItalic") private var italic = false

    var body: some View {
        HStack(spacing: 8) {
            Picker("Font", selection: $fontName) {
                ForEach(TextFonts.names, id: \.self) { Text($0).tag($0) }
            }
            .fixedSize()
            Picker("Size", selection: $fontSize) {
                ForEach(TextFonts.sizes, id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
            .fixedSize()
            ColorPicker("Colour", selection: Binding(
                get: { Color(nsColor: StoredColor.color(colorHex, fallback: .black)) },
                set: { colorHex = StoredColor.hex(StoredColor.ns($0)) }), supportsOpacity: false)
            Toggle(isOn: $bold) { Image(systemName: "bold") }.toggleStyle(.button)
            Toggle(isOn: $italic) { Image(systemName: "italic") }.toggleStyle(.button)
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Annotations list (sidebar)

struct AnnotationsView: View {
    @ObservedObject var store: DocumentStore
    @State private var rows: [AnnotationRow] = []

    var body: some View {
        Group {
            if rows.isEmpty {
                VStack {
                    Spacer()
                    Text("No Annotations").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(rows, selection: $store.selectedAnnotationID) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: row.symbol)
                            .foregroundStyle(Color(nsColor: row.annotation.color))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            if !row.quote.isEmpty { Text(row.quote).lineLimit(2) }
                            if !row.note.isEmpty {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Image(systemName: "text.bubble")
                                    Text(row.note).lineLimit(3)
                                }
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            }
                            if row.quote.isEmpty && row.note.isEmpty { Text(row.kind) }
                            Text(detail(row)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // A new row is selected by the change below; clicking the selected row again shows it again.
                        if store.selectedAnnotationID == row.id { store.reveal(row) } else { store.selectedAnnotationID = row.id }
                    }
                    .contextMenu {
                        Button("Edit Note…") {
                            store.reveal(row)
                            store.editNote(PlacedAnnotation(page: row.page, annotation: row.annotation))
                        }
                        .disabled(!store.canComment)
                        Button("Delete") { store.deleteAnnotation(row) }
                            .disabled(!store.canComment)
                    }
                    .tag(row.id)
                }
                .listStyle(.sidebar)
                .onChange(of: store.selectedAnnotationID) { _, id in
                    if id != nil { store.selectedMarkup = nil }
                    if id != nil, id == store.suppressRevealFor { store.suppressRevealFor = nil; return }
                    if let id, let row = rows.first(where: { $0.id == id }) { store.reveal(row) }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: store.annotationRevision) { _, _ in reload() }
        .onChange(of: store.pageRevision) { _, _ in reload() }
        .onChange(of: store.pdf) { _, _ in reload() }
    }

    private func detail(_ row: AnnotationRow) -> String {
        var parts = ["Page \(row.pageIndex + 1)"]
        if let author = row.annotation.userName, !author.isEmpty { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        rows = store.annotationRows()
        if let selected = store.selectedAnnotationID, !rows.contains(where: { $0.id == selected }) {
            store.selectedAnnotationID = nil
        }
    }
}
