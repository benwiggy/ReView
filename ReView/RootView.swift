import SwiftUI

/// The right-hand pane: the PDF, with the search status bar and busy spinner floating over it.
/// (The sidebar is a separate pane in an NSSplitViewController; see DocumentWindowController.)
struct PDFAreaView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        PDFKitView(store: store)
            .overlay(alignment: .bottom) {
                if store.isSearching || !store.searchResults.isEmpty {
                    SearchStatusBar(store: store).padding(12)
                }
            }
            .overlay {
                if store.isBusy {
                    ProgressView("Applying filter…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
    }
}

struct SidebarView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $store.sidebarTab) {
                Text("Thumbnails").tag(SidebarTab.thumbnails)
                Text("Bookmarks").tag(SidebarTab.bookmarks)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch store.sidebarTab {
            case .thumbnails: ThumbnailCollectionView(store: store)
            case .bookmarks:  BookmarksView(store: store)
            }
        }
        .background(.background)
    }
}

/// "3 of 12" with previous/next, floating over the bottom of the PDF.
struct SearchStatusBar: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 10) {
            if store.isSearching { ProgressView().controlSize(.small) }
            Text(store.searchResults.isEmpty
                 ? "Searching…"
                 : "\(store.searchIndex + 1) of \(store.searchResults.count)\(store.isSearching ? "+" : "")")
                .monospacedDigit()
            Button { store.previousResult() } label: { Image(systemName: "chevron.up") }
                .help("Previous Match (⇧⌘G)")
            Button { store.nextResult() } label: { Image(systemName: "chevron.down") }
                .help("Next Match (⌘G)")
            Button { store.cancelSearch() } label: { Image(systemName: "xmark.circle.fill") }
                .help("Clear Search")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 3, y: 1)
    }
}
