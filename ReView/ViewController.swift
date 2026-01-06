//
//  ViewController.swift
//  ReView
//
//  Created by Ben on 14/03/2019.
//  A Free and open source project.

import Cocoa
import Quartz

class ViewController: NSViewController {

    // SETUP
    @IBOutlet var thePDFView: PDFView!
    @IBOutlet var theThumbnailView: PDFThumbnailView!
    @IBOutlet weak var searchField: NSSearchField!
    
    var searchResults: [PDFSelection] = []
    var currentSearchIndex: Int = 0

    
    var document: Document! {
         //return self.view.window?.windowController?.document as? Document
        return self.representedObject as? Document
     }
    

    
    // These should be prefs
    var theDisplayMode: PDFDisplayMode! = .singlePageContinuous
    var bookState: Bool = true
    let defaults = UserDefaults.standard
    
    
    
    
    // View menu commands
    
    
    @IBAction func changePageStyle(_ sender: NSMenuItem) {
        // Update display mode
        switch sender.tag {
        case 0: theDisplayMode = .singlePage
        case 1: theDisplayMode = .singlePageContinuous
        case 2: theDisplayMode = .twoUp
        case 3: theDisplayMode = .twoUpContinuous
        default:
            return
        }
        thePDFView.displayMode = theDisplayMode

        // Update checkmarks
        if let menu = sender.menu {
            for item in menu.items where item.action == #selector(changePageStyle(_:)) {
                item.state = (item == sender) ? .on : .off
            }
        }
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
    
      
    // Setting defaults prefs, but not reading them
    @IBAction func FirstCover(_ sender: NSMenuItem) {
        let bookStateKey = "bookState"
        if thePDFView.displaysAsBook {
           thePDFView.displaysAsBook = false
            sender.state = .off
            bookState = false
            self.defaults.set(false, forKey: bookStateKey)
        } else {
            thePDFView.displaysAsBook = true
            sender.state = .on
            bookState = true
             self.defaults.set(true, forKey: bookStateKey)
        }
    }
    
    
    // FUNCTIONS THAT EDIT
    // TO DO: Make Undo function
    
    @IBAction func addBlank(_sender: Any?) {
        if let selectedPages = theThumbnailView.selectedPages {
            // let selectedPageNo: Int? = (thePDFView.document!.index(for: thePDFView.currentPage!))
            for page in selectedPages {
            let pageSize = page.bounds(for: .mediaBox)
            let blankPage = PDFPage.init()
            blankPage.setBounds(pageSize, for: .mediaBox)
                document.insert(blankPage: blankPage, at: ((document!.thePDFDocument!.index(for: page))))
            }
            document!.rinse()
        }
    }
    
    @IBAction func rotateLeft(_sender: Any? ) {
        if let selectedPages = theThumbnailView.selectedPages {
            for page in selectedPages {
                let existingRotation = page.rotation
                let newRotation = existingRotation - 90
                let pageIndex = (page.document!.index(for: page))
                document.setRotation(newRotation, forPageAt: pageIndex)
                }
            loadViewParameters()
        }
    }
    
    @IBAction func rotateRight(_sender: Any? ) {
        if let selectedPages = theThumbnailView.selectedPages {
        for page in selectedPages {
            let existingRotation = page.rotation
            let newRotation = existingRotation + 90
            let pageIndex = (page.document!.index(for: page))
            document.setRotation(newRotation, forPageAt: pageIndex)
            }
            loadViewParameters()
        }
    }
    
