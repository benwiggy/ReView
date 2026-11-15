import PDFKit

/// A value-type copy of a PDFOutline entry. Editing a plain tree of structs is far easier
/// (and easier to undo) than mutating PDFOutline objects; the tree is written back to
/// `PDFDocument.outlineRoot` only when saving or applying a filter.
struct BookmarkNode: Identifiable {
    let id = UUID()
    var title: String
    /// The destination page. Held by reference, so bookmarks follow their page when pages
    /// are reordered. If the page is deleted the bookmark is kept but has no destination.
    var page: PDFPage?
    var children: [BookmarkNode] = []

    /// `List(_:children:)` wants nil for leaves.
    var childrenOrNil: [BookmarkNode]? { children.isEmpty ? nil : children }
}

// MARK: - Tree helpers (index paths: [2, 0, 1] = third root item, its first child, that child's second child)

extension Array where Element == BookmarkNode {

    func path(of id: UUID) -> [Int]? {
        for (i, node) in enumerated() {
            if node.id == id { return [i] }
            if let sub = node.children.path(of: id) { return [i] + sub }
        }
        return nil
    }

    func node(at path: [Int]) -> BookmarkNode {
        let node = self[path[0]]
        return path.count == 1 ? node : node.children.node(at: [Int](path.dropFirst()))
    }

    mutating func mutateNode(at path: [Int], _ change: (inout BookmarkNode) -> Void) {
        if path.count == 1 {
            change(&self[path[0]])
        } else {
            self[path[0]].children.mutateNode(at: [Int](path.dropFirst()), change)
        }
    }

    @discardableResult
    mutating func removeNode(at path: [Int]) -> BookmarkNode {
        if path.count == 1 { return remove(at: path[0]) }
        return self[path[0]].children.removeNode(at: [Int](path.dropFirst()))
    }

    /// `path.last` is the insertion index within its parent's list.
    mutating func insertNode(_ node: BookmarkNode, at path: [Int]) {
        if path.count == 1 {
            insert(node, at: path[0])
        } else {
            self[path[0]].children.insertNode(node, at: [Int](path.dropFirst()))
        }
    }

    /// Number of siblings in the list that contains `path`.
    func siblingCount(at path: [Int]) -> Int {
        path.count == 1 ? count : node(at: [Int](path.dropLast())).children.count
    }

    /// Returns a copy with every destination page passed through `transform`.
    func remapped(_ transform: (PDFPage?) -> PDFPage?) -> [BookmarkNode] {
        map { node in
            var copy = node
            copy.page = transform(node.page)
            copy.children = node.children.remapped(transform)
            return copy
        }
    }
}
