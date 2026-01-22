//
//  ViewController.swift
//  ReView
//
//  Created by Ben on 14/03/2019.
//  A Free and open source project.

import Cocoa
import Quartz

class PDFViewController: NSViewController {
    
    // SETUP
    @IBOutlet var thePDFView: PDFView!

    var thumbnailViewController: ThumbnailViewController? {
        (parent as? NSSplitViewController)?.splitViewItems[0].viewController as? ThumbnailViewController
    }
    
    var theThumbnailView: PDFThumbnailView? {
        thumbnailViewController?.theThumbnailView
    }
    
    var searchResults: [PDFSelection] = []
    var currentSearchIndex: Int = 0
    
    var document: Document! {
        representedObject as? Document
    }
    
    // These should be prefs
    var theDisplayMode: PDFDisplayMode! = .singlePageContinuous
    var bookState: Bool = true
    let defaults = UserDefaults.standard
    
    
    func updatePageStyleMenu(for mode: PDFDisplayMode) {
        guard let mainMenu = NSApp.mainMenu,
              let viewMenu = mainMenu.item(withTitle: "View")?.submenu else { return }
        
        for item in viewMenu.items where item.action == #selector(changePageStyle(_:)) {
            switch mode {
            case .singlePage: item.state = (item.tag == 0) ? .on : .off
            case .singlePageContinuous: item.state = (item.tag == 1) ? .on : .off
            case .twoUp: item.state = (item.tag == 2) ? .on : .off
            case .twoUpContinuous: item.state = (item.tag == 3) ? .on : .off
            default: item.state = .off
            }
        }
    }
        
    // OVERRIDES
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Register initial defaults (only used if keys don’t exist yet)
        defaults.register(defaults: [
            "pageViewStyle": 1,   // 0=singlePage, 1=singlePageContinuous, 2=twoUp, 3=twoUpContinuous
            "bookState": true
        ])
        
        //  Read saved values
        var savedTag: Int
        if let existingValue = defaults.object(forKey: "pageViewStyle") as? Int {
            savedTag = existingValue
        } else {
            // first-time: write the default into plist
            savedTag = 1
            defaults.set(savedTag, forKey: "pageViewStyle")
        }
        
        let savedBookState: Bool
        if defaults.object(forKey: "bookState") != nil {
            savedBookState = defaults.bool(forKey: "bookState")
        } else {
            savedBookState = true
            defaults.set(savedBookState, forKey: "bookState")
        }
        
        
        // Now read them safely
        switch savedTag {
        case 0: theDisplayMode = .singlePage
        case 1: theDisplayMode = .singlePageContinuous
        case 2: theDisplayMode = .twoUp
        case 3: theDisplayMode = .twoUpContinuous
        default: theDisplayMode = .singlePageContinuous
        }
        
        bookState = defaults.bool(forKey: "bookState")
        
        // Apply
        thePDFView.displayMode = theDisplayMode
        thePDFView.displaysAsBook = bookState
        updatePageStyleMenu(for: theDisplayMode)
        
        // The rest of your setup…
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleDocumentReverted),
                                               name: .documentReverted,
                                               object: nil)

        if #available(OSX 10.13, *) {
            thePDFView.acceptsDraggedFiles = true
        } else {
            thePDFView.allowsDragging = true
        }
    }
    
    override func viewWillAppear() {
        loadViewParameters()
        
    }
    
    override var representedObject: Any? {
        didSet {
            loadViewParameters()
        }
    }
    
    // Highlight the currently selected search result
    func highlightCurrentSearchResult() {
        guard !searchResults.isEmpty else { return }
        
        let selection = searchResults[currentSearchIndex]
        thePDFView.currentSelection = selection
        thePDFView.scrollSelectionToVisible(self)
    }
        
    // Highlight the search box
    func focusSearchField() {
        guard
            let window = view.window,
            let toolbar = window.toolbar
        else { return }
        
        for item in toolbar.items {
            if let searchField = item.view as? NSSearchField {
                window.makeFirstResponder(searchField)
                break
            }
        }
    }
    
    func loadViewParameters()  {
        thePDFView?.document = document?.thePDFDocument
        thePDFView.layoutDocumentView()
        thePDFView.autoScales = true   // always fit to window
        //   thePDFView.setNeedsDisplay(view.bounds)
        theThumbnailView?.pdfView = self.thePDFView
        theThumbnailView?.setNeedsDisplay(view.bounds)
        // "Go to same page" reselects the page in thumbnail
        thePDFView.goToNextPage(Any?.self)
        thePDFView.goToPreviousPage(Any?.self)
    }
        
    @objc func handleDocumentReverted(_ note: Notification) {
        let sendingDocument = note.object as? Document
        guard sendingDocument == document else { return }
        loadViewParameters()
        thePDFView.setNeedsDisplay(thePDFView.bounds)
        theThumbnailView?.setNeedsDisplay(theThumbnailView!.bounds)
        
    }
    
    /*
     func getOutlines: {
        // let theOutline = PDFOutline.init()
        let theOutline = document.thePDFDocument?.outlineRoot
     }
     */
}

