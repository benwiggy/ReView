import AppKit
import PDFKit
import SwiftUI

// MARK: - Line geometry

/// A PDF line annotation keeps its end points relative to its bounds; these helpers work in page coordinates.
enum LineGeometry {
    static func endpoints(of annotation: PDFAnnotation) -> (start: CGPoint, end: CGPoint) {
        let origin = annotation.bounds.origin
        return (CGPoint(x: origin.x + annotation.startPoint.x, y: origin.y + annotation.startPoint.y),
                CGPoint(x: origin.x + annotation.endPoint.x, y: origin.y + annotation.endPoint.y))
    }

    /// Room around the end points for the line's thickness and arrowheads.
    static func padding(forWidth width: CGFloat) -> CGFloat { 8 + width * 3 }

    static func set(_ annotation: PDFAnnotation, from start: CGPoint, to end: CGPoint) {
        let pad = padding(forWidth: annotation.border?.lineWidth ?? 1)
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y)).insetBy(dx: -pad, dy: -pad)
        annotation.bounds = box
        annotation.startPoint = CGPoint(x: start.x - box.minX, y: start.y - box.minY)
        annotation.endPoint = CGPoint(x: end.x - box.minX, y: end.y - box.minY)
    }
}

// MARK: - Outline on or off

/// Preview writes "no outline" as a zero border width and no /C (colour) entry at all. A clear colour doesn't work:
/// PDFKit drops the opacity of a stroke colour, so it comes out black.
enum ShapeStroke {
    static func isOff(_ annotation: PDFAnnotation) -> Bool {
        (annotation.border?.lineWidth ?? 1) == 0
    }

    static func turnOff(_ annotation: PDFAnnotation) {
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        annotation.removeValue(forAnnotationKey: .color)
    }

    static func turnOn(_ annotation: PDFAnnotation, color: NSColor, width: CGFloat) {
        let border = PDFBorder()
        border.lineWidth = width
        annotation.border = border
        annotation.color = color
    }
}

// MARK: - Defaults for the next shape

enum ShapeDefaults {
    static let strokeFallback = NSColor(srgbRed: 0.85, green: 0.10, blue: 0.10, alpha: 1)
    static let fillFallback = NSColor(srgbRed: 1.00, green: 0.90, blue: 0.10, alpha: 0.35)

    /// False when the outline is turned off (a clear stroke colour).
    static var strokeOn: Bool { UserDefaults.standard.object(forKey: "shapeStrokeOn") as? Bool ?? true }

    static var stroke: NSColor {
        StoredColor.color(UserDefaults.standard.string(forKey: "shapeStrokeHex"), fallback: strokeFallback)
    }
    static var width: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: "shapeWidth") as? Double ?? 2)
    }
    static var fillOn: Bool { UserDefaults.standard.bool(forKey: "shapeFillOn") }
    static var fill: NSColor {
        StoredColor.color(UserDefaults.standard.string(forKey: "shapeFillHex"), fallback: fillFallback)
    }
}

// MARK: - Store: creating and editing lines

extension DocumentStore {

