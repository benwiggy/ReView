//
//  ClipboardDocumentController.swift
//  ReView
//
//  Created by Ben on 26/10/2026.
//


import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Makes File > New create a document from whatever PDF or image is on the clipboard.
/// If there's nothing usable, throwing from `makeUntitledDocument` makes AppKit show the
/// error as an alert and no window opens.
///
/// This must be the first NSDocumentController created: see main.swift.
final class ClipboardDocumentController: NSDocumentController {

    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        guard let pdf = Self.pdfFromClipboard() else { throw NoClipboardDataError() }
        let document = try super.makeUntitledDocument(ofType: typeName)
        (document as? PDFFileDocument)?.store.load(pdf)
        document.updateChangeCount(.changeDone)   // unsaved content: closing asks to save
        return document
    }
    
    /// File > Open: our own panel, so it can offer to combine several files into one new PDF.
    override func openDocument(_ sender: Any?) {
        let combineBox = NSButton(checkboxWithTitle: "Combine selected files into one new PDF", target: nil, action: nil)
        combineBox.state = UserDefaults.standard.bool(forKey: "openCombine") ? .on : .off
        combineBox.sizeToFit()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image]
        panel.accessoryView = combineBox
        panel.isAccessoryViewDisclosed = true
        panel.begin { [self] response in
            guard response == .OK else { return }
            let combine = combineBox.state == .on
            UserDefaults.standard.set(combine, forKey: "openCombine")
            let urls = panel.urls
            if combine, urls.count > 1 {
                openCombined(urls)
            } else {
                for url in urls {
                    openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error { NSApp.presentError(error) }
                    }
                }
            }
        }
    }

    /// One new, unsaved PDF from all the files, in natural filename order.
    private func openCombined(_ urls: [URL]) {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let result = PageImporter.pages(fromURLs: sorted, fitting: DocumentStore.defaultPageRect.size)
        PageImporter.reportSkipped(result.skipped)
        guard !result.pages.isEmpty else { return }

        let combined = PDFDocument()
        for page in result.pages { combined.insert(page, at: combined.pageCount) }
        do {
            let document = try PDFFileDocument(type: "com.adobe.pdf")
            document.store.load(combined)
            document.updateChangeCount(.changeDone)   // unsaved content: closing asks to save
            addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
        } catch {
            presentError(error)
        }
    }

    /// PDF data, then copied PDF/image files, then image data.
    static func pdfFromClipboard() -> PDFDocument? {
        let pasteboard = NSPasteboard.general

        // 1. PDF data (e.g. copied from another PDF viewer)
        if let data = pasteboard.data(forType: .pdf), let pdf = PDFDocument(data: data), pdf.pageCount > 0 {
            return pdf
        }

        // 2. Files copied in the Finder (PDFs or images)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            let output = PDFDocument()
            for url in urls {
                if let source = PDFDocument(url: url) {
                    for index in 0..<source.pageCount {
                        if let page = source.page(at: index)?.copy() as? PDFPage {
                            output.insert(page, at: output.pageCount)
                        }
                    }
                } else if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                    output.insert(page, at: output.pageCount)
                }
            }
            if output.pageCount > 0 { return output }
        }

        // 3. Image data (screenshots, images copied from other apps): one page per image
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            let output = PDFDocument()
            for image in images {
                if let page = PDFPage(image: image) { output.insert(page, at: output.pageCount) }
            }
            if output.pageCount > 0 { return output }
        }

        return nil
    }
    
    private static func unlocked(_ pdf: PDFDocument, name: String) -> PDFDocument? {
        guard pdf.isLocked else { return pdf }
        return PasswordPrompt.unlock(pdf, name: name) == nil ? nil : pdf
    }
}

private struct NoClipboardDataError: LocalizedError {
    var errorDescription: String? { "There's no PDF or image on the clipboard." }
    var recoverySuggestion: String? {
        "Copy a PDF, an image, or a PDF or image file, then choose File > New from Clipboard again."
    }
}
