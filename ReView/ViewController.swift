//
//  ViewController.swift
//  ReView
//
//  Created by Ben on 14/03/2019.
//  A Free and open source project.

import Cocoa
import Quartz

class ViewController: NSViewController {

    @IBOutlet var thePDFView: PDFView!
    @IBOutlet var theThumbnailView: PDFThumbnailView!

    @IBOutlet var theTabView: NSTabView!
    @IBOutlet var PageView: NSTabViewItem!
    @IBOutlet var ToCTab: NSTabViewItem!
    
    
    // View menu commands
    @IBAction func singlePage(_ sender: NSMenuItem) {
        self.thePDFView.displayMode = .singlePage
    }
    
    @IBAction func singleCont(_ sender: NSMenuItem) {
        self.thePDFView.displayMode = .singlePageContinuous
    }
    
    @IBAction func TwoPages(_ sender: NSMenuItem) {
        self.thePDFView.displayMode = .twoUp
    }
    
    @IBAction func TwoCont(_ sender: NSMenuItem) {
        self.thePDFView.displayMode = .twoUpContinuous
    }
    
    @IBAction func FirstCover(_ sender: NSMenuItem) {
        if self.thePDFView.displaysAsBook {
           self.thePDFView.displaysAsBook = false
            sender.state = .off
        } else {
            self.thePDFView.displaysAsBook = true
            sender.state = .on
        }
    }
    
    
    override func viewDidLoad() {

        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    override func viewDidAppear() {
        let theThumbnailSize = CGSize(width: 200, height: 200)
        let document = self.view.window?.windowController?.document as! Document
        self.thePDFView?.document = document.thePDFDocument
        self.thePDFView?.autoScales = true
        self.thePDFView?.displayMode = .singlePageContinuous
        self.thePDFView?.displaysAsBook = true
       self.theThumbnailView?.pdfView = self.thePDFView
       self.theThumbnailView?.thumbnailSize = theThumbnailSize
    }
    

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    /*
    func getOutlines: {
        let document = self.view.window?.windowController?.document as! Document
        // let theOutline = PDFOutline.init()
        let theOutline = document.thePDFDocument?.outlineRoot
    }
 */
    
    // Make sure our page is centred on the paper, to avoid uneven margins.
    // (This gives the best fit when duplexing.)
    func thePrintInfo() -> NSPrintInfo {
        let thePrintInfo = NSPrintInfo()
        thePrintInfo.horizontalPagination = .fit
        thePrintInfo.verticalPagination = .fit
        thePrintInfo.isHorizontallyCentered = true
        thePrintInfo.isVerticallyCentered = true
        thePrintInfo.leftMargin = 0.0
        thePrintInfo.rightMargin = 0.0
        thePrintInfo.topMargin = 0.0
        thePrintInfo.bottomMargin = 0.0
        thePrintInfo.jobDisposition = .spool
        return thePrintInfo
    }
    
    // Add the Page Setup options to the Print Dialog
    func thePrintPanel() -> NSPrintPanel {
        let thePrintPanel = NSPrintPanel()
        thePrintPanel.options = [
            NSPrintPanel.Options.showsCopies,
            NSPrintPanel.Options.showsPrintSelection,
            NSPrintPanel.Options.showsPageSetupAccessory,
            NSPrintPanel.Options.showsPreview
        ]
        return thePrintPanel
    }
    
    // File > Print menu item.
    @IBAction func printContent(_ sender: Any) {
       let printOperation = thePDFView.document?.printOperation(for: thePrintInfo(), scalingMode: .pageScaleNone, autoRotate: true)
    printOperation?.printPanel = thePrintPanel()
       /// Would prefer to use .runModal but don't know what the parameters should be.
    printOperation?.run()
    }
    
    
}

