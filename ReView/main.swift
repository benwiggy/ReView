import AppKit

// AppKit entry point. Documents are managed by NSDocument (see PDFFileDocument)
// so that autosave can be switched off; the UI inside each window is SwiftUI.
AppSettings.registerDefaults()
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
_ = ClipboardDocumentController()   // the first controller created becomes NSDocumentController.shared
app.setActivationPolicy(.regular)
app.run()
