//
//  MySplitViewControllerActions.swift
//  ReView
//
//  Created by Pat Garner on 1/22/26.
//  Copyright © 2026 Ben. All rights reserved.
//

import Cocoa

extension MySplitViewController {
    @IBAction func changePageStyle(_ sender: NSMenuItem) {
        pdfViewController?.changePageStyle(sender)
    }

    // Go to next search result
    @IBAction func goToNextSearchResult(_ sender: Any?) {
        pdfViewController?.goToNextSearchResult(sender)
    }
    
    // Go to previous search result
    @IBAction func goToPreviousSearchResult(_ sender: Any?) {
        pdfViewController?.goToPreviousSearchResult(sender)
    }
    
    @IBAction func find(_ sender: Any?) {
        pdfViewController?.find(sender)
    }

    // Setting defaults prefs, but not reading them
    @IBAction func FirstCover(_ sender: NSMenuItem) {
        pdfViewController?.FirstCover(sender)
    }
    
    @IBAction func applyFilter(_sender: Any?) {
        pdfViewController?.applyFilter(_sender: _sender)
    }

    @IBAction func search2(_ sender: NSSearchField) {
        pdfViewController?.search2(sender)
    }

    @IBAction func addBlank(_ sender: Any?) {
        pdfViewController?.addBlank(sender)
    }
    
    @IBAction func rotateLeft(_sender: Any? ) {
        pdfViewController?.rotateLeft(_sender: _sender)
    }
    
    @IBAction func rotateRight(_sender: Any? ) {
        pdfViewController?.rotateRight(_sender: _sender)
    }
    
    @IBAction func deletePage(_sender: Any?) {
        pdfViewController?.deletePage(_sender: _sender)
    }
}
