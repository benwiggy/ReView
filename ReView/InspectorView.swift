//
//  InspectorModel.swift
//  ReView
//
//  Created by Ben on 27/10/2026.
//


import AppKit
import PDFKit
import SwiftUI
import Combine

// MARK: - Which document the Inspector shows

/// Follows the frontmost document window, so one Inspector panel serves every open document.
final class InspectorModel: NSObject, ObservableObject {
    @Published private(set) var store: DocumentStore?
    private(set) weak var controller: DocumentWindowController?

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowBecameMain(_:)),
                           name: NSWindow.didBecomeMainNotification, object: nil)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: nil)
        follow(NSApp.mainWindow)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func follow(_ window: NSWindow?) {
        guard let controller = window?.windowController as? DocumentWindowController else { return }
        self.controller = controller
        store = controller.store
    }

    @objc private func windowBecameMain(_ note: Notification) {
        follow(note.object as? NSWindow)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow, window.windowController === controller else { return }
        controller = nil
        store = nil
    }
}

// MARK: - Panel content

enum InspectorTab: Int, CaseIterable, Identifiable {
    case general, metadata, security
    var id: Int { rawValue }
    var symbol: String {
        switch self {
        case .general: return "info.circle"
        case .metadata: return "tag"
        case .security: return "lock"
        }
    }
    var title: String {
        switch self {
        case .general: return "General"
        case .metadata: return "Metadata"
        case .security: return "Security"
        }
    }
}

struct InspectorRootView: View {
    @ObservedObject var model: InspectorModel
    @AppStorage("inspectorTab") private var tabRaw = InspectorTab.general.rawValue

    private var tab: InspectorTab { InspectorTab(rawValue: tabRaw) ?? .general }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tabRaw) {
                ForEach(InspectorTab.allCases) { tab in
                    Image(systemName: tab.symbol)
                        .accessibilityLabel(tab.title)
                        .tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()

            if let store = model.store {
                InspectorContent(store: store, controller: model.controller, tab: tab)
                    .id(ObjectIdentifier(store))
            } else {
                Spacer()
                Text("No document")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 290, minHeight: 380)
    }
}

private struct InspectorContent: View {
    @ObservedObject var store: DocumentStore
    let controller: DocumentWindowController?
    let tab: InspectorTab

    var body: some View {
        switch tab {
        case .general: GeneralTab(store: store)
        case .metadata: MetadataTab(store: store)
        case .security: SecurityTab(store: store, controller: controller)
        }
    }
}

// MARK: General

private struct GeneralTab: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        let pdf = store.pdf
        Form {
            Section("Document") {
                LabeledContent("Name", value: store.document?.displayName ?? "Untitled")
                LabeledContent("Kind", value: "PDF Document")
                LabeledContent("PDF version", value: "\(pdf.majorVersion).\(pdf.minorVersion)")
                // The file can change without the store changing (saving), so look again every couple of seconds.
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent("File size", value: fileSizeText)
                }
            }
            Section("Pages") {
                LabeledContent("Page count", value: "\(store.pageCount)")
                ForEach(PageSizes.groups(of: pdf)) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.description)
                        Text(group.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .id(store.pageRevision)   // sizes change with edits; rebuild the list then
    }

    private var fileSizeText: String {
        guard let url = store.document?.fileURL,
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            return "Not saved yet"
        }
        let text = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return store.document?.isDocumentEdited == true ? "\(text) (before your changes)" : text
    }
}

// MARK: Metadata

private struct MetadataTab: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        let attributes = store.pdf.documentAttributes ?? [:]
        let created = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        let modified = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date

        Form {
            Section("Edit") {
                MetadataField(label: "Title", value: store.metadata.title) { text in update { $0.title = text } }
                MetadataField(label: "Author", value: store.metadata.author) { text in update { $0.author = text } }
                MetadataField(label: "Subject", value: store.metadata.subject) { text in update { $0.subject = text } }
                MetadataField(label: "Keywords (separated by commas)", value: store.metadata.keywords) { text in
                    update { $0.keywords = text }   }
                MetadataField(label: "Creator", value: store.metadata.creator) { text in update { $0.creator = text } }
            }
            Section("Recorded in the file") {
                LabeledContent("Created", value: created?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                LabeledContent("Modified", value: modified?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                LabeledContent("Producer", value: (attributes[PDFDocumentAttribute.producerAttribute] as? String) ?? "—")
            }
            Text("Edits are saved into the file when you save the document.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func update(_ change: (inout DocumentStore.DocumentMetadata) -> Void) {
        var updated = store.metadata
        change(&updated)
        store.setMetadata(updated)
    }

}

/// A text field that records its edit (one undo step) when you press Return or move away,
/// rather than on every keystroke.
private struct MetadataField: View {
    let label: String
    let value: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { commit(text) }
        }
        .onAppear { text = value }
        .onChange(of: value) { _, new in if new != text { text = new } }   // undo, redo, or another document
        .onChange(of: focused) { _, isFocused in if !isFocused { commit(text) } }
    }
}