    /// Creates a rectangle, oval or line from a drag (or, for rectangles and ovals, a click).
    func placeShape(_ tool: MarkupTool, on page: PDFPage, from start: CGPoint, to end: CGPoint, in view: PDFView) {
        guard canComment else { return }
        let box = page.bounds(for: .cropBox)
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, box.minX), box.maxX), y: min(max(p.y, box.minY), box.maxY))
        }
        let a = clamp(start), b = clamp(end)
        let width = max(ShapeDefaults.width, 1)
        let strokeless = tool != .line && !ShapeDefaults.strokeOn

        let border = PDFBorder()
        border.lineWidth = width

        let annotation: PDFAnnotation
        switch tool {
        case .rectangle, .oval:
            var rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            if rect.width < 6 || rect.height < 6 {                       // a click: a default-sized shape
                rect = CGRect(x: a.x, y: a.y - 80, width: 120, height: 80)
                rect.origin.x = min(max(rect.minX, box.minX), box.maxX - rect.width)
                rect.origin.y = min(max(rect.minY, box.minY), box.maxY - rect.height)
            }
            annotation = PDFAnnotation(bounds: rect, forType: tool == .rectangle ? .square : .circle, withProperties: nil)
            annotation.interiorColor = ShapeDefaults.fillOn ? ShapeDefaults.fill : .clear
            annotation.border = border
        case .line:
            guard hypot(b.x - a.x, b.y - a.y) >= 6 else { NSSound.beep(); return }
            annotation = PDFAnnotation(bounds: .zero, forType: .line, withProperties: nil)
            annotation.border = border
            LineGeometry.set(annotation, from: a, to: b)
            let ends = UserDefaults.standard.integer(forKey: "shapeLineEnds")      // 0 plain, 1 arrow, 2 double arrow
            annotation.startLineStyle = ends == 2 ? .closedArrow : .none
            annotation.endLineStyle = ends >= 1 ? .closedArrow : .none
        default:
            return
        }
        if strokeless {
            ShapeStroke.turnOff(annotation)
        } else {
            annotation.color = ShapeDefaults.stroke
        }
        annotation.userName = authorName
        annotation.modificationDate = Date()

        let item = PlacedAnnotation(page: page, annotation: annotation)
        addAnnotations([item], name: "Add \(tool.title)")
        selectedMarkup = item      // so it can be adjusted straight away
    }

    func setLine(_ item: PlacedAnnotation, from start: CGPoint, to end: CGPoint,
                 oldFrom: CGPoint, oldTo: CGPoint) {
        guard start != oldFrom || end != oldTo else { return }
        LineGeometry.set(item.annotation, from: start, to: end)
        item.annotation.modificationDate = Date()
        refresh(item)
        undoManager?.registerUndo(withTarget: self) { $0.setLine(item, from: oldFrom, to: oldTo, oldFrom: start, oldTo: end) }
        undoManager?.setActionName("Move Line End")
    }
}

// MARK: - Strip: options for shapes

enum ShapeStyles {
    static let widths: [Double] = [1, 2, 3, 5, 8]
}

/// Stroke, width and fill for the next shape (remembered between launches).
struct ShapeDefaultsOptions: View {
    @AppStorage("shapeStrokeOn") private var strokeOn = true
    @AppStorage("shapeStrokeHex") private var strokeHex = StoredColor.hex(ShapeDefaults.strokeFallback)
    @AppStorage("shapeWidth") private var width = 2.0
    @AppStorage("shapeFillOn") private var fillOn = false
    @AppStorage("shapeFillHex") private var fillHex = StoredColor.hex(ShapeDefaults.fillFallback)
    @AppStorage("shapeLineEnds") private var lineEnds = 0
    let showsFill: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsFill { Toggle("Stroke", isOn: $strokeOn).toggleStyle(.checkbox) }   // lines always have one
            ColorPicker("Stroke colour", selection: Binding(
                get: { Color(nsColor: StoredColor.color(strokeHex, fallback: ShapeDefaults.strokeFallback)) },
                set: { strokeHex = StoredColor.hex(StoredColor.ns($0)); strokeOn = true }), supportsOpacity: true)
                .labelsHidden()
                .disabled(showsFill && !strokeOn)

