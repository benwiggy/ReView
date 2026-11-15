//
//  BookmarkSplitter.swift
//  ReView
//
//  Created by Ben on 28/10/2026.
//

import AppKit
import Combine
import PDFKit
import SwiftUI

// MARK: - The plan: which pages go into which file

/// One output file: a run of pages and the sub-bookmarks that stay inside it.
final class SplitUnit {
    let title: String
    let start: Int            // first page (0-based)
    var end: Int = -1         // last page; less than `start` means the unit is empty and is dropped
    let outline: [BookmarkNode]
    init(title: String, start: Int, outline: [BookmarkNode]) {
        self.title = title
        self.start = start
        self.outline = outline
    }
    var isEmpty: Bool { end < start }
}

private indirect enum SplitEntry {
    case file(SplitUnit)
    case folder(String, [SplitEntry])
}

struct SplitPlan {
    struct Job {
        let folders: [String]
        let fileName: String
        let unit: SplitUnit
    }
    struct Line: Identifiable {
        let id: Int
        let indent: Int
        let text: String
    }

    var jobs: [Job] = []
    var lines: [Line] = []

    // MARK: Bookmark tree measurements

    private static func pageIndex(_ page: PDFPage?, in pdf: PDFDocument) -> Int? {
        guard let page, page.document === pdf else { return nil }
        let index = pdf.index(for: page)
        return index == NSNotFound ? nil : index
    }

    /// A bookmark's first page: its own, or (for a heading with no destination) its first child's.
    private static func start(of node: BookmarkNode, in pdf: PDFDocument) -> Int? {
        if let index = pageIndex(node.page, in: pdf) { return index }
        return node.children.compactMap { start(of: $0, in: pdf) }.min()
    }

    private static func usable(_ nodes: [BookmarkNode], in pdf: PDFDocument) -> [BookmarkNode] {
        nodes.filter { start(of: $0, in: pdf) != nil }
    }

    /// The deepest level of bookmarks that point somewhere.
    static func maxLevel(_ nodes: [BookmarkNode], in pdf: PDFDocument) -> Int {
        let live = usable(nodes, in: pdf)
        guard !live.isEmpty else { return 0 }
        return 1 + (live.map { maxLevel($0.children, in: pdf) }.max() ?? 0)
    }

    private static func count(_ nodes: [BookmarkNode], atLevel level: Int, in pdf: PDFDocument) -> Int {
        let live = usable(nodes, in: pdf)
        if level == 1 { return live.count }
        return live.reduce(0) { $0 + count($1.children, atLevel: level - 1, in: pdf) }
    }

    /// The shallowest level with more than one bookmark: many manuals have a single top bookmark
    /// (the manual's title) with the chapters beneath it.
    static func defaultLevel(_ nodes: [BookmarkNode], in pdf: PDFDocument) -> Int {
        let deepest = maxLevel(nodes, in: pdf)
        guard deepest > 0 else { return 1 }
        for level in 1...deepest where count(nodes, atLevel: level, in: pdf) > 1 { return level }
        return deepest
    }

    // MARK: Building

