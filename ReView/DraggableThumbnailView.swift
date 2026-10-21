import Cocoa
import Quartz

class DraggableThumbnailView: PDFThumbnailView {

    private var draggedPages: [PDFPage] = []
    private weak var sourceDocument: PDFDocument?

    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        guard let pdfView = self.pdfView, let pdf = pdfView.document else { return }

        draggedPages = selectedPages()
        guard !draggedPages.isEmpty else { return }

        sourceDocument = pdf

        // Create pasteboard item
        let pasteboardItem = NSPasteboardItem()
        for page in draggedPages {
            if let data = page.dataRepresentation {
                pasteboardItem.setData(data, forType: .pdf)
            }
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(self.bounds, contents: snapshot())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    // MARK: - Helpers
    private func selectedPages() -> [PDFPage] {
        if #available(OSX 11.0, *) {
            return self.selectedPages ?? []
        } else if let pdfView = self.pdfView, let selection = pdfView.currentSelection {
            return selection.pages
        } else {
            return []
        }
    }

    private func snapshot() -> NSImage {
        let rep = self.bitmapImageRepForCachingDisplay(in: self.bounds)!
        self.cacheDisplay(in: self.bounds, to: rep)
        let image = NSImage(size: self.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func movePages(to index: Int, in targetDocument: PDFDocument? = nil) {
        guard let pdf = targetDocument ?? sourceDocument else { return }

        for page in draggedPages {
            if let originalIndex = sourceDocument?.index(for: page) {
                sourceDocument?.removePage(at: originalIndex)
            }
        }

        for (i, page) in draggedPages.enumerated() {
            pdf.insert(page, at: index + i)
        }

        draggedPages.removeAll()
        self.needsDisplay = true
    }
}

// MARK: - NSDraggingSource
extension DraggableThumbnailView: NSDraggingSource {

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.move]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedPages.removeAll()
        sourceDocument = nil
    }
}

// MARK: - NSDraggingDestination
extension DraggableThumbnailView {

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .move
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pdfView = self.pdfView, let targetDoc = pdfView.document else { return false }

        let dragPoint = sender.draggingLocation
        let dropIndex = pageIndex(at: dragPoint) ?? targetDoc.pageCount

        for page in draggedPages {
            // Remove from source if needed
            if let sourceDoc = sourceDocument, sourceDoc != targetDoc {
                let idx = sourceDoc.index(for: page)
                sourceDoc.removePage(at: idx)
            }

            // Insert in target
            targetDoc.insert(page, at: dropIndex)
        }

        draggedPages.removeAll()
        self.needsDisplay = true
        return true
    }

    func pageIndex(at point: NSPoint) -> Int? {
        guard let pdfView = self.pdfView, let pdfDoc = pdfView.document else { return nil }

        // Convert point to PDFView coordinates
        let pointInPDFView = self.convert(point, to: pdfView)

        // Use PDFView.page(for:nearest:) to get the page
        if let page = pdfView.page(for: pointInPDFView, nearest: true) {
            return pdfDoc.index(for: page)
        }

        return nil
    }
}
