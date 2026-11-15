import SwiftUI

/// Editable, nestable bookmarks (the PDF's outline).
struct BookmarksView: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            if store.bookmarks.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No Bookmarks").font(.headline)
                    Text("Press ⌘D to bookmark the page you're viewing.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                List(store.bookmarks, children: \.childrenOrNil, selection: $store.bookmarkSelection) { node in
                    HStack {
                        Text(node.title).lineLimit(1)
                        Spacer()
                        Text(store.pageNumber(for: node).map { "\($0)" } ?? "–")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Rename…") { store.bookmarkSelection = node.id; store.promptRenameSelectedBookmark() }
                        Button("Set Destination to Current Page") {
                            store.bookmarkSelection = node.id
                            store.setSelectedBookmarkDestinationToCurrentPage()
                        }
                        Divider()
                        Button("Delete") { store.bookmarkSelection = node.id; store.deleteSelectedBookmark() }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: store.bookmarkSelection) { _, id in
                    if let id { store.goToBookmark(id) }
                }
            }

            Divider()
            HStack(spacing: 2) {
                button("plus", "Add Bookmark (⌘D)") { store.addBookmark(asChild: false) }
                button("arrow.turn.down.right", "Add Sub-bookmark (⌥⌘D)", needsSelection: true) { store.addBookmark(asChild: true) }
                Divider().frame(height: 14)
                button("decrease.indent", "Outdent (⌥⌘←)", needsSelection: true) { store.outdentSelectedBookmark() }
                button("increase.indent", "Indent (⌥⌘→)", needsSelection: true) { store.indentSelectedBookmark() }
                button("arrow.up", "Move Up (⌥⌘↑)", needsSelection: true) { store.moveSelectedBookmark(by: -1) }
                button("arrow.down", "Move Down (⌥⌘↓)", needsSelection: true) { store.moveSelectedBookmark(by: 1) }
                Spacer()
                button("trash", "Delete Bookmark (⌥⌘⌫)", needsSelection: true) { store.deleteSelectedBookmark() }
            }
            .padding(6)
        }
    }

    private func button(_ symbol: String, _ help: String, needsSelection: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 20) }
            .buttonStyle(.borderless)
            .help(help)
            .disabled(needsSelection && store.bookmarkSelection == nil)
    }
}
