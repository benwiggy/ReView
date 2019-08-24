//
//  Scrapbook.swift
//  ReView
//
//  Created by Ben on 23/08/2019.
//  Copyright © 2019 Ben. All rights reserved.
//

// THIS IS JUST A PLACE TO PUT RANDOM BITS OF CODE THAT MIGHT BE USEFUL LATER

import Foundation

/*
 
 
 // 
 
static func mergePagesIntoSinglePDF(streamId: String, numPages: Int)
{
    let newPDF = PDFDocument()
    
    newPDF.outlineRoot = PDFOutline();  // CREATE PDF OUTLINE ROOT NODE!
    
    var directoryURLStr = ""
    
    for pageNum in 1...numPages {
        
        let directoryUrl = getFileURL(streamId: streamId, recNum: pageNum)
        directoryURLStr = directoryUrl!.absoluteString
        
        if let pdfDocument = PDFDocument(url: directoryUrl!),
            let pdfPage = pdfDocument.page(at: 0)
        {
            newPDF.insert(pdfPage, at: newPDF.pageCount)
        }
    }
    
    for pageNum in 1...numPages {
        
        let pdfPage = newPDF.page(at: pageNum-1)!
        
        // ADD A LITTLE CODE TO MAKE THE NSPoint IN THE DESTINATION MORE SOUND
        
        let pdfPageRect = pdfPage.bounds(for: PDFDisplayBox.mediaBox)
        let topLeft = NSMakePoint(pdfPageRect.minX, pdfPageRect.height + 20)
        let destination = PDFDestination(page: pdfPage, at: topLeft)
        
        let newDest = PDFDestination(page: pdfPage, at:topLeft)
        let newTOCEntry = PDFOutline()
        
        newTOCEntry.destination = newDest
        newTOCEntry.label = "\(streamId) page \(pageNum)"
        newPDF.outlineRoot!.insertChild(newTOCEntry, at: pageNum-1)
    }
    
    directoryURLStr = (getFileURL(streamId: streamId)?.absoluteString)!
    let fileURL = URL(string: directoryURLStr)
    
    newPDF.write(to: fileURL!)
}

 
 
 
*/