    @IBAction func deletePage(_sender: Any?) {
        if let pageCount = thePDFView.document?.pageCount {
            if pageCount > 1 {
                if let selectedPages = theThumbnailView.selectedPages {
                for page in selectedPages {
                
                let selectedPageNo: Int? = (thePDFView.document!.index(for: thePDFView.currentPage!))
              
                    let alert = NSAlert()
                    alert.messageText = "Delete Page"
                    alert.informativeText = ("Do you want to delete page " + String(selectedPageNo!+1) + "?")
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Cancel")
                    let result = alert.runModal()
                    switch result {
                    case NSApplication.ModalResponse.alertFirstButtonReturn:
                        document.deletePage(at: selectedPageNo!)
                    case NSApplication.ModalResponse.alertSecondButtonReturn:
                        break
                    default:
                        break
                        }

                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "No Page Selected"
                    alert.informativeText = "Select a page in the Thumbnail pane."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    }
                    
                
            } else {
                let alert = NSAlert()
                alert.messageText = "Only One Page"
                alert.informativeText = "ReView will not delete the only page."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    @IBAction func applyFilter(_sender: Any?) {
    
        let storyboardName = NSStoryboard.Name(stringLiteral: "Main")
        let storyboard = NSStoryboard(name: storyboardName, bundle: nil)
        let storyboardID = NSStoryboard.SceneIdentifier(stringLiteral: "quartzPanelID")
         
        if let quartzWindowController = storyboard.instantiateController(withIdentifier: storyboardID) as? NSWindowController {
        //    if let quartzPanelVC = quartzWindowController.contentViewController as? quartzPanelViewController {
        
                
        //    }
            quartzWindowController.showWindow(nil)
        }
    }
    
    
    // SEARCH
    
    @IBAction func search2(_ sender: NSSearchField) {
        let searchText = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure we have text and a PDFDocument
        guard !searchText.isEmpty, let pdfDocument = document?.thePDFDocument else {
            // Clear previous results if search is empty
            searchResults = []
            currentSearchIndex = 0
            thePDFView.clearSelection()
            return
        }
        
        // Perform the search asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Find all matches (case-insensitive)
            let matches = pdfDocument.findString(searchText, withOptions: .caseInsensitive)
            
            DispatchQueue.main.async {
                self.searchResults = matches
                self.currentSearchIndex = 0
                
                if matches.isEmpty {
                    // No matches found
                    self.thePDFView.clearSelection()
                    NSSound.beep()  // system alert
                } else {
                    // Highlight first match
                    self.highlightCurrentSearchResult()
                }
            }
        }
    }

    // Highlight the currently selected search result
    func highlightCurrentSearchResult() {
        guard !searchResults.isEmpty else { return }
        
        let selection = searchResults[currentSearchIndex]
        thePDFView.currentSelection = selection
        thePDFView.scrollSelectionToVisible(self)
    }

    // Go to next search result
    @IBAction func goToNextSearchResult(_ sender: Any?) {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
        highlightCurrentSearchResult()
    }

    // Go to previous search result
    @IBAction func goToPreviousSearchResult(_ sender: Any?) {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
        highlightCurrentSearchResult()
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleDocumentReverted), name: .documentReverted, object: nil)
        theThumbnailView.maximumNumberOfColumns = 1
        theThumbnailView.allowsMultipleSelection = true
        let theThumbnailSize = CGSize(width: 200, height: 200)
        if #available(OSX 10.13, *) {
            thePDFView.acceptsDraggedFiles = true
            theThumbnailView.allowsDragging = true
        } else {
            thePDFView.allowsDragging = true
        }
        theThumbnailView?.thumbnailSize = theThumbnailSize
    }
    
  func loadViewParameters()  {
        thePDFView?.document = document?.thePDFDocument
        thePDFView.layoutDocumentView()
      thePDFView.autoScales = true   // always fit to window
     //   thePDFView.setNeedsDisplay(view.bounds)
        theThumbnailView.pdfView = self.thePDFView
        theThumbnailView.setNeedsDisplay(view.bounds)
    // "Go to same page" reselects the page in thumbnail
    thePDFView.goToNextPage(Any?.self)
    thePDFView.goToPreviousPage(Any?.self)
    }
    
    override func viewWillAppear() {
         loadViewParameters()
    }

    override var representedObject: Any? {
        didSet {
        loadViewParameters()
        }
    }
    
    @objc func handleDocumentReverted(_ note: Notification) {
      let sendingDocument = note.object as? Document
      guard sendingDocument == document else { return }
       loadViewParameters()
      thePDFView.setNeedsDisplay(thePDFView.bounds)
      theThumbnailView.setNeedsDisplay(theThumbnailView.bounds)
       
    }
    
    /*
    func getOutlines: {
        // let theOutline = PDFOutline.init()
        let theOutline = document.thePDFDocument?.outlineRoot
    }
 */
     

    
    
}

