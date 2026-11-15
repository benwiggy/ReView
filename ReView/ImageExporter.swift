//
//  ImageExportFormat.swift
//  ReView
//
//  Created by Ben on 27/10/2026.
//


import AppKit
import PDFKit
import SwiftUI
import Combine

// MARK: - Options

enum ImageExportFormat: String, CaseIterable, Identifiable {
    case png, tiff, jpeg

    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .tiff: return "tiff"
        case .jpeg: return "jpg"
        }
    }
}

/// What the user chooses in the export panel. Remembered between exports.
final class ExportOptions: ObservableObject {
    private enum Key {
        static let format = "exportFormat"
        static let dpi = "exportDPI"
        static let quality = "exportJPEGQuality"
        static let useFolder = "exportUseFolder"
    }

    @Published var baseName: String
    @Published var format: ImageExportFormat
    @Published var dpi: Int
    @Published var jpegQuality: Double
    @Published var useFolder: Bool
    @Published var selectedOnly = false

    let pageCount: Int
    let selectedCount: Int
    let firstPageSize: CGSize?   // in points, as displayed

    init(baseName: String, pageCount: Int, selectedCount: Int, firstPageSize: CGSize?) {
        let defaults = UserDefaults.standard
        self.baseName = baseName
        self.pageCount = pageCount
        self.selectedCount = selectedCount
        self.firstPageSize = firstPageSize
        format = ImageExportFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .png
        let savedDPI = defaults.integer(forKey: Key.dpi)
        dpi = savedDPI > 0 ? savedDPI : 150
        let savedQuality = defaults.double(forKey: Key.quality)
        jpegQuality = savedQuality > 0 ? savedQuality : 0.85
        useFolder = defaults.object(forKey: Key.useFolder) as? Bool ?? true
    }

    func remember() {
        let defaults = UserDefaults.standard
        defaults.set(format.rawValue, forKey: Key.format)
        defaults.set(dpi, forKey: Key.dpi)
        defaults.set(jpegQuality, forKey: Key.quality)
        defaults.set(useFolder, forKey: Key.useFolder)
    }

    /// The name typed by the user, made safe to use in a file name.
    var cleanBaseName: String {
        var name = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return name.isEmpty ? "Page" : name
    }

    /// Page numbers are padded to the width of the document's last page number only:
    /// 9 pages: 1…9, 12 pages: 01…12, 120 pages: 001…120.
    func fileName(forPage number: Int) -> String {
        let digits = String(pageCount).count
        return "\(cleanBaseName)-\(String(format: "%0\(digits)d", number)).\(format.fileExtension)"
    }

    var summary: String {
        var text = "\(fileName(forPage: 1)) … \(fileName(forPage: pageCount))"
        if let size = firstPageSize {
            let scale = CGFloat(dpi) / 72
            text += "\nAbout \(Int(size.width * scale)) × \(Int(size.height * scale)) pixels per page (first page)"
        }
        return text
    }
}

// MARK: - Panel accessory

