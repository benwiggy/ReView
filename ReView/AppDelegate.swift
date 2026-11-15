import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindow: NSWindow?

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private var inspectorPanel: NSPanel?
    private var inspectorModel: InspectorModel?

    /// View > Show Inspector (⌘I): one floating panel that follows the frontmost document.
    @objc func toggleInspector(_ sender: Any?) {
        if let panel = inspectorPanel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        if inspectorPanel == nil {
            let model = InspectorModel()
            let panel = NSPanel(contentViewController: NSHostingController(rootView: InspectorRootView(model: model)))
            panel.title = "Inspector"
            panel.styleMask = [.titled, .closable, .resizable, .utilityWindow]
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true     // clicking a text field makes it key; nothing else does
            panel.isReleasedWhenClosed = false
            panel.setContentSize(NSSize(width: 320, height: 520))
            panel.setFrameAutosaveName("InspectorPanel")
            inspectorModel = model
            inspectorPanel = panel
        }
        inspectorPanel?.orderFront(nil)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MenuBuilder.buildMainMenu()
    }

    // A viewer shouldn't conjure up an empty document at launch; use File > New or Open.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleInspector(_:)) {
            item.title = inspectorPanel?.isVisible == true ? "Hide Inspector" : "Show Inspector"
        }
        return true
    }
}
