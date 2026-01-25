//
//  PreferencesViewController.swift
//  ReView
//
//  Created by Ben on 25/01/2026.
//  Copyright © 2026 Ben. All rights reserved.
//

import Cocoa

final class PreferencesViewController: NSViewController {

    // MARK: - Outlets

    @IBOutlet weak var viewStylePopUp: NSPopUpButton!
    @IBOutlet weak var firstPageCoverCheckbox: NSButton!
    @IBOutlet weak var verticalRadio: NSButton!
    @IBOutlet weak var horizontalRadio: NSButton!

    // MARK: - Defaults

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pageViewStyle = "pageViewStyle"   // Int (0–3)
        static let bookState = "bookState"           // Bool
        static let horizontal = "horizontal"         // Bool
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        loadDefaultsIntoUI()
        updateOrientationEnabledState()
    }

    // MARK: - Load defaults → UI

    private func loadDefaultsIntoUI() {
        viewStylePopUp.selectItem(withTag:
            defaults.integer(forKey: Keys.pageViewStyle)
        )

        firstPageCoverCheckbox.state =
            defaults.bool(forKey: Keys.bookState) ? .on : .off

        let isHorizontal = defaults.bool(forKey: Keys.horizontal)
        horizontalRadio.state = isHorizontal ? .on : .off
        verticalRadio.state = isHorizontal ? .off : .on
    }

    // MARK: - Actions (write defaults only)

    @IBAction func viewStyleChanged(_ sender: NSPopUpButton) {
        defaults.set(sender.selectedTag(), forKey: Keys.pageViewStyle)
        updateOrientationEnabledState()
    }

    @IBAction func firstPageCoverChanged(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: Keys.bookState)
    }

    @IBAction func orientationChanged(_ sender: NSButton) {
        defaults.set(sender == horizontalRadio, forKey: Keys.horizontal)
    }

    // MARK: - Helpers

    private func updateOrientationEnabledState() {
        // Orientation only applies to Single Page Continuous (tag = 1)
        let enabled = viewStylePopUp.selectedTag() == 1
        verticalRadio.isEnabled = enabled
        horizontalRadio.isEnabled = enabled
    }
}
