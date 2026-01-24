//
//  DocumentController.swift
//  ReView
//
//  Created by Ben Byram-Wigfield on 10/11/2019.
//  Copyright © 2019 Ben. All rights reserved.
//

import Cocoa
import Quartz



final class DocumentController: NSDocumentController {
    

    
    @objc func myNewFile(_ sender: Any?) {
        let pboard = NSPasteboard.general

        // 1 Check for PDF
        if let data = pboard.data(forType: .pdf),
           let pdf = PDFDocument(data: data) {
            createDocument(from: pdf)
            return
        }

        // 2 Check for valid image
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if let _ = pboard.availableType(from: imageTypes),
           let image = NSImage(pasteboard: pboard),
           let page = PDFPage(image: image),
           page.bounds(for: .mediaBox).width > 0,
           page.bounds(for: .mediaBox).height > 0
        {
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)
            createDocument(from: pdf)
            return
        }

        // 3 Nothing usable — show alert
        let alert = NSAlert()
        alert.messageText = "No PDF or Image on Clipboard"
        alert.informativeText = "The clipboard does not contain a valid PDF or image."
        alert.runModal()
    }
    
    
    override func newDocument(_ sender: Any?) {
        let pboard = NSPasteboard.general

        // 1. Try PDF data directly
        if let data = pboard.data(forType: .pdf), let pdf = PDFDocument(data: data) {
            createDocument(from: pdf)
            return
        }

        // 2. Try common image types
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if let bestType = pboard.availableType(from: imageTypes),
           let image = NSImage(pasteboard: pboard),
           image.representations.contains(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {

            // Create PDFPage from image and check it has content
            if let page = PDFPage(image: image),
               page.bounds(for: .mediaBox).width > 0,
               page.bounds(for: .mediaBox).height > 0 {

                let pdf = PDFDocument()
                pdf.insert(page, at: 0)
                createDocument(from: pdf)
                return
            }
        }

        // 3. Nothing usable
        let alert = NSAlert()
        alert.messageText = "No PDF or Image on Clipboard"
        alert.informativeText = "The clipboard does not contain a valid PDF or image."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let pboard = NSPasteboard.general
        if let data = pboard.data(forType: .pdf), PDFDocument(data: data) != nil {
            return try super.makeUntitledDocument(ofType: typeName)
        }
        if let image = NSImage(pasteboard: pboard),
           let page = PDFPage(image: image),
           page.bounds(for: .mediaBox).width > 0,
           page.bounds(for: .mediaBox).height > 0 {
            return try super.makeUntitledDocument(ofType: typeName)
        }

        // Otherwise, prevent window creation
        throw NSError(domain: "ReView", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "No PDF or image on clipboard"
        ])
    }
    
    
    private func createDocument(from pdf: PDFDocument) {
        do {
            let document = try makeUntitledDocument(ofType: "pdf") as! Document

            document.load(pdfDocument: pdf)

            addDocument(document)
            document.makeWindowControllers()
            document.showWindows()

        } catch {
            NSAlert(error: error).runModal()
        }
    }
    

}


/*
 override func newDocument(_ sender: Any?) {
      let myFavoriteTypes = [NSPasteboard.PasteboardType.pdf, NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff]
      let pboard = NSPasteboard.general
     print("qwe")
      if let bestType = pboard.availableType(from: myFavoriteTypes) {
          if pboard.data(forType: bestType) != nil{
              if let image = NSImage.init(pasteboard: pboard){
                  let page = PDFPage.init(image: image)
                  let pageData = page?.dataRepresentation
                  }
              }
      }
     else
      {
         let alert = NSAlert()
         alert.messageText = "No Clipboard Data"
         alert.informativeText = "No suitable Clipboard data has been found"
         alert.addButton(withTitle: "OK")

         let result = alert.runModal()
     }
     
     }
        */
