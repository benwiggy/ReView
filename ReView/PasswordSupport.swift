//
//  PasswordSupport.swift
//  ReView
//
//  Created by Ben on 27/10/2026.
//

import AppKit
import PDFKit

/// Protection the user has chosen explicitly in File > Password Protection…
///
/// A PDF has two different passwords:
/// - the *open* (user) password: needed to open the file at all;
/// - the *owner* password: needed to change the restrictions. Without it, the file can still be
///   opened (if there is no open password), read, annotated and saved, within the restrictions.
/// Core Graphics, and so PDFKit, can only restrict printing and copying.
struct SecuritySettings: Equatable {
    var openPassword: String?
    var ownerPassword: String?
    var allowsPrinting = true
    var allowsCopying = true

    var isUnprotected: Bool {
        openPassword == nil && ownerPassword == nil && allowsPrinting && allowsCopying
    }
}

struct SaveVerificationError: LocalizedError {
    var errorDescription: String? { "The file wasn't saved." }
    var failureReason: String? {
        "Saving would have changed this PDF's password protection, so nothing was written and your original file is unchanged. Choose File > Password Protection… to set the protection you want, then save again."
    }
}

enum AppActivation {
    /// Brings the app (and so its newest window) in front of other apps' windows.
    static func bringToFront() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
}

/// Asks for the password of a locked PDF.
enum PasswordPrompt {

    /// Returns the password that unlocked `pdf`, or nil if the user cancelled.
    static func unlock(_ pdf: PDFDocument, name: String) -> String? {
        var message = "Enter the password to open “\(name)”."
        while true {
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            let alert = NSAlert()
            alert.messageText = "Password Required"
            alert.informativeText = message
            alert.accessoryView = field
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            AppActivation.bringToFront()
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let password = field.stringValue
            if pdf.unlock(withPassword: password) { return password }
            message = "That password is incorrect. Try again."
        }
    }
}

enum PasswordProtectionSheet {

    /// Runs `refresh` when a checkbox changes (the checkbox's target isn't retained, so callers keep this alive).
    private final class Refresher: NSObject {
        let refresh: () -> Void
        init(_ refresh: @escaping () -> Void) { self.refresh = refresh }
        @objc func fire(_ sender: Any?) { refresh() }
    }

    /// The sheet's contents, kept so it can be shown again after a validation message.
    struct Draft {
        var requireOpen = false, open = "", openVerify = ""
        var restrict = false, owner = "", ownerVerify = ""
        var printing = true, copying = true

        init(_ s: SecuritySettings) {
            requireOpen = s.openPassword != nil
            open = s.openPassword ?? ""; openVerify = open
            restrict = s.ownerPassword != nil || !s.allowsPrinting || !s.allowsCopying
            owner = s.ownerPassword ?? ""; ownerVerify = owner
            printing = s.allowsPrinting; copying = s.allowsCopying
        }
    }

    /// For documents whose restrictions are protected by an owner password we don't know yet:
    /// changing protection needs that password. `verify` returns true if it's right.
    static func askOwnerPassword(on window: NSWindow, message: String? = nil,
                                 verify: @escaping (String) -> Bool, proceed: @escaping () -> Void) {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let alert = NSAlert()
        alert.messageText = "Owner Password Required"
        alert.informativeText = message ??
            "This document restricts what can be done with it. To change its protection, enter its owner password."
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            if verify(field.stringValue) { proceed() }
            else {
                DispatchQueue.main.async {
                    askOwnerPassword(on: window, message: "That owner password is incorrect.",
                                     verify: verify, proceed: proceed)
                }
            }
        }
    }

    /// `apply` receives the user's chosen protection. Nothing is encrypted unless they ask for it here.
    static func present(on window: NSWindow, draft: Draft, message: String? = nil,
                        apply: @escaping (SecuritySettings) -> Void) {
        func secure(_ text: String, _ placeholder: String) -> NSSecureTextField {
            let field = NSSecureTextField()
            field.placeholderString = placeholder
            field.stringValue = text
            field.widthAnchor.constraint(equalToConstant: 280).isActive = true
            return field
        }
        func note(_ text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 280
            return label
        }

        let openBox = NSButton(checkboxWithTitle: "Require a password to open", target: nil, action: nil)
        openBox.state = draft.requireOpen ? .on : .off
        let open = secure(draft.open, "Password to open")
        let openVerify = secure(draft.openVerify, "Verify password")

        let restrictBox = NSButton(checkboxWithTitle: "Restrict what can be done (needs an owner password)",
                                   target: nil, action: nil)
        restrictBox.state = draft.restrict ? .on : .off
        let owner = secure(draft.owner, "Owner password")
        let ownerVerify = secure(draft.ownerVerify, "Verify owner password")
        let printBox = NSButton(checkboxWithTitle: "Allow printing", target: nil, action: nil)
        printBox.state = draft.printing ? .on : .off
        let copyBox = NSButton(checkboxWithTitle: "Allow copying text and images", target: nil, action: nil)
        copyBox.state = draft.copying ? .on : .off

        let refresher = Refresher {
            for control in [open, openVerify] { control.isEnabled = openBox.state == .on }
            for control in [owner, ownerVerify, printBox, copyBox] as [NSControl] {
                control.isEnabled = restrictBox.state == .on
            }
        }
        for box in [openBox, restrictBox] { box.target = refresher; box.action = #selector(Refresher.fire(_:)) }
        refresher.refresh()

        let stack = NSStackView(views: [
            openBox, open, openVerify,
            restrictBox, owner, ownerVerify, printBox, copyBox,
            note("Anyone can open the file without an owner password, and read and annotate it as far as the restrictions allow. Only the owner password changes the restrictions. Neither password can be recovered if forgotten.")
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(18, after: openVerify)
        stack.setCustomSpacing(12, after: copyBox)
        stack.setFrameSize(stack.fittingSize)

        let alert = NSAlert()
        alert.messageText = "Password Protection"
        alert.informativeText = message ?? "Nothing changes on disk until you save."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { response in
            _ = refresher   // keeps the checkbox target alive while the sheet is up
            guard response == .alertFirstButtonReturn else { return }

            var edited = Draft(SecuritySettings())
            edited.requireOpen = openBox.state == .on
            edited.open = open.stringValue; edited.openVerify = openVerify.stringValue
            edited.restrict = restrictBox.state == .on
            edited.owner = owner.stringValue; edited.ownerVerify = ownerVerify.stringValue
            edited.printing = printBox.state == .on; edited.copying = copyBox.state == .on

            var settings = SecuritySettings()
            var problem: String?
            if edited.requireOpen {
                if edited.open.isEmpty { problem = "Enter a password to open." }
                else if edited.open != edited.openVerify { problem = "The two open passwords don't match." }
                else { settings.openPassword = edited.open }
            }
            if problem == nil, edited.restrict {
                if edited.owner.isEmpty { problem = "Enter an owner password." }
                else if edited.owner != edited.ownerVerify { problem = "The two owner passwords don't match." }
                else if edited.requireOpen, edited.owner == edited.open, !edited.printing || !edited.copying {
                    problem = "The owner password must differ from the open password, or the restrictions would apply to nobody."
                } else {
                    settings.ownerPassword = edited.owner
                    settings.allowsPrinting = edited.printing
                    settings.allowsCopying = edited.copying
                }
            }
            if let problem {
                DispatchQueue.main.async { present(on: window, draft: edited, message: problem, apply: apply) }
                return
            }
            apply(settings)
        }
    }
}
