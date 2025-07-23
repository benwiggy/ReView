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
    
    var document: Document! {
         //return self.view.window?.windowController?.document as? Document
        return self.representedObject as? Document
     }

    
    // These should be prefs
    var theDisplayMode: PDFDisplayMode! = .singlePageContinuous
    var bookState: Bool = true
    let defaults = UserDefaults.standard
    
    
    
    
    // View menu commands
    @IBAction func singlePage(_ sender: NSMenuItem) {
        self.theDisplayMode = .singlePage
        self.thePDFView.displayMode = theDisplayMode
    }
    
    @IBAction func singleCont(_ sender: NSMenuItem) {
        self.theDisplayMode = .singlePageContinuous
        self.thePDFView.displayMode = theDisplayMode
    }
    
    @IBAction func TwoPages(_ sender: NSMenuItem) {
        self.theDisplayMode = .twoUp
        self.thePDFView.displayMode = theDisplayMode
    }
    
    @IBAction func TwoCont(_ sender: NSMenuItem) {
        self.theDisplayMode = .twoUpContinuous
        self.thePDFView.displayMode = theDisplayMode
    }
    
    // Setting defaults prefs, but not reading them
    @IBAction func FirstCover(_ sender: NSMenuItem) {
        let bookStateKey = "bookState"
        if self.thePDFView.displaysAsBook {
           self.thePDFView.displaysAsBook = false
            sender.state = .off
            bookState = false
            self.defaults.set(false, forKey: bookStateKey)
        } else {
            self.thePDFView.displaysAsBook = true
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
    
    
    // OVERRIDES
    override func viewDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleDocumentReverted), name: .documentReverted, object: nil)
        self.theThumbnailView.maximumNumberOfColumns = 1
        self.theThumbnailView.allowsMultipleSelection = true
        let theThumbnailSize = CGSize(width: 200, height: 200)
        self.thePDFView?.displayMode = theDisplayMode
        self.thePDFView?.displaysAsBook = bookState
        if #available(OSX 10.13, *) {
             self.thePDFView.acceptsDraggedFiles = true
            self.theThumbnailView.allowsDragging = true
         } else {
             self.thePDFView.allowsDragging = true
         }
        self.theThumbnailView?.thumbnailSize = theThumbnailSize
        // Do any additional setup after loading the view.
    }
    
  func loadViewParameters()  {
    self.thePDFView?.document = document?.thePDFDocument
        self.thePDFView.layoutDocumentView()
        self.thePDFView.setNeedsDisplay(view.bounds)
        self.theThumbnailView.pdfView = self.thePDFView
        self.theThumbnailView.setNeedsDisplay(view.bounds)
    // "Go to same page" reselects the page in thumbnail
    self.thePDFView.goToNextPage(Any?.self)
    self.thePDFView.goToPreviousPage(Any?.self)
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

