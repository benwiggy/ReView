//
//  ThumbnailViewController.swift
//  ReView
//
//  Created by Ben on 14/03/2019.
//  A Free and open source project.

import Cocoa
import Quartz

class ThumbnailViewController: NSViewController {
    
    // SETUP
    
    @IBOutlet weak var theThumbnailView: PDFThumbnailView!
    @IBOutlet weak var searchField: NSSearchField!
    @IBOutlet weak var theSplitView: NSSplitView!
    
    var searchResults: [PDFSelection] = []
    var currentSearchIndex: Int = 0
    
    var pdfViewController: PDFViewController? {
        (parent as? NSSplitViewController)?.splitViewItems[1].viewController as? PDFViewController
    }
    
    var thePDFView: PDFView? {
        pdfViewController?.thePDFView
    }
    
    var document: Document? {
        pdfViewController?.document
    }
    
    // FUNCTIONS THAT EDIT
    // TO DO: Make Undo function
        
    // OVERRIDES
    override func viewDidLoad() {
        super.viewDidLoad()
        theThumbnailView.maximumNumberOfColumns = 1
        theThumbnailView.allowsMultipleSelection = true
        theThumbnailView?.thumbnailSize = CGSize(width: 200, height: 200)
        if #available(OSX 10.13, *) {
            theThumbnailView.allowsDragging = true
        }
    }
}