struct ExportOptionsView: View {
    @ObservedObject var options: ExportOptions
    private let resolutions = [72, 100, 150, 200, 300, 400, 600]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Name") {
                TextField("Name", text: $options.baseName)
            }
            row("Format") {
                Picker("", selection: $options.format) {
                    ForEach(ImageExportFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            row("Resolution") {
                Picker("", selection: $options.dpi) {
                    ForEach(resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer()
            }
            row("Quality") {
                Slider(value: $options.jpegQuality, in: 0.1...1)
                Text("\(Int(options.jpegQuality * 100))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(options.format != .jpeg)
            .opacity(options.format == .jpeg ? 1 : 0.4)

            if options.selectedCount > 0 {
                row("Pages") {
                    Picker("", selection: $options.selectedOnly) {
                        Text("All \(options.pageCount)").tag(false)
                        Text("Selected \(options.selectedCount)").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                    Spacer()
                }
            }

            row("") {
                Toggle("Put the images in a folder named “\(options.cleanBaseName)”", isOn: $options.useFolder)
            }
            row("") {
                Text(options.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).frame(width: 80, alignment: .trailing)
            content()
        }
    }
}

// MARK: - Progress sheet

final class ExportProgress: ObservableObject {
    @Published var done = 0
    @Published var cancelled = false
    var title = "Exporting files…"
    let total: Int
    init(total: Int) { self.total = total }
}

struct ExportProgressView: View {
    @ObservedObject var progress: ExportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(progress.title).font(.headline)
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
            HStack {
                Text("\(progress.done) of \(progress.total)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { progress.cancelled = true }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

// MARK: - Exporter

/// Runs one export: asks for a destination folder (with the options in the panel), then
/// renders one page at a time, yielding to the run loop between pages so the progress
/// sheet stays live and Cancel works.
final class ImageExporter {
    private let store: DocumentStore
    private weak var window: NSWindow?
    private let options: ExportOptions

    private var jobs: [(page: Int, url: URL)] = []
    private var nextJob = 0
    private var failedPages: [Int] = []
    private var progress = ExportProgress(total: 0)
    private var sheet: NSWindow?
    private var completion: () -> Void = {}

    init(store: DocumentStore, window: NSWindow, baseName: String) {
        self.store = store
        self.window = window
        let firstIndex = store.selection.min() ?? 0
        let firstSize = store.pdf.page(at: firstIndex)?.dataRepresentation
            .flatMap { NSPDFImageRep(data: $0)?.bounds.size }
        options = ExportOptions(baseName: baseName, pageCount: store.pageCount,
                                selectedCount: store.selection.count, firstPageSize: firstSize)
    }

    // MARK: Asking

    func begin(completion: @escaping () -> Void) {
        self.completion = completion
        guard let window else { completion(); return }

        // An open panel (choosing a folder), not a save panel: a sandboxed app is only allowed
        // to write into a folder the user has chosen, not next to a single saved file.
        let panel = NSOpenPanel()
        panel.title = "Export as Images"
        panel.message = "Choose where to save the images."
        panel.prompt = "Export"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let accessory = NSHostingView(rootView: ExportOptionsView(options: options))
        accessory.setFrameSize(accessory.fittingSize)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let directory = panel.url else { finish(); return }
            prepare(in: directory)
        }
    }

    private func prepare(in directory: URL) {
        options.remember()

        let pageIndexes: [Int] = options.selectedOnly
            ? store.selection.filter { $0 < store.pageCount }.sorted()
            : Array(0..<store.pageCount)
        let target = options.useFolder
            ? directory.appendingPathComponent(options.cleanBaseName, isDirectory: true)
            : directory

        jobs = pageIndexes.map { index in
            (page: index, url: target.appendingPathComponent(options.fileName(forPage: index + 1)))
        }
        guard !jobs.isEmpty else { finish(); return }

        let existing = jobs.filter { FileManager.default.fileExists(atPath: $0.url.path) }.count
        guard existing > 0, let window else {
            start(creating: target)
            return
        }

        let alert = NSAlert()
        alert.messageText = existing == 1 ? "One file already exists." : "\(existing) files already exist."
        alert.informativeText = "Do you want to replace \(existing == 1 ? "it" : "them")?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [self] response in
            if response == .alertFirstButtonReturn { start(creating: target) } else { finish() }
        }
    }

    // MARK: Running

    private func start(creating folder: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            present(error)
            finish()
            return
        }

        progress = ExportProgress(total: jobs.count)
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: ExportProgressView(progress: progress)))
        self.sheet = sheet
        window?.beginSheet(sheet)

        DispatchQueue.main.async { [self] in step() }
    }

    private func step() {
        guard !progress.cancelled, nextJob < jobs.count else {
            endSheet()
            if !failedPages.isEmpty { reportFailures() }
            else if !progress.cancelled, let first = jobs.first {
                NSWorkspace.shared.activateFileViewerSelecting([first.url])
            }
            finish()
            return
        }

        let job = jobs[nextJob]
        nextJob += 1
        autoreleasepool {
            var written = false
            if let page = store.pdf.page(at: job.page),
               let data = Self.encode(page, format: options.format, dpi: options.dpi, quality: options.jpegQuality) {
                written = (try? data.write(to: job.url, options: .atomic)) != nil
            }
            if !written { failedPages.append(job.page + 1) }
        }
        progress.done = nextJob
        DispatchQueue.main.async { [self] in step() }
    }

    private func endSheet() {
        if let sheet { window?.endSheet(sheet) }
        sheet = nil
    }

    private func reportFailures() {
        let alert = NSAlert()
        alert.messageText = "Some pages couldn't be exported."
        alert.informativeText = "Pages: " + failedPages.map(String.init).joined(separator: ", ")
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func present(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func finish() {
        completion()
        completion = {}
    }

    // MARK: Rendering

    /// Renders one page to image data. The page is drawn onto white (like paper), so PNG
    /// and TIFF files don't come out transparent and JPEGs don't go black.
    static func encode(_ page: PDFPage, format: ImageExportFormat, dpi: Int, quality: Double) -> Data? {
        // A one-page PDF through NSPDFImageRep, which applies the page's rotation and crop box.
        guard let pageData = page.dataRepresentation, let rep = NSPDFImageRep(data: pageData) else { return nil }

        let size = rep.bounds.size                       // points
        let scale = CGFloat(dpi) / 72
        let pixelsWide = max(1, Int((size.width * scale).rounded()))
        let pixelsHigh = max(1, Int((size.height * scale).rounded()))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = size                               // points per image: records the dpi in the file

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let area = NSRect(origin: .zero, size: size)
        NSColor.white.setFill()
        area.fill()
        rep.draw(in: area)
        NSGraphicsContext.restoreGraphicsState()

        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .tiff:
            return bitmap.representation(using: .tiff,
                                         properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }
}
