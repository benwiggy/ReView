//
//  Document.swift
//  MyPreview
//
//  Created by Ben on 14/03/2019.
//  
//

import Cocoa
import Quartz

class Document: NSDocument {
    var thePDFDocument: PDFDocument?

    override init() {
        super.init()
        // Add your subclass-specific initialization here.
    }

    // NO! We do not want our precious originals overwritten!
    override class var autosavesInPlace: Bool {
        return false
    }

    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller")) as! NSWindowController
        self.addWindowController(windowController)
    }

    override func data(ofType typeName: String) throws -> Data {
        // Insert code here to write your document to data of the specified type, throwing an error in case of failure.
        // Alternatively, you could remove this method and override fileWrapper(ofType:), write(to:ofType:), or write(to:ofType:for:originalContentsURL:) instead.
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        self.thePDFDocument = PDFDocument.init(data: data)
        if self.thePDFDocument == nil {
            throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
        }
    }
    
}

