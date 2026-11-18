# ReView
A better attempt at Apple's own Preview app

MacOS has some incredibly powerful and flexible APIs for viewing, printing and converting images to other formats. It's such a shame that Apple's own Preview application has been woeful in implementing them. This project hopes to improve on Preview in the following ways:

1. Loaded documents will not be auto-saved without the user's express permission. By default, alteration suggests saving with a new name. This is important, as PDF files and images may be originals that should not be overwritten. PDFKit is not capable of replicating all types of PDF; also successive JPEGing of images may cause lossage.

2. Preview has a limit of c.15 windows, after which it puts all documents in tabs.

3. Improved Exporting of file types and modification of PDFs using Quartz Filters. Currently, Preview has both "Export As PDF" and "Export...." with format PDF. They work in different ways, of course, but it's a terrible UI. It would also be nice to see Quartz Filters applied in a similar way to ColorSync Utility.

4. Support creation and editing of PDF Bookmarks (e.g. Table of Contents). Preview's own 'bookmarks' are proprietary: they do not work in other PDF viewers. PDFKit has a perfectly good set of objects (PDFOutline) for working with bookmarks.


# Release Notes

v.2.01. Fix for issue with 'Go to Page' dialog.

### v.2.0 New Release!

ReView has been rewritten from scratch using SwiftUI. (Yes, Claude did the heavy lifting.) Much more robust implementation.

* Import images as PDF and Export PDF as images. New documents from image data in Clipboard.

* Supports drag and drop of page thumbnails in both directions: export selected pages, or import images/PDFs into the current document.

* Export PDFs, split at Bookmarks, at any hierarchical level.

* Support for encrypted PDFs.

* Bookmarks can be created and edited.

* Preferences save default view styles.

* Support for Horizontal and Vertical page layout.

* Support for Annotations and Markup: Notes, Highlighter; add text, lines and shapes.

* Quartz Filters can be applied to the current document.

* Document metadata (e.g. Title, Author, Creator) can be edited. 

* Lower memory footprint than Preview!


