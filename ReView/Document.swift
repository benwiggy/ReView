//
//  Document.swift
//  MyPreview
//
//  Created by Ben on 14/03/2019.
//  
//

import Cocoa
import Quartz

extension Notification.Name {
  static let documentReverted = Notification.Name(rawValue:"Revert!")
}

class Document: NSDocument {
    var thePDFDocument: PDFDocument!

    override init() {
        super.init()
        // Add your subclass-specific initialization here.
      NotificationCenter.default.addObserver(self, selector: #selector(handleFilterChoice), name: .filterSelected, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
     // NO! We do not want our precious originals overwritten!
    override class var autosavesInPlace: Bool {
        return false
    }
    
    var viewController: MySplitViewController? {
        return windowControllers.first?.contentViewController as? MySplitViewController
    }
    
    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller")) as! NSWindowController
        windowController.shouldCascadeWindows = true
        self.addWindowController(windowController)
        if let viewController = windowController.contentViewController as? MySplitViewController {
            viewController.pdfViewController?.representedObject = self
        }
       // windowController.window?.titleVisibility = .hidden
    }
/*
    override func data(ofType typeName: String) throws -> Data {
        // Insert code here to write your document to data of the specified type, throwing an error in case of failure.
        // Alternatively, you could remove this method and override fileWrapper(ofType:), write(to:ofType:), or write(to:ofType:for:originalContentsURL:) instead.
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
     }
*/

    override func read(from data: Data, ofType typeName: String) throws {
        self.thePDFDocument = PDFDocument.init(data: data)
        if self.thePDFDocument == nil {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
    
    // Provide warning that Save will overwrite the existing file. Also allow user to turn it off.
    override func save(_ sender: Any?) {

        switch self.isDocumentEdited {
        case false:
         
            let alert = NSAlert()
            alert.messageText = "Save Document?"
            alert.informativeText = "Document has not been altered. \rSaving will 'rinse' the document through PDFKit."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Save As..")
            alert.addButton(withTitle: "Cancel")
            
            // Would prefer a sheet, but don't know which window it is.
            let result = alert.runModal()

            switch result {
            case NSApplication.ModalResponse.alertFirstButtonReturn:
                super.save(Any?.self)
            case NSApplication.ModalResponse.alertSecondButtonReturn:
                super.saveAs(Any?.self)
            case NSApplication.ModalResponse.alertThirdButtonReturn:
             break
            default:
                super.save(Any?.self)
            }
        case true:
             super.save(Any?.self)
        }
    }
    
    // Save as a PDF. Options will come later. (Allowing Quartz Filters, metadata)
    override func write(to url: URL, ofType typeName: String) throws {
        thePDFDocument?.write(to: url, withOptions: nil)
    }
    
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
      do {
        let data = try Data(contentsOf: url)
        self.thePDFDocument = PDFDocument.init(data: data)
        try super.revert(toContentsOf: url, ofType: typeName)
        NotificationCenter.default.post(name: .documentReverted, object: self)
        viewController?.viewWillAppear()
        }
    }
    
    override func close() {
        thePDFDocument = nil
        super.close()
    }
    
    
    // PRINTING
    // Make sure our page is centred on the paper, to avoid uneven margins.
    // (This gives the best fit when duplexing.)
    func thePrintInfo() -> NSPrintInfo {
        let thePrintInfo = NSPrintInfo()
        thePrintInfo.horizontalPagination = .fit
        thePrintInfo.verticalPagination = .fit
        thePrintInfo.isHorizontallyCentered = true
        thePrintInfo.isVerticallyCentered = true
        thePrintInfo.leftMargin = 0.0
        thePrintInfo.rightMargin = 0.0
        thePrintInfo.topMargin = 0.0
        thePrintInfo.bottomMargin = 0.0
        thePrintInfo.jobDisposition = .spool
        return thePrintInfo
    }
    
    // Add the Page Setup options to the Print Dialog
    func thePrintPanel() -> NSPrintPanel {
        let thePrintPanel = NSPrintPanel()
        thePrintPanel.options = [
            NSPrintPanel.Options.showsCopies,
            NSPrintPanel.Options.showsPrintSelection,
            NSPrintPanel.Options.showsPageSetupAccessory,
            NSPrintPanel.Options.showsPreview
        ]
        return thePrintPanel
    }
    
    override func printDocument(_ sender: Any?) {
        if let printOperation = thePDFDocument.printOperation(for: thePrintInfo(), scalingMode: .pageScaleNone, autoRotate: true){
            printOperation.printPanel = thePrintPanel()
            // Would prefer to use .runModal but don't know what the window is.
            printOperation.run()
        }
    }
    
    
    @objc func handleFilterChoice(_ note: Notification) {
        let filterpath = note.userInfo!["url"] as! URL
        let value = QuartzFilter(url: filterpath)
        let dict = [ "QuartzFilter" : value ]
            if let pdfData = thePDFDocument.dataRepresentation(options: dict as Any as! [AnyHashable : Any]) {
            thePDFDocument = PDFDocument.init(data: pdfData)
                viewController?.viewWillAppear()
    }
    }
    
    // PDFDocument has to be rinsed through NSData and back in to
    // update page numbers and redisplay Quartz Filter effects, etc.
    // Ideally want to have options dict as an argument. (See handleFilterChoice)
    func rinse() {
        let pdfData = thePDFDocument?.dataRepresentation()
        thePDFDocument = PDFDocument.init(data: pdfData!)
        viewController?.viewWillAppear()
    }
    
    func setRotation(_ rotation: Int, forPageAt index: Int) {
        guard let page = thePDFDocument.page(at: index) else { return }
        let oldRotation = page.rotation
        page.rotation = rotation
        registerUndoForRotation(page: page, oldRotation: oldRotation, newRotation: rotation)
    }
    
    private func registerUndoForRotation(page: PDFPage, oldRotation: Int, newRotation: Int) {
        viewController?.undoManager?.registerUndo(withTarget: self) { target in
            target.setRotation(oldRotation, forPageAt: self.thePDFDocument.index(for: page))
        }
    }
    
    func insert(blankPage: PDFPage, at index: Int) {
        thePDFDocument.insert(blankPage, at: index)
        registerUndoForInsert(page: blankPage, at: index)
    }
    
    private func registerUndoForInsert(page: PDFPage, at index: Int) {
        viewController?.undoManager?.registerUndo(withTarget: self) { target in
            self.thePDFDocument.removePage(at: index)
        }
    }
    
    
    func deletePage(at index: Int) {
        guard let page = thePDFDocument.page(at: index) else { return }
        thePDFDocument.removePage(at: index)
        registerUndoForRemove(page: page, at: index)
    }
    
    private func registerUndoForRemove(page: PDFPage, at index: Int) {
        viewController?.undoManager?.registerUndo(withTarget: self) { target in
            self.thePDFDocument.insert(page, at: index)
        }
    }
    
    
}
