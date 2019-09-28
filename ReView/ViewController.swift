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
    @IBAction func rotateLeft(_sender: Any? ) {
        if let selectedPage = thePDFView.currentPage {
            let existingRotation = selectedPage.rotation
            let newRotation = existingRotation - 90
            selectedPage.rotation = newRotation
            document?.updateChangeCount(.changeDone)
            thePDFView.setNeedsDisplay(view.bounds)
        }
    }
    
    @IBAction func rotateRight(_sender: Any? ) {
        if let selectedPage = thePDFView.currentPage {
            let existingRotation = selectedPage.rotation
            let newRotation = existingRotation + 90
            selectedPage.rotation = newRotation
            document?.updateChangeCount(.changeDone)
            thePDFView.setNeedsDisplay(view.bounds)
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
                        theThumbnailView.setNeedsDisplay(CGRect(x: 0, y: 0, width: 0, height: 0))
                        document?.updateChangeCount(.changeDone)
                        thePDFView.setNeedsDisplay(view.bounds)
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
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDocumentReverted), name: .documentReverted, object: nil)
        // Do any additional setup after loading the view.
    }
    
    override func viewDidAppear() {
        
        let theThumbnailSize = CGSize(width: 200, height: 200)
        self.thePDFView?.document = document?.thePDFDocument
        // self.thePDFView?.autoScales = true
        self.thePDFView?.displayMode = theDisplayMode
        self.thePDFView?.displaysAsBook = bookState

        self.theThumbnailView?.pdfView = self.thePDFView
        self.theThumbnailView?.thumbnailSize = theThumbnailSize
    }
    

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    @objc func handleDocumentReverted(_ note: Notification) {
      let sendingDocument = note.object as? Document
      guard sendingDocument == document else { return }
      thePDFView.setNeedsDisplay(view.bounds)
        NSLog("qwe")
    }  
    
    /*
    func getOutlines: {
        let document = self.view.window?.windowController?.document as! Document
        // let theOutline = PDFOutline.init()
        let theOutline = document.thePDFDocument?.outlineRoot
    }
 */
     

    
    
}

