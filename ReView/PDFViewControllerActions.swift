//
//  PDFViewControllerActions.swift
//  ReView
//
//  Copyright © 2026 Ben. All rights reserved.
//

import Cocoa
import Quartz

extension PDFViewController {
    // Page Style relates to PDFView appearance
    
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
    
  @objc  @IBAction func changeAxis (_ sender: NSMenuItem) {
        switch sender.tag {
    case 0:
        theDisplayDirection = .horizontal
            menu!.item(withTag: 0)!.state = .on
            menu!.item(withTag: 1)!.state = .off
    case 1:
        theDisplayDirection = .vertical
            menu!.item(withTag: 0)!.state = .off
            menu!.item(withTag: 1)!.state = .on
    default:
        return
    }
        thePDFView.displayDirection = theDisplayDirection
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
    
    
    @IBAction func find(_ sender: Any?) {
        focusSearchField()
    }

    // Setting defaults prefs, but not reading them
    @IBAction func FirstCover(_ sender: NSMenuItem) {
        let bookStateKey = "bookState"
        if thePDFView.displaysAsBook {
            thePDFView.displaysAsBook = false
            sender.state = .off
            bookState = false
        } else {
            thePDFView.displaysAsBook = true
            sender.state = .on
            bookState = true
        }
    }
    
    
    // Functions act on the current selected page. Whether that selection is, or ought to be, the thumbnail or just the "location" of PDFView, I have no idea.
    
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

    @IBAction func addBlank(_ sender: Any?) {
        guard let pdfDoc = document?.thePDFDocument else { return }

        // Use the first selected page or first page as template
        let targetPage = theThumbnailView?.selectedPages?.first ?? pdfDoc.page(at: 0)
        let pageSize = targetPage?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)

        let blankPage = PDFPage()
        blankPage.setBounds(pageSize, for: .mediaBox)

        // Insert **in front of selected page** (or first page)
        let index = targetPage.map { pdfDoc.index(for: $0) } ?? 0
        pdfDoc.insert(blankPage, at: index)

        document?.rinse()
    }
    
    @IBAction func rotateLeft(_sender: Any? ) {
        guard let document else { return }
        
        if let selectedPages = theThumbnailView?.selectedPages {
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
        guard let document else { return }
        
        if let selectedPages = theThumbnailView?.selectedPages {
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
        guard let pdfDoc = document?.thePDFDocument, let document else { return }

        let selected = theThumbnailView?.selectedPages ?? []
        guard !selected.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Page Selected"
            alert.informativeText = "Select a page in the Thumbnail pane."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Never delete every page
        guard selected.count < pdfDoc.pageCount else {
            let alert = NSAlert()
            alert.messageText = "Can't Delete All Pages"
            alert.informativeText = "ReView will not delete every page in the document."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Indexes, highest first so earlier removals don't shift later ones
        let indexes = selected.map { pdfDoc.index(for: $0) }.sorted(by: >)

        let alert = NSAlert()
        alert.messageText = indexes.count == 1 ? "Delete Page" : "Delete \(indexes.count) Pages"
        alert.informativeText = indexes.count == 1
            ? "Do you want to delete page \(indexes[0] + 1)?"
            : "Do you want to delete the \(indexes.count) selected pages?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        for index in indexes {
            document.deletePage(at: index)
        }
        loadViewParameters()
    }
}
