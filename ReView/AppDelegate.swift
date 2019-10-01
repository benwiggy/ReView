//
//  AppDelegate.swift
//  MyPreview
//
//  Created by Ben on 14/03/2019.
//  
//

import Cocoa
// import PDFKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    

    
    
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
   
    /*
      @IBAction func newDocument(_ sender: Any?) {
        let myFavoriteTypes = [NSPasteboard.PasteboardType.pdf, NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType.postScript]
        let pboard = NSPasteboard.general
        if let bestType = pboard.availableType(from: myFavoriteTypes) {
            if let clipData = pboard.data(forType: bestType){
                if let image = NSImage.init(pasteboard: pboard){
                    let page = PDFPage.init(image: image)
                    let pageData = page?.dataRepresentation
                    
                }
                
            }
            
        }
       
 */
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
          
      


}

