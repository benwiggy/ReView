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
    var document: Document? {
         return self.view.window?.windowController?.document as? Document
     }
    
    // These should be prefs
    var theDisplayMode: PDFDisplayMode! = .singlePageContinuous
    var bookState: Bool = true
    let defaults = UserDefaults.standard
    
    @IBOutlet var theTabView: NSTabView!
    @IBOutlet var PageView: NSTabViewItem!
    @IBOutlet var ToCTab: NSTabViewItem!
    
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
         if let selectedPage = thePDFView.currentPage {
            let selectedPageNo: Int? = (thePDFView.document!.index(for: thePDFView.currentPage!))
            let pageSize = selectedPage.bounds(for: .mediaBox)
            let blankPage = PDFPage.init()
            blankPage.setBounds(pageSize, for: .mediaBox)
            thePDFView.document!.insert(blankPage, at: selectedPageNo!)
            document?.updateChangeCount(.changeDone)
            loadViewParameters()
        }
    }
    
    @IBAction func rotateLeft(_sender: Any? ) {
        if let selectedPage = thePDFView.currentPage {
            let existingRotation = selectedPage.rotation
            let newRotation = existingRotation - 90
            selectedPage.rotation = newRotation
            document?.updateChangeCount(.changeDone)
            loadViewParameters()
        }
    }
    
    @IBAction func rotateRight(_sender: Any? ) {
        if let selectedPage = thePDFView.currentPage {
            let existingRotation = selectedPage.rotation
            let newRotation = existingRotation + 90
            selectedPage.rotation = newRotation
            document?.updateChangeCount(.changeDone)
            loadViewParameters()
        }
    }
    
    @IBAction func deletePage(_sender: Any?) {
        if let pageCount = thePDFView.document?.pageCount {
            if pageCount > 1 {
                if thePDFView!.currentPage != nil {
                let selectedPageNo: Int? = (thePDFView.document!.index(for: thePDFView.currentPage!))
                if (selectedPageNo != nil)  {
                    let alert = NSAlert()
                    alert.messageText = "Delete Page"
                    alert.informativeText = ("Do you want to delete page " + String(selectedPageNo!+1) + "?")
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Cancel")
                    let result = alert.runModal()
                    switch result {
                    case NSApplication.ModalResponse.alertFirstButtonReturn:
                        thePDFView!.document!.removePage(at: selectedPageNo!)
                        document?.updateChangeCount(.changeDone)
                        loadViewParameters()
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
                alert.informativeText = "ReView cannot delete the only page."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    
    // OVERRIDES
    override func viewDidLoad() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleDocumentReverted), name: .documentReverted, object: nil)
        // Do any additional setup after loading the view.
    }
    
  func loadViewParameters()  {
        self.thePDFView?.document = document?.thePDFDocument
        self.thePDFView.setNeedsDisplay(view.bounds)
        self.theThumbnailView?.pdfView = nil
        self.theThumbnailView?.pdfView = self.thePDFView
        self.theThumbnailView.setNeedsDisplay(view.bounds)
        
    }
    
    override func viewWillAppear() {
        let theThumbnailSize = CGSize(width: 200, height: 200)
        // self.thePDFView?.autoScales = true
        self.thePDFView?.displayMode = theDisplayMode
        self.thePDFView?.displaysAsBook = bookState
        self.theThumbnailView?.thumbnailSize = theThumbnailSize
         loadViewParameters()
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
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
        let document = self.view.window?.windowController?.document as! Document
        // let theOutline = PDFOutline.init()
        let theOutline = document.thePDFDocument?.outlineRoot
    }
 */
     

    
    
}

