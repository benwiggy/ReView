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
    
    
    override func newDocument(_ sender: Any?) {
         let myFavoriteTypes = [NSPasteboard.PasteboardType.pdf, NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff]
         let pboard = NSPasteboard.general
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

}


/*
        myFavoriteTypes = [NSPasteboardTypePDF, NSPasteboardTypeTIFF, NSPasteboardTypePNG, NSTIFFPboardType, NSPICTPboardType, 'com.adobe.encapsulated-postscript']
        pb = NSPasteboard.generalPasteboard()
        best_type = pb.availableTypeFromArray_(myFavoriteTypes)
        if best_type:
            clipData = pb.dataForType_(best_type)
            if clipData:
                image = NSImage.alloc().initWithPasteboard_(pb)
                if image:
                    page = Quartz.PDFPage.alloc().initWithImage_(image)

                
                else:
                    pageData = page.dataRepresentation()
                    myFile = Quartz.PDFDocument.alloc().initWithData_(pageData)
        */
