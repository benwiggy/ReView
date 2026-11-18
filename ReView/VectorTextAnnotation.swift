import AppKit
import PDFKit

// MARK: - Annotations that draw themselves as vectors
//
// PDFKit draws text boxes and note icons from a cached bitmap, so they look blurry when zoomed.
// These subclasses draw the text and the icon directly into the page's graphics context instead,
// which is crisp at any zoom and re-wraps text when the box is resized. Annotations read from a file
// are swapped for these as they scroll into view (see DocumentStore.upgradeAnnotations).

extension PDFAnnotation {
    /// Copies everything we care about from `old` (used when swapping in a drawing subclass).
    func copyAttributes(from old: PDFAnnotation) {
        contents = old.contents
        font = old.font
        fontColor = old.fontColor
        color = old.color
        alignment = old.alignment
        userName = old.userName
        modificationDate = old.modificationDate
        border = old.border
    }
}

final class VectorTextAnnotation: PDFAnnotation {

    /// Degrees the text is turned anticlockwise relative to the page, fixed when the box is made.
    /// Saved as the annotation's /Rotate entry if PDFKit allows it.
    var rotation = 0
    private static let rotateKey = PDFAnnotationKey(rawValue: "/Rotate")

    func setRotation(_ degrees: Int) {
        rotation = ((degrees % 360) + 360) % 360
        _ = setValue(NSNumber(value: rotation), forAnnotationKey: Self.rotateKey)
    }

    convenience init(copying old: PDFAnnotation) {
        self.init(bounds: old.bounds, forType: .freeText, withProperties: nil)
        copyAttributes(from: old)
        if let known = (old as? VectorTextAnnotation)?.rotation {
            setRotation(known)
        } else if let stored = old.value(forAnnotationKey: Self.rotateKey) {
            setRotation((stored as? NSNumber)?.intValue ?? (stored as? Int) ?? 0)
        }
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        if color.alphaComponent > 0.01 {
            context.setFillColor(color.cgColor)
            context.fill(bounds)
        }
        if let text = contents, !text.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: fontColor ?? NSColor.black,
                .paragraphStyle: paragraph
            ]
            // The text is turned within the box (tall or wide the other way round in page space).
            let sideways = rotation == 90 || rotation == 270
            let width = sideways ? bounds.height : bounds.width
            let height = sideways ? bounds.width : bounds.height

            context.clip(to: bounds)
            context.translateBy(x: bounds.midX, y: bounds.midY)
            context.rotate(by: CGFloat(rotation) * .pi / 180)
            let area = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)

            // The page's context has y pointing up, which is what an unflipped NSGraphicsContext expects.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (text as NSString).draw(with: area.insetBy(dx: 3, dy: 2),
                                    options: [.usesLineFragmentOrigin],
                                    attributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        context.restoreGState()
    }
}

final class VectorNoteAnnotation: PDFAnnotation {

    convenience init(copying old: PDFAnnotation) {
        self.init(bounds: old.bounds, forType: .text, withProperties: nil)
        copyAttributes(from: old)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let fill = (color.usingColorSpace(.sRGB) ?? NSColor.systemYellow).withAlphaComponent(1)

        context.saveGState()
        // Turned back on a rotated page, so the icon's lines stay horizontal as the page is shown.
        let turns = ((page?.rotation ?? 0) % 360 + 360) % 360
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: CGFloat(turns) * .pi / 180)
        let r = CGRect(x: -bounds.width / 2, y: -bounds.height / 2,
                       width: bounds.width, height: bounds.height).insetBy(dx: 1.5, dy: 1.5)
        context.setFillColor(fill.cgColor)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(0.8)
        context.addPath(CGPath(roundedRect: r, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.drawPath(using: .fillStroke)

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(0.9)
        for index in 0..<3 {
            let y = r.maxY - r.height * (0.28 + 0.2 * CGFloat(index))
            context.move(to: CGPoint(x: r.minX + r.width * 0.2, y: y))
            context.addLine(to: CGPoint(x: r.maxX - r.width * 0.2, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }
}

extension DocumentStore {

    func upgradeVisibleAnnotations() {
        guard let view = pdfView else { return }
        for page in view.visiblePages { upgradeAnnotations(on: page) }
    }

    /// Swaps PDFKit's own text boxes and note icons on `page` for the vector-drawing versions.
    func upgradeAnnotations(on page: PDFPage) {
        var changed = false
        for old in page.annotations {
            let replacement: PDFAnnotation
            switch AnnotationRow.rawType(old) {
            case "freetext" where !(old is VectorTextAnnotation): replacement = VectorTextAnnotation(copying: old)
            case "text" where !(old is VectorNoteAnnotation):     replacement = VectorNoteAnnotation(copying: old)
            default: continue
            }
            page.removeAnnotation(old)
            page.addAnnotation(replacement)
            if let selected = selectedMarkup, selected.annotation === old {
                selectedMarkup = PlacedAnnotation(page: page, annotation: replacement)
            }
            changed = true
        }
        if changed { pdfView?.annotationsChanged(on: page) }
    }
}
