import AppKit
import PDFKit

/// The document. Using NSDocument (rather than SwiftUI's DocumentGroup) is deliberate:
/// DocumentGroup always autosaves and offers no way to switch that off.
final class PDFFileDocument: NSDocument {

    let store = DocumentStore()
    /// Set when this document was made by opening an image: it is then an unsaved, untitled PDF.
    private var imageSourceName: String?
    private var needsBringToFront = false   // set when a password prompt may have left our window behind

    // Manual saving only: no autosave-in-place, no autosaved drafts.
    nonisolated override class var autosavesInPlace: Bool { false }
    nonisolated override class var autosavesDrafts: Bool { false }

    override init() {
        super.init()
        store.document = self
    }

    /// An untitled PDF made from an image is named after the image until it is saved.
    override var displayName: String! {
        get { fileURL == nil ? (imageSourceName ?? super.displayName) : super.displayName }
        set { super.displayName = newValue }
    }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        guard let pdf = PDFDocument(data: data) else {
            // Not a PDF: an image file opened as a new PDF.
            guard let converted = PageImporter.document(fromImageData: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            imageSourceName = fileURL?.deletingPathExtension().lastPathComponent
            store.load(converted)
            return
        }
        var password: String?
        if pdf.isLocked {
            let name = fileURL?.lastPathComponent ?? "this document"
            let entered = MainActor.assumeIsolated { PasswordPrompt.unlock(pdf, name: name) }
            guard let entered else { throw CocoaError(.userCancelled) }   // Cancel: no alert, no window
            password = entered
            needsBringToFront = true
        }
        store.load(pdf, openPassword: password)
    }

    override func data(ofType typeName: String) throws -> Data {
        store.commitBookmarks()   // write the bookmark tree into the PDF's outline first
        store.commitMetadata()    // and the edited title, author, subject and keywords
        return try store.encodedData()
    }

    // MARK: Windows

    override func showWindows() {
        super.showWindows()
        guard needsBringToFront else { return }
        needsBringToFront = false
        DispatchQueue.main.async { [weak self] in
            AppActivation.bringToFront()
            self?.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
        }
    }

    override func makeWindowControllers() {
        if imageSourceName != nil {
            // The image file must never be overwritten with PDF data: become an untitled, unsaved
            // PDF, so closing asks to save and Save asks for a name.
            fileURL = nil
            fileType = "com.adobe.pdf"
            updateChangeCount(.changeDone)
        }
        addWindowController(DocumentWindowController(store: store))
    }

    // MARK: Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = NSPrintInfo(dictionary: printSettings)
        guard let operation = store.pdf.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return operation
    }
}