    static func make(bookmarks: [BookmarkNode], pdf: PDFDocument, level: Int,
                     hierarchical: Bool, includeFrontMatter: Bool) -> SplitPlan {
        var units: [SplitUnit] = []

        func build(_ nodes: [BookmarkNode], depth: Int) -> [SplitEntry] {
            var entries: [SplitEntry] = []
            for node in nodes {
                guard let nodeStart = start(of: node, in: pdf) else { continue }
                let kids = usable(node.children, in: pdf)
                if depth >= level || kids.isEmpty {
                    let unit = SplitUnit(title: node.title, start: nodeStart, outline: node.children)
                    units.append(unit)
                    entries.append(.file(unit))
                } else {
                    var inner: [SplitEntry] = []
                    // Pages a heading owns before its first sub-bookmark would otherwise be lost
                    // (or glued to the previous part), so they get a file of their own.
                    if let own = pageIndex(node.page, in: pdf),
                       let firstKid = kids.compactMap({ start(of: $0, in: pdf) }).min(), own < firstKid {
                        let intro = SplitUnit(title: node.title, start: own, outline: [])
                        units.append(intro)
                        inner.append(.file(intro))
                    }
                    inner += build(kids, depth: depth + 1)
                    entries.append(.folder(node.title, inner))
                }
            }
            return entries
        }

        var root = build(bookmarks, depth: 1)

        if includeFrontMatter, let first = units.map(\.start).min(), first > 0 {
            let front = SplitUnit(title: "Front matter", start: 0, outline: [])
            units.append(front)
            root.insert(.file(front), at: 0)
        }

        // Each unit runs to the page before the next one starts. A page that starts a section
        // belongs to that section.
        let ordered = units.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        for (i, unit) in ordered.enumerated() {
            let nextStart = i + 1 < ordered.count ? ordered[i + 1].start : pdf.pageCount
            unit.end = nextStart - 1
        }

        var plan = SplitPlan()
        func pages(_ unit: SplitUnit) -> String {
            unit.start == unit.end ? "p. \(unit.start + 1)" : "pp. \(unit.start + 1)–\(unit.end + 1)"
        }
        func hasContent(_ entry: SplitEntry) -> Bool {
            switch entry {
            case .file(let unit): return !unit.isEmpty
            case .folder(_, let inner): return inner.contains(where: hasContent)
            }
        }
        func padded(_ number: Int, width: Int) -> String {
            let text = String(number)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        func addLine(_ indent: Int, _ text: String) {
            plan.lines.append(Line(id: plan.lines.count, indent: indent, text: text))
        }

        if hierarchical {
            func layout(_ entries: [SplitEntry], folders: [String], indent: Int) {
                let live = entries.filter(hasContent)
                let width = String(live.count).count
                for (i, entry) in live.enumerated() {
                    let number = padded(i + 1, width: width)
                    switch entry {
                    case .file(let unit):
                        let name = "\(number) - \(safeName(unit.title)).pdf"
                        plan.jobs.append(Job(folders: folders, fileName: name, unit: unit))
                        addLine(indent, "\(name)   \(pages(unit))")
                    case .folder(let title, let inner):
                        let folder = "\(number) - \(safeName(title))"
                        addLine(indent, folder + "/")
                        layout(inner, folders: folders + [folder], indent: indent + 1)
                    }
                }
            }
            layout(root, folders: [], indent: 0)
        } else {
            var flat: [SplitUnit] = []
            func flatten(_ entries: [SplitEntry]) {
                for entry in entries {
                    switch entry {
                    case .file(let unit): if !unit.isEmpty { flat.append(unit) }
                    case .folder(_, let inner): flatten(inner)
                    }
                }
            }
            flatten(root)
            let width = String(flat.count).count
            for (i, unit) in flat.enumerated() {
                let name = "\(padded(i + 1, width: width)) - \(safeName(unit.title)).pdf"
                plan.jobs.append(Job(folders: [], fileName: name, unit: unit))
                addLine(0, "\(name)   \(pages(unit))")
            }
        }
        return plan
    }

    /// A bookmark title made safe to use as (part of) a file or folder name.
    static func safeName(_ title: String) -> String {
        var name = ""
        for scalar in title.unicodeScalars {
            let unsafe = scalar == "/" || scalar == ":" || scalar == "\\" || scalar.value < 32
            name.unicodeScalars.append(unsafe ? "-" : scalar)
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > 100 { name = String(name.prefix(100)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "Untitled" : name
    }
}

// MARK: - Options

/// What the user chooses in the split panel. Layout choices are remembered between uses.
final class SplitOptions: ObservableObject {
    private enum Key {
        static let hierarchical = "splitHierarchical"
        static let front = "splitIncludeFrontMatter"
        static let useFolder = "splitUseFolder"
    }

    @Published var baseName: String
    @Published var level: Int
    @Published var hierarchical: Bool
    @Published var includeFrontMatter: Bool
    @Published var useFolder: Bool

    let bookmarks: [BookmarkNode]
    let pdf: PDFDocument
    let maxLevel: Int

    init(baseName: String, bookmarks: [BookmarkNode], pdf: PDFDocument) {
        let defaults = UserDefaults.standard
        self.baseName = baseName
        self.bookmarks = bookmarks
        self.pdf = pdf
        maxLevel = max(1, SplitPlan.maxLevel(bookmarks, in: pdf))
        level = SplitPlan.defaultLevel(bookmarks, in: pdf)
        hierarchical = defaults.object(forKey: Key.hierarchical) as? Bool ?? false
        includeFrontMatter = defaults.object(forKey: Key.front) as? Bool ?? true
        useFolder = defaults.object(forKey: Key.useFolder) as? Bool ?? true
    }

    func remember() {
        let defaults = UserDefaults.standard
        defaults.set(hierarchical, forKey: Key.hierarchical)
        defaults.set(includeFrontMatter, forKey: Key.front)
        defaults.set(useFolder, forKey: Key.useFolder)
    }

    var cleanBaseName: String { SplitPlan.safeName(baseName) }

    var plan: SplitPlan {
        SplitPlan.make(bookmarks: bookmarks, pdf: pdf, level: level,
                       hierarchical: hierarchical, includeFrontMatter: includeFrontMatter)
    }
}

struct SplitOptionsView: View {
    @ObservedObject var options: SplitOptions

    var body: some View {
        let plan = options.plan
        VStack(alignment: .leading, spacing: 10) {
            row("Split at") {
                Picker("", selection: $options.level) {
                    ForEach(1...options.maxLevel, id: \.self) { level in
                        Text(level == 1 ? "Level 1 (top-level bookmarks)" : "Level \(level)").tag(level)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                Spacer()
            }
            row("Files") {
                Picker("", selection: $options.hierarchical) {
                    Text("All in one folder").tag(false)
                    Text("In folders matching the bookmark hierarchy").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Spacer()
            }
            row("") {
                Toggle("Include the pages before the first bookmark", isOn: $options.includeFrontMatter)
            }
            row("Name") {
                TextField("Name", text: $options.baseName)
            }
            row("") {
                Toggle("Put everything in a folder named “\(options.cleanBaseName)”", isOn: $options.useFolder)
            }
            row("") {
                Text(plan.jobs.count == 1 ? "1 file" : "\(plan.jobs.count) files")
                    .font(.caption).foregroundStyle(.secondary)
            }
            row("") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(plan.lines) { line in
                            Text(line.text)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, CGFloat(line.indent) * 14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(height: 180)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
            }
        }
        .padding(16)
        .frame(width: 540)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).frame(width: 80, alignment: .trailing)
            content()
        }
    }
}

// MARK: - Splitter

/// Runs one split: asks for a destination folder (with the options in the panel), then writes
/// one part at a time, yielding to the run loop between parts so the progress sheet stays live.
final class BookmarkSplitter {
    private let store: DocumentStore
    private weak var window: NSWindow?
    private let options: SplitOptions

    private var jobs: [(job: SplitPlan.Job, url: URL)] = []
    private var nextJob = 0
    private var failed: [String] = []
    private var progress = ExportProgress(total: 0)
    private var sheet: NSWindow?
    private var completion: () -> Void = {}

    init(store: DocumentStore, window: NSWindow, baseName: String) {
        self.store = store
        self.window = window
        options = SplitOptions(baseName: baseName, bookmarks: store.bookmarks, pdf: store.pdf)
    }

    // MARK: Asking

    func begin(completion: @escaping () -> Void) {
        self.completion = completion
        guard let window else { completion(); return }

        guard !store.copyingRestricted else {
            alert("This document doesn't allow its content to be copied.",
                  "Its owner has restricted copying, so it can't be split.", on: window)
            return
        }
        guard SplitPlan.maxLevel(store.bookmarks, in: store.pdf) > 0 else {
            alert("There are no bookmarks to split at.",
                  "Add bookmarks in the sidebar first. Bookmarks without a destination page are ignored.", on: window)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Split at Bookmarks"
        panel.message = "Choose where to save the new PDFs."
        panel.prompt = "Split"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let accessory = NSHostingView(rootView: SplitOptionsView(options: options))
        accessory.setFrameSize(accessory.fittingSize)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let directory = panel.url else { finish(); return }
            prepare(in: directory)
        }
    }

    private func alert(_ message: String, _ detail: String, on window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.beginSheetModal(for: window) { [self] _ in finish() }
    }

    private func prepare(in directory: URL) {
        options.remember()
        let plan = options.plan
        let target = options.useFolder
            ? directory.appendingPathComponent(options.cleanBaseName, isDirectory: true)
            : directory

        jobs = plan.jobs.map { job in
            var url = target
            for folder in job.folders { url.appendPathComponent(folder, isDirectory: true) }
            url.appendPathComponent(job.fileName)
            return (job, url)
        }
        guard !jobs.isEmpty else { finish(); return }

        let existing = jobs.filter { FileManager.default.fileExists(atPath: $0.url.path) }.count
        guard existing > 0, let window else { start(); return }

        let alert = NSAlert()
        alert.messageText = existing == 1 ? "One file already exists." : "\(existing) files already exist."
        alert.informativeText = "Do you want to replace \(existing == 1 ? "it" : "them")?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [self] response in
            if response == .alertFirstButtonReturn { start() } else { finish() }
        }
    }

    // MARK: Running

    private func start() {
        do {
            for folder in Set(jobs.map { $0.url.deletingLastPathComponent() }) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        } catch {
            if let window { NSAlert(error: error).beginSheetModal(for: window) }
            finish()
            return
        }

        progress = ExportProgress(total: jobs.count)
        progress.title = "Splitting…"
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: ExportProgressView(progress: progress)))
        self.sheet = sheet
        window?.beginSheet(sheet)
        DispatchQueue.main.async { [self] in step() }
    }

    private func step() {
        guard !progress.cancelled, nextJob < jobs.count else {
            if let sheet { window?.endSheet(sheet) }
            sheet = nil
            if !failed.isEmpty { reportFailures() }
            else if !progress.cancelled, let first = jobs.first {
                NSWorkspace.shared.activateFileViewerSelecting([first.url])
            }
            finish()
            return
        }

        let item = jobs[nextJob]
        nextJob += 1
        autoreleasepool {
            if !write(item.job.unit, to: item.url) { failed.append(item.job.fileName) }
        }
        progress.done = nextJob
        DispatchQueue.main.async { [self] in step() }
    }

    private func reportFailures() {
        let alert = NSAlert()
        alert.messageText = "Some files couldn't be written."
        alert.informativeText = failed.joined(separator: "\n")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func finish() {
        completion()
        completion = {}
    }

    // MARK: One part

    private func write(_ unit: SplitUnit, to url: URL) -> Bool {
        let part = PDFDocument()
        var map: [ObjectIdentifier: PDFPage] = [:]
        for index in unit.start...unit.end {
            // Copies: inserting the originals would pull them out of the open document.
            guard let original = store.pdf.page(at: index), let copy = original.copy() as? PDFPage else { return false }
            part.insert(copy, at: part.pageCount)
            map[ObjectIdentifier(original)] = copy
        }
        part.outlineRoot = Self.outline(from: Self.remap(unit.outline, map), in: part)

        var attributes: [AnyHashable: Any] = [PDFDocumentAttribute.titleAttribute: unit.title]
        let metadata = store.metadata
        if !metadata.author.isEmpty { attributes[PDFDocumentAttribute.authorAttribute] = metadata.author }
        if !metadata.subject.isEmpty { attributes[PDFDocumentAttribute.subjectAttribute] = metadata.subject }
        if !metadata.creator.isEmpty { attributes[PDFDocumentAttribute.creatorAttribute] = metadata.creator }
        let words = metadata.keywords.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !words.isEmpty { attributes[PDFDocumentAttribute.keywordsAttribute] = words }
        part.documentAttributes = attributes

        return part.write(to: url)
    }

    /// Point each bookmark at the copy of its page; drop ones that have nowhere to go in this part.
    private static func remap(_ nodes: [BookmarkNode], _ map: [ObjectIdentifier: PDFPage]) -> [BookmarkNode] {
        nodes.compactMap { node in
            var copy = node
            copy.page = node.page.flatMap { map[ObjectIdentifier($0)] }
            copy.children = remap(node.children, map)
            return copy.page == nil && copy.children.isEmpty ? nil : copy
        }
    }

    private static func outline(from marks: [BookmarkNode], in document: PDFDocument) -> PDFOutline? {
        guard !marks.isEmpty else { return nil }
        func add(_ nodes: [BookmarkNode], to parent: PDFOutline) {
            for (i, node) in nodes.enumerated() {
                let item = PDFOutline()
                item.label = node.title
                if let page = node.page {
                    let box = page.bounds(for: .cropBox)
                    item.destination = PDFDestination(page: page, at: CGPoint(x: box.minX, y: box.maxY))
                }
                parent.insertChild(item, at: i)
                add(node.children, to: item)
            }
        }
        let root = PDFOutline()
        add(marks, to: root)
        return root
    }
}
