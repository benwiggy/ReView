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

    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override func viewDidAppear() {
        let document = self.view.window?.windowController?.document as! Document
        self.thePDFView.document = document.thePDFDocument
        self.thePDFView.autoScales = true
        self.theThumbnailView.pdfView = self.thePDFView
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
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
    printOperation?.run()
    }
    
}

