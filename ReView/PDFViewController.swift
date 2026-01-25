//
//  ViewController.swift
//  ReView
//
//  Created by Ben on 14/03/2019.
//  A Free and open source project.

import Cocoa
import Quartz

class PDFViewController: NSViewController, NSMenuItemValidation {
    
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

    
    // Functions for User prefs for Viewing Styles
    private enum DefaultsKeys {
        static let pageViewStyle = "pageViewStyle"   // Int: 0=singlePage, 1=singlePageContinuous, 2=twoUp, 3=twoUpContinuous
        static let bookState = "bookState"           // Bool: displaysAs First Page on its own in 2-up views.
        static let horizontal = "horizontal"         // Bool: horizontal display in Single Continuous.
    }
    
    let defaults = UserDefaults.standard

      var theDisplayMode: PDFDisplayMode!
      var bookState: Bool = true
      var theDisplayDirection: PDFDisplayDirection!
    
    func registerDefaults() {
        defaults.register(defaults: [
            DefaultsKeys.pageViewStyle: 1,      // singlePageContinuous
            DefaultsKeys.bookState: true,
            DefaultsKeys.horizontal: false
        ])
    }

    func loadDefaults() {
        // Page style
        let styleValue = defaults.integer(forKey: DefaultsKeys.pageViewStyle)
        switch styleValue {
        case 0: theDisplayMode = .singlePage
        case 1: theDisplayMode = .singlePageContinuous
        case 2: theDisplayMode = .twoUp
        case 3: theDisplayMode = .twoUpContinuous
        default: theDisplayMode = .singlePageContinuous
        }

        // Book mode
        bookState = defaults.bool(forKey: DefaultsKeys.bookState)

        // Display direction
        let horizontal = defaults.bool(forKey: DefaultsKeys.horizontal)
        theDisplayDirection = horizontal ? .horizontal : .vertical
    }

    func applyDefaultsToPDFView() {
        guard let pdfView = thePDFView else { return }
        pdfView.displayMode = theDisplayMode
        pdfView.displaysAsBook = bookState
        pdfView.displayDirection = theDisplayDirection
        pdfView.autoScales = true
    }
    
    
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
    
    func updateBookStateMenu() {
        guard let mainMenu = NSApp.mainMenu,
              let viewMenu = mainMenu.item(withTitle: "View")?.submenu else { return }

        for item in viewMenu.items where item.action == #selector(FirstCover(_:)) {
            item.state = bookState ? .on : .off
        }
    }
    
    // FOUR separate functions, just to get Horizontal/Vertical menu items working..!!!!
    
    //- Menu validation.
     func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
         switch menuItem.action {

         case #selector(toggleHorizontal(_:)):
             menuItem.state = (theDisplayDirection == .horizontal) ? .on : .off
             return thePDFView.displayMode == .singlePageContinuous

         case #selector(toggleVertical(_:)):
             menuItem.state = (theDisplayDirection == .vertical) ? .on : .off
             return thePDFView.displayMode == .singlePageContinuous

         case #selector(changePageStyle(_:)):
             guard let pdfView = thePDFView else { return false }
             switch pdfView.displayMode {
             case .singlePage: menuItem.state = (menuItem.tag == 0) ? .on : .off
             case .singlePageContinuous: menuItem.state = (menuItem.tag == 1) ? .on : .off
             case .twoUp: menuItem.state = (menuItem.tag == 2) ? .on : .off
             case .twoUpContinuous: menuItem.state = (menuItem.tag == 3) ? .on : .off
             default: menuItem.state = .off
             }
             return true

         default:
             return true
         }
     }
    
    
    func applyDisplayDirection(_ direction: PDFDisplayDirection) {
        guard let pdfView = thePDFView else { return }

        let currentPage = pdfView.currentPage

        theDisplayDirection = direction
        pdfView.displayDirection = direction

        if let page = currentPage {
            pdfView.go(to: page)
        }
    }
    
    @IBAction func toggleHorizontal(_ sender: Any?) {
        applyDisplayDirection(.horizontal)
        }

    @IBAction func toggleVertical(_ sender: Any?) {
        applyDisplayDirection(.vertical)
    }
    
        
    // OVERRIDES
    override func viewDidLoad() {
        super.viewDidLoad()
        
        registerDefaults()
         loadDefaults()
        applyDefaultsToPDFView()
        updatePageStyleMenu(for: theDisplayMode)
        updateBookStateMenu()
        
        // The rest of the setup…
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
        super.viewWillAppear()
        loadViewParameters()
        
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }
    

    override var representedObject: Any? {
        didSet {
            loadViewParameters()
        }
    }
    
    // MARK: - Search functions
    
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
        thePDFView.scaleFactor = thePDFView.scaleFactorForSizeToFit
        thePDFView.displayDirection = theDisplayDirection
        theThumbnailView?.pdfView = self.thePDFView
        theThumbnailView?.setNeedsDisplay(view.bounds)
        // "Go to same page" reselects the page in thumbnail
        thePDFView.goToNextPage(Any?.self)
        thePDFView.goToPreviousPage(Any?.self)
     //   thePDFView.goToFirstPage(Any?.self)
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

