//
//  PreferencesWindowController.swift
//  ReView
//
//  Created by Ben on 25/01/2026.
//  Copyright © 2026 Ben. All rights reserved.
//

import Cocoa

final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private init() {
        let storyboard = NSStoryboard(name: "Preferences", bundle: nil)
        guard let wc = storyboard.instantiateController(withIdentifier: "PreferencesWC") as? NSWindowController else {
            fatalError("Preferences storyboard does not contain a NSWindowController with ID 'PreferencesWC'")
        }
        super.init(window: wc.window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
