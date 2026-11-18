import AppKit
import PDFKit

// MARK: - Flatten markup into the page

extension DocumentStore {

    /// Annotations that are always flattened: the things drawn *on* the page rather than comments about it.
    private static let drawnTypes: Set<String> = ["freetext", "square", "circle", "line", "ink", "stamp"]
    private static let commentTypes: Set<String> = ["highlight", "underline", "strikeout", "text"]

    private func typesToFlatten(includingComments: Bool) -> Set<String> {
        includingComments ? Self.drawnTypes.union(Self.commentTypes) : Self.drawnTypes
    }

    /// How many pages carry something that would be flattened.
    func pagesToFlatten(includingComments: Bool) -> Int {
        let types = typesToFlatten(includingComments: includingComments)
        var count = 0
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            if page.annotations.contains(where: { types.contains(AnnotationRow.rawType($0)) }) { count += 1 }
        }
        return count
    }

    /// Redraws each page that has markup, with the markup baked into its content (as vectors), and replaces the
    /// document with the result (one undo step). Pages without such markup are kept as they are.
    func flattenMarkup(includingComments: Bool) {
        guard canComment else { NSSound.beep(); return }
        let types = typesToFlatten(includingComments: includingComments)
        let source = pdf
        let result = PDFDocument()

        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { continue }
            let hasMarkup = page.annotations.contains { types.contains(AnnotationRow.rawType($0)) }
            if hasMarkup, let flat = Self.flattenedPage(from: page, flattening: types) {
                result.insert(flat, at: result.pageCount)
            } else if let copy = page.copy() as? PDFPage {
                result.insert(copy, at: result.pageCount)
            }
        }
        guard result.pageCount == source.pageCount else { NSSound.beep(); return }
        Self.repointLinks(in: result, from: source)

        selectedMarkup = nil
        replaceDocument(with: result, bookmarks: bookmarks, name: "Flatten Markup")
        annotationRevision += 1
    }

    /// One page redrawn (as vectors) with the chosen annotations drawn into its content and removed as objects.
    private static func flattenedPage(from page: PDFPage, flattening types: Set<String>) -> PDFPage? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = page.bounds(for: .mediaBox)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }

        // Draw the page with only the annotations we're flattening visible.
        let kept = page.annotations.filter { !types.contains(AnnotationRow.rawType($0)) }
        let wasShown = kept.map(\.shouldDisplay)
        kept.forEach { $0.shouldDisplay = false }

        context.beginPDFPage(nil)
        page.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()

        for (annotation, shown) in zip(kept, wasShown) { annotation.shouldDisplay = shown }

        guard let flat = PDFDocument(data: data as Data)?.page(at: 0) else { return nil }
        flat.setBounds(page.bounds(for: .cropBox), for: .cropBox)
        flat.rotation = page.rotation

        // Everything not flattened (links, highlights, notes, form fields) stays an annotation.
        for annotation in kept where AnnotationRow.rawType(annotation) != "popup" {
            if let copy = annotation.copy() as? PDFAnnotation { flat.addAnnotation(copy) }
        }
        return flat
    }

    /// Links copied from the old document still point at the old document's pages; point them at the new ones.
    private static func repointLinks(in result: PDFDocument, from source: PDFDocument) {
        func mapped(_ destination: PDFDestination?) -> PDFDestination? {
            guard let destination, let oldPage = destination.page else { return nil }
            let index = source.index(for: oldPage)
            guard index != NSNotFound, let newPage = result.page(at: index) else { return nil }
            return PDFDestination(page: newPage, at: destination.point)
        }
        for index in 0..<result.pageCount {
            guard let page = result.page(at: index) else { continue }
            for annotation in page.annotations where AnnotationRow.rawType(annotation) == "link" {
                if let destination = mapped(annotation.destination) {
                    annotation.destination = destination
                } else if let action = annotation.action as? PDFActionGoTo, let destination = mapped(action.destination) {
                    annotation.action = PDFActionGoTo(destination: destination)
                }
            }
        }
    }
}
