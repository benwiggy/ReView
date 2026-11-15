import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Turns dropped PDF files, image files and image data into pages to insert.
enum PageImporter {

    /// Dragged file types that can become pages.
    static let fileTypes: [String] = [UTType.pdf.identifier, UTType.image.identifier]

    private static var urlOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: fileTypes]
    }

    /// Pasteboard types the sidebar must register for to be offered these drags.
    static var draggedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
    }

    static func canImport(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: urlOptions)
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// Pages for everything usable on the pasteboard, in drag order, and the names of items that were left out.
    /// Images are shrunk to fit inside `reference` (never enlarged), turned to match its orientation.
    static func pages(from pasteboard: NSPasteboard, fitting reference: CGSize) -> (pages: [PDFPage], skipped: [String]) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL]) ?? []
        if !urls.isEmpty {
            return Self.pages(fromURLs: urls, fitting: reference)
        }

        // Image data dragged from a browser or another app.
        var result: [PDFPage] = []
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let page = page(from: image, fitting: reference) { result.append(page) }
            }
        }
        return (result, [])
    }

    /// A new document from an image file's data: one page per image (a multi-page TIFF gives several),
    /// shrunk to fit a default page if it is larger, and never enlarged.
    static func document(fromImageData data: Data) -> PDFDocument? {
        var images: [NSImage] = NSBitmapImageRep.imageReps(with: data).map { rep in
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            return image
        }
        if images.isEmpty, let image = NSImage(data: data) { images = [image] }

        let document = PDFDocument()
        for image in images {
            if let page = page(from: image, fitting: DocumentStore.defaultPageRect.size) {
                document.insert(page, at: document.pageCount)
            }
        }
        return document.pageCount > 0 ? document : nil
    }

    /// Pages for PDF and image files, in the order given, and the names of any that were left out.
    static func pages(fromURLs urls: [URL], fitting reference: CGSize) -> (pages: [PDFPage], skipped: [String]) {
        var pages: [PDFPage] = []
        var skipped: [String] = []
        for url in urls {
            if let source = PDFDocument(url: url) {
                if source.isLocked, PasswordPrompt.unlock(source, name: url.lastPathComponent) == nil {
                    skipped.append(url.lastPathComponent)      // password not given
                    continue
                }
                guard source.allowsCopying else {
                    skipped.append(url.lastPathComponent)      // the owner forbids copying its pages
                    continue
                }
                for index in 0..<source.pageCount {
                    // Copies: inserting the originals would pull them out of their own document.
                    if let copy = source.page(at: index)?.copy() as? PDFPage { pages.append(copy) }
                }
            } else if let image = NSImage(contentsOf: url), let page = page(from: image, fitting: reference) {
                pages.append(page)
            } else {
                skipped.append(url.lastPathComponent)
            }
        }
        return (pages, skipped)
    }

    private static func page(from image: NSImage, fitting reference: CGSize) -> PDFPage? {
        guard let sized = image.copy() as? NSImage, sized.size.width > 0, sized.size.height > 0 else { return nil }
        let landscape = sized.size.width > sized.size.height
        let long = max(reference.width, reference.height), short = min(reference.width, reference.height)
        let box = landscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
        let scale = min(1, box.width / sized.size.width, box.height / sized.size.height)
        sized.size = NSSize(width: sized.size.width * scale, height: sized.size.height * scale)
        return PDFPage(image: sized)
    }

    static func reportSkipped(_ names: [String]) {
        guard !names.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "One item couldn't be added." : "\(names.count) items couldn't be added."
        alert.informativeText = names.joined(separator: "\n")
            + "\n\nThey weren't PDFs or images, were password-protected (and no password was given), or don't allow their pages to be copied."
        alert.runModal()
    }
}