// MARK: Security

private struct SecurityTab: View {
    @ObservedObject var store: DocumentStore
    let controller: DocumentWindowController?

    var body: some View {
        Form {
            Section("Protection") {
                LabeledContent("Encryption", value: store.pdf.isEncrypted || store.isProtected ? "Encrypted" : "Not encrypted")
                LabeledContent("Password to open", value: store.requiresOpenPassword ? "Required" : "Not required")
                LabeledContent("Printing", value: store.printingRestricted ? "Not allowed" : "Allowed")
                LabeledContent("Copying", value: store.copyingRestricted ? "Not allowed" : "Allowed")
                if store.security != nil {
                    Text("These are the settings that will be written when you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Password Protection…") { controller?.showPasswordProtection(nil) }
                    .disabled(controller == nil)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Page sizes

struct PageSizeGroup: Identifiable {
    let id: String
    let description: String   // "210 × 297 mm (A4)"
    let detail: String        // "595 × 842 pt · all pages"
}

enum PageSizes {
    private static let named: [(name: String, w: CGFloat, h: CGFloat)] = [
        ("A0", 2384, 3370), ("A1", 1684, 2384), ("A2", 1191, 1684), ("A3", 842, 1191),
        ("A4", 595, 842), ("A5", 420, 595), ("A6", 298, 420), ("B5", 499, 709),
        ("Letter", 612, 792), ("Legal", 612, 1008), ("Tabloid", 792, 1224), ("Executive", 522, 756)
    ]

    static func groups(of pdf: PDFDocument) -> [PageSizeGroup] {
        // Group pages by their shown size (a rotated page swaps width and height).
        var order: [String] = []
        var sizes: [String: CGSize] = [:]
        var pages: [String: IndexSet] = [:]
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            var size = page.bounds(for: .cropBox).size
            if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            let key = "\(Int((size.width * 2).rounded()))x\(Int((size.height * 2).rounded()))"
            if sizes[key] == nil { sizes[key] = size; order.append(key) }
            pages[key, default: IndexSet()].insert(index)
        }
        let all = pdf.pageCount
        return order.map { key in
            let size = sizes[key]!
            let set = pages[key]!
            let scope = set.count == all ? "all pages" : "page" + (set.count == 1 ? " " : "s ") + rangeText(set)
            return PageSizeGroup(id: key,
                                 description: describe(size),
                                 detail: "\(points(size.width)) × \(points(size.height)) pt · \(scope)")
        }
    }

    private static func points(_ value: CGFloat) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private static func describe(_ size: CGSize) -> String {
        let measurement: String
        if Locale.current.measurementSystem == .us {
            measurement = "\(trim(size.width / 72)) × \(trim(size.height / 72)) in"
        } else {
            measurement = "\(trim(size.width / 72 * 25.4)) × \(trim(size.height / 72 * 25.4)) mm"
        }
        let short = min(size.width, size.height), long = max(size.width, size.height)
        let match = named.first { abs($0.w - short) <= 2 && abs($0.h - long) <= 2 }
        guard let match else { return measurement }
        let orientation = size.width > size.height ? ", landscape" : ""
        return "\(measurement) (\(match.name)\(orientation))"
    }

    private static func trim(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    /// "1–3, 5, 8–9" (1-based).
    private static func rangeText(_ set: IndexSet) -> String {
        set.rangeView.map { range in
            range.count == 1 ? "\(range.lowerBound + 1)" : "\(range.lowerBound + 1)–\(range.upperBound)"
        }.joined(separator: ", ")
    }
}
