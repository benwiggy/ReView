import SwiftUI
import PDFKit

/// SwiftUI wrapper around PDFKit's PDFView.
struct PDFKitView: NSViewRepresentable {
    @ObservedObject var store: DocumentStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> PDFView {
        let view = MarkupPDFView()
                view.store = store
        view.autoScales = true
        // True-size zoom is above 1 on most screens, so the default limit would stop 400% short.
        view.maxScaleFactor = 20
        view.minScaleFactor = 0.05
        view.interpolationQuality = .high
        view.displayMode = store.displayMode
        view.displayDirection = store.effectiveDirection
        view.displaysAsBook = store.displaysAsBook
        view.displaysPageBreaks = store.displaysPageBreaks
        view.document = store.pdf
        store.pdfView = view

        let coordinator = context.coordinator
        coordinator.lastPDF = store.pdf
        coordinator.lastRevision = store.pageRevision
        coordinator.attach(to: view)
        coordinator.monitor = MarkupEventMonitor(view: view, store: store)
        DispatchQueue.main.async { [weak store] in store?.refreshZoom() }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        store.pdfView = view

        if coordinator.lastPDF !== store.pdf {
            // A different document (open, revert, filter, undo of a filter).
            view.document = store.pdf
            coordinator.lastPDF = store.pdf
            coordinator.lastRevision = store.pageRevision
            store.pendingPage = nil
        } else if coordinator.lastRevision != store.pageRevision {
            // Pages were added, removed, moved or rotated. PDFView doesn't reliably notice
            // that, so re-assign the document and put the view back where it was.
            coordinator.lastRevision = store.pageRevision
            let keep = view.currentPage
            view.document = nil
            view.document = store.pdf

            var target: PDFPage?
            if let index = store.pendingPage {
                target = store.pdf.page(at: index)
                store.pendingPage = nil
            } else if let keep, keep.document === store.pdf {
                target = keep
            } else {
                target = store.pdf.page(at: max(0, min(store.currentPage, store.pdf.pageCount - 1)))
            }
            if let target { view.go(to: target) }
        }

        if view.displayMode != store.displayMode { view.displayMode = store.displayMode }
        if view.displayDirection != store.effectiveDirection { view.displayDirection = store.effectiveDirection }
        if view.displaysAsBook != store.displaysAsBook { view.displaysAsBook = store.displaysAsBook }
        if view.displaysPageBreaks != store.displaysPageBreaks { view.displaysPageBreaks = store.displaysPageBreaks }
    }

    final class Coordinator: NSObject {
        let store: DocumentStore
        var lastPDF: PDFDocument?
        var lastRevision = -1
        var monitor: MarkupEventMonitor?
        private var observer: NSObjectProtocol?
        private var scaleObserver: NSObjectProtocol?

        init(store: DocumentStore) { self.store = store }

        func attach(to view: PDFView) {
            scaleObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewScaleChanged, object: view, queue: .main
            ) { [weak self] _ in
                // Deferred: this can fire while SwiftUI is mid-update.
                DispatchQueue.main.async { self?.store.refreshZoom() }
            }
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view,
                      let page = view.currentPage, let document = view.document,
                      document === self.store.pdf else { return }
                let index = document.index(for: page)
                guard index != NSNotFound else { return }
                // Deferred: this can fire while SwiftUI is mid-update.
                DispatchQueue.main.async { self.store.pageDidChange(to: index) }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) }
        }
    }
}
