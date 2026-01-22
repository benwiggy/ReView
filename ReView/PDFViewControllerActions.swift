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
            self.defaults.set(false, forKey: bookStateKey)
        } else {
            thePDFView.displaysAsBook = true
            sender.state = .on
            bookState = true
            self.defaults.set(true, forKey: bookStateKey)
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
        if let selectedPages = theThumbnailView?.selectedPages {
            // let selectedPageNo: Int? = (thePDFView.document!.index(for: thePDFView.currentPage!))
            for page in selectedPages {
                let pageSize = page.bounds(for: .mediaBox)
                let blankPage = PDFPage.init()
                if let thePDFDocument = document?.thePDFDocument {
                    blankPage.setBounds(pageSize, for: .mediaBox)
                    document?.insert(blankPage: blankPage, at: ((thePDFDocument.index(for: page))))
                }
            }
            document?.rinse()
        }
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
        guard let thePDFView, let document else { return }
        
        if let pageCount = thePDFView.document?.pageCount {
            if pageCount > 1 {
                if let selectedPages = theThumbnailView?.selectedPages {
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
}
