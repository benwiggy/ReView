//
//  ViewController.swift
//  ReView
//
//  Created by Ben on 14/03/2019.
//  A Free and open source project.

import Cocoa
import Quartz

class MySplitViewController: NSSplitViewController {
    
    // SETUP
    
    var pdfViewController: PDFViewController? {
        splitViewItems[1].viewController as? PDFViewController
    }
    
    var thumbnailViewController: ThumbnailViewController? {
        splitViewItems[0].viewController as? ThumbnailViewController
    }
    
    var thePDFView: PDFView? {
        pdfViewController?.thePDFView
    }
    
    var theThumbnailView: PDFThumbnailView? {
        thumbnailViewController?.theThumbnailView
    }
    
    var searchResults: [PDFSelection] = []
    var currentSearchIndex: Int = 0
    
    var document: Document? {
        pdfViewController?.representedObject as? Document
    }
    
    // These should be prefs
    var theDisplayMode: PDFDisplayMode! = .singlePageContinuous
    var bookState: Bool = true
    let defaults = UserDefaults.standard

    // OVERRIDES
    override func viewDidLoad() {
        super.viewDidLoad()
        thumbnailViewController?.theThumbnailView?.pdfView = thePDFView
        loadViewParameters()
    }
    
    func loadViewParameters()  {
        pdfViewController?.loadViewParameters()
    }
    
    override func viewWillAppear() {
        loadViewParameters()
        
    }
    
    override var representedObject: Any? {
        didSet {
            loadViewParameters()
        }
    }

    @IBAction func sidebar(_ sender: Any?){
        splitViewItems[0].isCollapsed = !splitViewItems[0].isCollapsed
    }
}

