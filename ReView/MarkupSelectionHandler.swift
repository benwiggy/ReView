import AppKit
import Combine
import PDFKit
import SwiftUI

// MARK: - Selecting, moving and resizing markup on the page

/// PDFKit has no selection for annotations, so this adds it: click a text box (later also shapes, lines,
/// drawings) with the Select tool to select it, drag it to move it, drag a handle to resize it,
/// double-click a text box to edit its text, press Delete to remove it, Esc to deselect.
/// Receives mouse events from MarkupEventMonitor, in the PDF view's coordinates.
final class MarkupSelectionHandler {

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }       // top = larger y on the page
        var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
        var isCorner: Bool { (movesLeft || movesRight) && (movesTop || movesBottom) }
    }

    private enum Mode { case move, resize(Handle), lineEnd(isStart: Bool) }
    private struct Drag {
        let mode: Mode
        let item: PlacedAnnotation
        let start: CGPoint        // page coordinates
        let original: CGRect
        let originalEnds: (start: CGPoint, end: CGPoint)?   // lines only
    }

    /// The kinds of annotation that can be selected and moved.
    static let selectable: Set<String> = ["freetext", "square", "circle", "line", "ink", "stamp"]

    let overlay = SelectionOverlayView()
    private weak var view: PDFView?
    private weak var store: DocumentStore?
    private var drag: Drag?
    private var selectionSink: AnyCancellable?
    private var observedClip: NSClipView?
    private var clipObserver: NSObjectProtocol?
    private var renderWork: DispatchWorkItem?

    /// The box or line being dragged out with a creation tool, in the PDF view's coordinates.
    var rubber: RubberBand? {
        didSet { overlay.needsDisplay = true }
    }

    init(view: PDFView, store: DocumentStore) {
        self.view = view
        self.store = store
        overlay.handler = self
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
        selectionSink = store.$selectedMarkup
            .receive(on: DispatchQueue.main)
            .sink { [weak overlay] _ in overlay?.needsDisplay = true }
        // Once the view has its scroll view: follow scrolling, and swap in vector-drawing annotations.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.watchScrolling()
            self?.viewChanged()
        }
    }

    deinit {
        overlay.removeFromSuperview()
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
    }

    // MARK: Mouse

    /// Returns true if the click was used (the PDF view must not see it).
    func mouseDown(event: NSEvent, at point: CGPoint) -> Bool {
        guard let view, let store else { return false }
        watchScrolling()

        if let item = store.selectedMarkup, item.page.document != nil {
            if AnnotationRow.rawType(item.annotation) == "line" {
                if let isStart = lineEnd(at: point, of: item, in: view) {
                    begin(.lineEnd(isStart: isStart), item, at: point, in: view)
                    return true
                }
            } else if let handle = handle(at: point, of: item, in: view) {
                begin(.resize(handle), item, at: point, in: view)
                return true
            }
        }

        guard let page = view.page(for: point, nearest: false) else { deselect(); return false }
        let pagePoint = view.convert(point, to: page)
        guard let annotation = page.annotation(at: pagePoint) else { deselect(); return false }

        let raw = AnnotationRow.rawType(annotation)
        let item = PlacedAnnotation(page: page, annotation: annotation)

        if raw == "text" {                       // a sticky note: click to edit
            store.selectedMarkup = nil
            store.editNote(item)
            return true
        }
        guard Self.selectable.contains(raw) else { deselect(); return false }

        store.selectedMarkup = item
        if event.clickCount >= 2, raw == "freetext" {
            store.editNote(item)
            return true
        }
        begin(.move, item, at: point, in: view)
        return true
    }

    /// `shift`: keep a corner resize in proportion, or snap a line end to 45°.
    func mouseDragged(at point: CGPoint, shift: Bool) -> Bool {
        guard let drag, let view else { return false }
        let page = drag.item.page
        let current = view.convert(point, to: page)
        let box = page.bounds(for: .cropBox)
        let dx = current.x - drag.start.x, dy = current.y - drag.start.y
        var rect = drag.original

        switch drag.mode {
        case .lineEnd(let isStart):
            guard let ends = drag.originalEnds else { return true }
            var target = current
            if shift {
                target = ShapeConstraint.apply(.line, from: isStart ? ends.end : ends.start, to: current)
            }
            let spot = CGPoint(x: min(max(target.x, box.minX), box.maxX), y: min(max(target.y, box.minY), box.maxY))
            LineGeometry.set(drag.item.annotation, from: isStart ? spot : ends.start, to: isStart ? ends.end : spot)
            view.annotationsChanged(on: page)
            overlay.needsDisplay = true
            return true
        case .move:
            rect.origin.x = min(max(rect.minX + dx, box.minX), box.maxX - rect.width)
            rect.origin.y = min(max(rect.minY + dy, box.minY), box.maxY - rect.height)
        case .resize(let handle):
            let minSize: CGFloat = 16
            var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
            if handle.movesLeft { minX = min(max(minX + dx, box.minX), maxX - minSize) }
            if handle.movesRight { maxX = max(min(maxX + dx, box.maxX), minX + minSize) }
            if handle.movesBottom { minY = min(max(minY + dy, box.minY), maxY - minSize) }
            if handle.movesTop { maxY = max(min(maxY + dy, box.maxY), minY + minSize) }
            rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            if shift, handle.isCorner {
                // Keep the original proportions, holding the opposite corner still.
                let ow = drag.original.width, oh = drag.original.height
                let anchorX = handle.movesLeft ? drag.original.maxX : drag.original.minX
                let anchorY = handle.movesBottom ? drag.original.maxY : drag.original.minY
                let roomX = handle.movesLeft ? anchorX - box.minX : box.maxX - anchorX
                let roomY = handle.movesBottom ? anchorY - box.minY : box.maxY - anchorY
                let wanted = max(rect.width / ow, rect.height / oh)
                let scale = max(min(wanted, roomX / ow, roomY / oh), minSize / min(ow, oh))
                let w = ow * scale, h = oh * scale
                rect = CGRect(x: handle.movesLeft ? anchorX - w : anchorX,
                              y: handle.movesBottom ? anchorY - h : anchorY, width: w, height: h)
            }
        }
        drag.item.annotation.bounds = rect
        view.annotationsChanged(on: page)
        overlay.needsDisplay = true
        return true
    }

    func mouseUp(at point: CGPoint) -> Bool {
        guard let drag, let store else { return false }
        self.drag = nil
        if case .lineEnd = drag.mode, let ends = drag.originalEnds {
            let final = LineGeometry.endpoints(of: drag.item.annotation)
            LineGeometry.set(drag.item.annotation, from: ends.start, to: ends.end)
            store.setLine(drag.item, from: final.start, to: final.end, oldFrom: ends.start, oldTo: ends.end)
            return true
        }
        let final = drag.item.annotation.bounds
        drag.item.annotation.bounds = drag.original      // so the change is recorded as one undo step
        let name: String
        switch drag.mode {
        case .move: name = "Move"
        case .resize, .lineEnd: name = "Resize"
        }
        store.setBounds(drag.item, to: final, from: drag.original, name: name)
        return true
    }

    private func begin(_ mode: Mode, _ item: PlacedAnnotation, at point: CGPoint, in view: PDFView) {
        let isLine = AnnotationRow.rawType(item.annotation) == "line"
        drag = Drag(mode: mode, item: item, start: view.convert(point, to: item.page),
                    original: item.annotation.bounds,
                    originalEnds: isLine ? LineGeometry.endpoints(of: item.annotation) : nil)
    }

    private func deselect() {
        if store?.selectedMarkup != nil { store?.selectedMarkup = nil }
    }

    // MARK: Handles

    private func pagePoint(of handle: Handle, in b: CGRect) -> CGPoint {
        let x = handle.movesLeft ? b.minX : handle.movesRight ? b.maxX : b.midX
        let y = handle.movesBottom ? b.minY : handle.movesTop ? b.maxY : b.midY
        return CGPoint(x: x, y: y)
    }

    /// For a line: which end (true = start) is under the mouse.
    private func lineEnd(at point: CGPoint, of item: PlacedAnnotation, in view: PDFView) -> Bool? {
        let ends = LineGeometry.endpoints(of: item.annotation)
        let s = view.convert(ends.start, from: item.page), e = view.convert(ends.end, from: item.page)
        if hypot(s.x - point.x, s.y - point.y) <= 9 { return true }
        if hypot(e.x - point.x, e.y - point.y) <= 9 { return false }
        return nil
    }

    private func handle(at point: CGPoint, of item: PlacedAnnotation, in view: PDFView) -> Handle? {
        for handle in Handle.allCases {
            let p = view.convert(pagePoint(of: handle, in: item.annotation.bounds), from: item.page)
            if hypot(p.x - point.x, p.y - point.y) <= 7 { return handle }
        }
        return nil
    }

    // MARK: Drawing

    func drawSelection(in overlay: NSView) {
        if let band = rubber, let view {
            let from = overlay.convert(band.from, from: view), to = overlay.convert(band.to, from: view)
            let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
            let path: NSBezierPath
            switch band.tool {
            case .line:
                path = NSBezierPath()
                path.move(to: from)
                path.line(to: to)
            case .oval:
                path = NSBezierPath(ovalIn: rect)
            default:
                path = NSBezierPath(rect: rect)
            }
            if band.tool != .line {
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                path.fill()
            }
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        }
        guard let view, let item = store?.selectedMarkup, item.page.document != nil else { return }
        let b = item.annotation.bounds
        func spot(_ p: CGPoint) -> CGPoint { overlay.convert(view.convert(p, from: item.page), from: view) }

        if AnnotationRow.rawType(item.annotation) == "line" {      // just a handle at each end
            let ends = LineGeometry.endpoints(of: item.annotation)
            for end in [ends.start, ends.end] {
                let c = spot(end)
                let circle = NSBezierPath(ovalIn: NSRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
                NSColor.white.setFill()
                circle.fill()
                NSColor.controlAccentColor.setStroke()
                circle.lineWidth = 1.5
                circle.stroke()
            }
            return
        }

        let outline = NSBezierPath()
        outline.move(to: spot(CGPoint(x: b.minX, y: b.minY)))
        outline.line(to: spot(CGPoint(x: b.maxX, y: b.minY)))
        outline.line(to: spot(CGPoint(x: b.maxX, y: b.maxY)))
        outline.line(to: spot(CGPoint(x: b.minX, y: b.maxY)))
        outline.close()
        outline.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        for handle in Handle.allCases {
            let c = spot(pagePoint(of: handle, in: b))
            let square = NSBezierPath(rect: NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            square.fill()
            NSColor.controlAccentColor.setStroke()
            square.lineWidth = 1.5
            square.stroke()
        }
    }

    // MARK: Following the view

    /// Redraw the handles when the view scrolls.
    private func watchScrolling() {
        guard observedClip == nil, let clip = view?.documentView?.enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        observedClip = clip
        clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewChanged() }
        }
    }

    func scaleChanged() { viewChanged() }

    /// After scrolling or zooming: redraw the handles, and (shortly after it settles) swap any text boxes and
    /// note icons that have scrolled into view for the vector-drawing versions.
    private func viewChanged() {
        overlay.needsDisplay = true
        renderWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store?.upgradeVisibleAnnotations() }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

