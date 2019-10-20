# ReView
A better attempt at Apple's own Preview app

MacOS has some incredibly powerful and flexible APIs for viewing, printing and converting images to other formats. It's such a shame that Apple's own Preview application has been woeful in implementing them. This project hopes to improve on Preview in the following ways:

1. Loaded documents will not be auto-saved without the user's express permission. By default, alteration suggests saving with a new name. This is important, as PDF files and images may be originals that should not be overwritten. PDFKit is not capable of replicating all types of PDF (e.g. PDF/A, etc); also successive JPEGing of images may cause lossage. Disabling auto-saving is no longer possible on a per-app basis.

2. Improved Exporting of file types and modification of PDFs using Quartz Filters. Currently, Preview has both "Export As PDF" and "Export...." with format PDF. They work in different ways, of course, but it's a terrible UI. It would also be nice to see Quartz Filters applied in a similar way to ColorSync Utility.

3. Support creation and editing of PDF Bookmarks (e.g. Table of Contents). Preview's own 'bookmarks' are proprietary: they do not work in other PDF viewers. PDFKit has a perfectly good set of objects (PDFOutline) for working with bookmarks.

4. Save As PDF/X-3 (using a better Filter than Apple's own); individual pages; booklet. Add a variety of text of graphics to existing document.

5. Improved AppleScript support. Preview has only recently included any AppleScript support, and most of it is 'generic'. It would be good to include exporting to other formats.

Much of this is far beyond my abilities, so please feel free to contribute! Grateful Acknowledgement is made to Howard Oakley, who provided the basic code to get the app up and running.

# Release Notes

### 0.15
Review is still very much in 'alpha' phase. The current release of ReView does the following:
* Opens PDFs for Viewing as 1-up or 2-up (with first page on its own or not); Single or Continuous pages.
* Rotate individual pages left or right
* Prints using accurate page positioning for duplexing with enhanced print panel.
* Deletes individual pages (with warning).
* Adds blank pages
* Applies Quartz Filter to PDF documents.
* Saves documents when asked, if altered.

#### Known problems:
There is no Undo. However, Revert to Saved works.

