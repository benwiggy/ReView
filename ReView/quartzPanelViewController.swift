//
//  quartzPanelViewController.swift
//  ReView
//
//  Created by Ben Byram-Wigfield on 05/10/2019.
//  Copyright © 2019 Ben. All rights reserved.
//

import Cocoa
import Quartz

extension Notification.Name {
    static let filterSelected = Notification.Name(rawValue:"Filter!")
}

class quartzPanelViewController: NSViewController {
    
    struct MyFilter {
        var myURL: URL?
        var name: String = ""
    }
     var filterArray = [MyFilter]()
    
    var document: Document? {
            return self.view.window?.windowController?.document as? Document
        }
    
    @IBOutlet var filterPopup: NSPopUpButton!
    
    
    @IBAction func OKFilter(_sender: Any) {
        if let chosenFilter = filterPopup?.indexOfSelectedItem {
            let filterURL = filterArray[chosenFilter].myURL
            NotificationCenter.default.post(name: .filterSelected, object: self, userInfo: ["url": filterURL!])
        }
    }

    func getFilters() -> Array<MyFilter> {
        if let filters = QuartzFilterManager.filters(inDomains: nil) {
            for eachFilter in filters {
                            let aFilter = MyFilter(myURL: (eachFilter as! QuartzFilter).url(), name: (eachFilter as! QuartzFilter).localizedName()!)

                filterArray.append(aFilter)
            }
        }
        return filterArray
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    override func viewWillAppear() {
        let filterList = getFilters()
            filterPopup.removeAllItems()
        for eachFilter in filterList {
            filterPopup.addItem(withTitle: eachFilter.name)
        }
    }
  
    
    @IBAction func close(_sender: Any?) {
        view.window?.close()
    }
}
