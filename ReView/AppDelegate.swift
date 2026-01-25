//
//  AppDelegate.swift
//  MyPreview
//
//  Created by Ben on 14/03/2019.
//  
//

//
//  AppDelegate.swift
//  MyPreview
//

import Cocoa
import PDFKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire the “New from Clipboard” menu programmatically
        if let newMenuItem = NSApp.mainMenu?
            .item(withTitle: "File")?
            .submenu?
            .item(withTitle: "New from Clipboard") {
            newMenuItem.target = self
            newMenuItem.action = #selector(myNewFile(_:))
            newMenuItem.isEnabled = true // always enabled
        }
    }

    // MARK: - Clipboard-based New command
    @IBAction func myNewFile(_ sender: Any?) {
        let pboard = NSPasteboard.general

        // 1️⃣ PDF from clipboard
        if let data = pboard.data(forType: .pdf),
           let pdf = PDFDocument(data: data) {
            createDocument(from: pdf)
            return
        }

        // 2️⃣ Image from clipboard
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if let _ = pboard.availableType(from: imageTypes),
           let image = NSImage(pasteboard: pboard),
           let page = PDFPage(image: image) {

            // Create a PDFDocument and insert the page
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)

            // Display the document
            createDocument(from: pdf)
            return
        }

        // 3️⃣ Nothing usable — show alert
        let alert = NSAlert()
        alert.messageText = "No PDF or Image on Clipboard"
        alert.informativeText = "The clipboard does not contain a valid PDF or image."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Create document using NSDocumentController

    private func createDocument(from pdf: PDFDocument) {
        // 1️⃣ Create a new Document instance directly
        let doc = Document()
        print("Created new Document instance")

        // 2️⃣ Assign the PDFDocument to the document property
        doc.load(pdfDocument: pdf)

        // 3️⃣ Setup window controllers and show the window
        doc.makeWindowControllers()
        doc.showWindows()
        print("Window controllers created and shown: \(doc.windowControllers.count)")

        // 4️⃣ Assign the PDFDocument to the PDFView inside your SplitView
        if let pdfView = doc.viewController?.pdfViewController?.thePDFView {
            pdfView.document = pdf
            print("Assigned PDFDocument to PDFView")
        } else {
            print("Could not find PDFViewController or thePDFView outlet is nil")
        }
    }
    
    
    // Trigger Preferences window from menu item
    @IBAction func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(nil)
        PreferencesWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }
    
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Optional: disable automatic untitled window at launch
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ aNotification: Notification) {}
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

extension AppDelegate {
    // Optional: menu validation to ensure menu is always enabled (or could add custom logic later)
     func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(myNewFile(_:)) {
            return true
        }
        return true
    }
}