struct RubberBand {
    let tool: MarkupTool
    let from: CGPoint
    let to: CGPoint
}

/// Draws the selection outline and handles over the PDF view. It never takes the mouse.
final class SelectionOverlayView: NSView {
    weak var handler: MarkupSelectionHandler?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        handler?.drawSelection(in: self)
    }
}

// MARK: - Store: moving and restyling (undoable)

private var lastRestyleTarget: AnyObject?
private var lastRestyleTime = Date.distantPast

struct AnnotationStyle {
    var font: NSFont?
    var fontColor: NSColor?
    var color: NSColor
    var alignment: NSTextAlignment
    var border: PDFBorder?
    var interiorColor: NSColor?
    var startLineStyle: PDFLineStyle
    var endLineStyle: PDFLineStyle
    var ends: (start: CGPoint, end: CGPoint)?      // lines: the end points, since line width changes the bounds

    init(_ annotation: PDFAnnotation) {
        font = annotation.font
        fontColor = annotation.fontColor
        color = annotation.color
        alignment = annotation.alignment
        border = annotation.border
        interiorColor = annotation.interiorColor
        startLineStyle = annotation.startLineStyle
        endLineStyle = annotation.endLineStyle
        ends = AnnotationRow.rawType(annotation) == "line" ? LineGeometry.endpoints(of: annotation) : nil
    }