            Picker("Width", selection: $width) {
                ForEach(ShapeStyles.widths, id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            if showsFill {
                Toggle("Fill", isOn: $fillOn).toggleStyle(.checkbox)
                ColorPicker("Fill colour", selection: Binding(
                    get: { Color(nsColor: StoredColor.color(fillHex, fallback: ShapeDefaults.fillFallback)) },
                    set: { fillHex = StoredColor.hex(StoredColor.ns($0)); fillOn = true }), supportsOpacity: true)
                    .labelsHidden()
            } else {
                Picker("Ends", selection: $lineEnds) {
                    Text("Plain").tag(0)
                    Text("Arrow").tag(1)
                    Text("Double Arrow").tag(2)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }
}

/// Options for the selected rectangle, oval or line.
struct SelectedShapeOptions: View {
    @ObservedObject var store: DocumentStore
    let item: PlacedAnnotation

    var body: some View {
        let _ = store.annotationRevision
        let annotation = item.annotation
        let raw = AnnotationRow.rawType(annotation)

        HStack(spacing: 10) {
            Text(raw == "line" ? "Line" : raw == "circle" ? "Oval" : "Rectangle")
                .font(.caption).foregroundStyle(.secondary)

            if raw != "line" {
                Toggle("Stroke", isOn: Binding(
                    get: { !ShapeStroke.isOff(annotation) },
                    set: { on in
                        store.restyle(item) { a in
                            if on {
                                ShapeStroke.turnOn(a, color: ShapeDefaults.stroke, width: max(ShapeDefaults.width, 1))
                            } else {
                                ShapeStroke.turnOff(a)
                            }
                        }
                    }))
                    .toggleStyle(.checkbox)
            }
            ColorPicker("Stroke colour", selection: Binding(
                get: { Color(nsColor: ShapeStroke.isOff(annotation) ? ShapeDefaults.stroke : annotation.color) },
                set: { color in store.restyle(item) { $0.color = StoredColor.ns(color) } }), supportsOpacity: true)
                .labelsHidden()
                .disabled(raw != "line" && ShapeStroke.isOff(annotation))

            Picker("Width", selection: Binding(
                get: { Double(annotation.border?.lineWidth ?? 1) },
                set: { width in
                    store.restyle(item) { a in
                        let border = PDFBorder()
                        border.lineWidth = CGFloat(width)
                        a.border = border
                        if AnnotationRow.rawType(a) == "line" {
                            let ends = LineGeometry.endpoints(of: a)
                            LineGeometry.set(a, from: ends.start, to: ends.end)   // room for the thicker line
                        }
                    }
                })) {
                ForEach(ShapeStyles.widths, id: \.self) { Text("\(Int($0)) pt").tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()

            if raw == "line" {
                Picker("Ends", selection: Binding(
                    get: { Self.endsChoice(of: annotation) },
                    set: { choice in
                        store.restyle(item) { a in
                            a.startLineStyle = choice == 2 ? .closedArrow : .none
                            a.endLineStyle = choice >= 1 ? .closedArrow : .none
                        }
                    })) {
                    Text("Plain").tag(0)
                    Text("Arrow").tag(1)
                    Text("Double Arrow").tag(2)
                }
                .pickerStyle(.menu)
                .fixedSize()
            } else {
                Toggle("Fill", isOn: Binding(
                    get: { Self.hasFill(annotation) },
                    set: { on in
                        store.restyle(item) { $0.interiorColor = on ? ShapeDefaults.fill : .clear }
                    })).toggleStyle(.checkbox)
                ColorPicker("Fill colour", selection: Binding(
                    get: { Color(nsColor: Self.hasFill(annotation) ? (annotation.interiorColor ?? ShapeDefaults.fill) : ShapeDefaults.fill) },
                    set: { color in store.restyle(item) { $0.interiorColor = StoredColor.ns(color) } }),
                            supportsOpacity: true)
                    .labelsHidden()
                    .disabled(!Self.hasFill(annotation))
            }
        }
    }

    private static func endsChoice(of annotation: PDFAnnotation) -> Int {
        if annotation.startLineStyle != .none && annotation.endLineStyle != .none { return 2 }
        return annotation.endLineStyle != .none ? 1 : 0
    }

    private static func hasFill(_ annotation: PDFAnnotation) -> Bool {
        let interior: NSColor? = annotation.interiorColor
        guard let fill = interior?.usingColorSpace(.sRGB) else { return false }
        return fill.alphaComponent > 0.01
    }
}

// MARK: - Shift: squares, circles and 45° lines

enum ShapeConstraint {
    /// Where the drag's end point goes while Shift is held: rectangles and ovals become square and round,
    /// lines snap to the nearest 45°. Works in any coordinate space, since both are unchanged by flipping.
    static func apply(_ tool: MarkupTool, from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        switch tool {
        case .rectangle, .oval:
            let size = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -size : size), y: start.y + (dy < 0 ? -size : size))
        case .line:
            let length = hypot(dx, dy)
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: start.x + length * cos(angle), y: start.y + length * sin(angle))
        default:
            return end
        }
    }
}
