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
    
    // Provide warning that Save will overwrite the existing file. Also allow user to turn it off.
    override func save(_ sender: Any?) {
        let defaults = UserDefaults.standard
        let alertSupressionKey = "AlertAlertSupression"
        
        // Reset default for testing
        // defaults.set(false, forKey: alertSupressionKey)
        
        switch defaults.bool(forKey: alertSupressionKey){
        case false:
            let alert = NSAlert()
            alert.messageText = "Save Document?"
            alert.informativeText = "ReView currently has no editing capabilities. \rSaving will 'rinse' the document through PDFKit."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Save As..")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            
            // Would prefer a sheet, but don't know which window it is.
            let result = alert.runModal()
            if alert.suppressionButton?.state == .on {
                defaults.set(true, forKey: alertSupressionKey)
            }
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
    

    
}