    func apply(to annotation: PDFAnnotation) {
        annotation.font = font
        annotation.fontColor = fontColor
        annotation.color = color
        annotation.alignment = alignment
        switch AnnotationRow.rawType(annotation) {
        case "freetext":
            break
        case "line":
            annotation.border = border
            annotation.startLineStyle = startLineStyle
            annotation.endLineStyle = endLineStyle
            if let ends { LineGeometry.set(annotation, from: ends.start, to: ends.end) }
        default:
            annotation.border = border
            if let interiorColor { annotation.interiorColor = interiorColor }
            if (border?.lineWidth ?? 1) == 0 {annotation.removeValue(forAnnotationKey: .color) }   // no outline
        }
    }
}

extension DocumentStore {

    func refresh(_ item: PlacedAnnotation) {
        pdfView?.annotationsChanged(on: item.page)
        annotationRevision += 1
    }

    func setBounds(_ item: PlacedAnnotation, to new: CGRect, from old: CGRect, name: String) {
        guard new != old else { return }
        item.annotation.bounds = new
        item.annotation.modificationDate = Date()
        refresh(item)
        undoManager?.registerUndo(withTarget: self) { $0.setBounds(item, to: old, from: new, name: name) }
        undoManager?.setActionName(name)
    }

    /// Changes font, colour, … of one annotation as one undo step.
    func restyle(_ item: PlacedAnnotation, _ change: (PDFAnnotation) -> Void) {
        let before = AnnotationStyle(item.annotation)
        change(item.annotation)
        item.annotation.modificationDate = Date()
        // Dragging in the colour panel changes the colour many times a second: one undo step for a burst.
        let now = Date()
        let isBurst = lastRestyleTarget === item.annotation && now.timeIntervalSince(lastRestyleTime) < 1.0
        lastRestyleTarget = item.annotation
        lastRestyleTime = now
        if !isBurst { registerStyleUndo(item, restoring: before) }
        refresh(item)
    }

    private func registerStyleUndo(_ item: PlacedAnnotation, restoring target: AnnotationStyle) {
        undoManager?.registerUndo(withTarget: self) { store in
            let now = AnnotationStyle(item.annotation)
            target.apply(to: item.annotation)
            store.refresh(item)
            store.registerStyleUndo(item, restoring: now)
        }
        undoManager?.setActionName("Change Style")
    }
}

// MARK: - Strip: options for the selected text box

extension TextColor {
    /// The index of the preset closest to `color`, or -1.
    static func match(_ color: NSColor?) -> Int {
        guard let color = color?.usingColorSpace(.sRGB) else { return -1 }
        for preset in allCases {
            guard let p = preset.nsColor.usingColorSpace(.sRGB) else { continue }
            if abs(p.redComponent - color.redComponent) < 0.05,
               abs(p.greenComponent - color.greenComponent) < 0.05,
               abs(p.blueComponent - color.blueComponent) < 0.05 { return preset.rawValue }
        }
        return -1
    }
}

struct SelectedTextOptions: View {
    @ObservedObject var store: DocumentStore
    let item: PlacedAnnotation

    var body: some View {
        let _ = store.annotationRevision   // look again after each change
        let annotation = item.annotation

        HStack(spacing: 8) {
            Text("Text Box").font(.caption).foregroundStyle(.secondary)

            Picker("Font", selection: Binding(
                get: { annotation.font?.familyName ?? "Helvetica" },
                set: { family in
                    store.restyle(item) { a in
                        a.font = TextFonts.font(family: family, size: a.font?.pointSize ?? 14,
                                                bold: TextFonts.isBold(a.font), italic: TextFonts.isItalic(a.font))
                    }
                })) {
                ForEach(TextFonts.names, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Picker("Size", selection: Binding(
                get: { Double(annotation.font?.pointSize ?? 14) },
                set: { size in
                    store.restyle(item) { a in
                        a.font = TextFonts.font(family: a.font?.familyName ?? "Helvetica", size: CGFloat(size),
                                                bold: TextFonts.isBold(a.font), italic: TextFonts.isItalic(a.font))
                    }
                })) {
                ForEach(TextFonts.sizes, id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            ColorPicker("Colour", selection: Binding(
                get: { Color(nsColor: annotation.fontColor ?? .black) },
                set: { color in store.restyle(item) { $0.fontColor = StoredColor.ns(color) } }),
                        supportsOpacity: false)

            Toggle(isOn: Binding(
                get: { TextFonts.isBold(annotation.font) },
                set: { on in
                    store.restyle(item) { a in
                        a.font = TextFonts.font(family: a.font?.familyName ?? "Helvetica", size: a.font?.pointSize ?? 14,
                                                bold: on, italic: TextFonts.isItalic(a.font))
                    }
                })) { Image(systemName: "bold") }
                .toggleStyle(.button)

            Toggle(isOn: Binding(
                get: { TextFonts.isItalic(annotation.font) },
                set: { on in
                    store.restyle(item) { a in
                        a.font = TextFonts.font(family: a.font?.familyName ?? "Helvetica", size: a.font?.pointSize ?? 14,
                                                bold: TextFonts.isBold(a.font), italic: on)
                    }
                })) { Image(systemName: "italic") }
                .toggleStyle(.button)
        }
    }
}
