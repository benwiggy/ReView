# ReView
A better attempt at Apple's own Preview app

MacOS has some incredibly powerful and flexible APIs for viewing, printing and converting images to other formats. It's such a shame that Apple's own Preview application has been woeful in implementing them. This project hopes to improve on Preview in the following ways:

1. Loaded documents will not be auto-saved without the user's express permission. By default, alteration suggests saving with a new name. This is important, as PDF files and images may be originals that should not be overwritten. PDFKit is not capable of replicating all types of PDF; also successive JPEGing of images may cause lossage.

2. Preview has a limit of c.15 windows, after which it puts all documents in tabs.

3. Improved Exporting of file types and modification of PDFs using Quartz Filters. Currently, Preview has both "Export As PDF" and "Export...." with format PDF. They work in different ways, of course, but it's a terrible UI. It would also be nice to see Quartz Filters applied in a similar way to ColorSync Utility.

4. Support creation and editing of PDF Bookmarks (e.g. Table of Contents). Preview's own 'bookmarks' are proprietary: they do not work in other PDF viewers. PDFKit has a perfectly good set of objects (PDFOutline) for working with bookmarks.

5. Save As PDF/X-3 (using a better Filter than Apple's own); individual pages; booklet. Add a variety of text of graphics to existing document.

6. Improved AppleScript support. Preview has only recently included any AppleScript support, and most of it is 'generic'. It would be good to include exporting to other formats.

Much of this is far beyond my abilities, so please feel free to contribute! Grateful Acknowledgement is made to Howard Oakley, who provided the basic app template, and Pat Garner, who helped rewrite the sidebar UI code. 

# Release Notes

### v.1.0 Stable Release!

Version 1.0 has the following features:  
* Opens PDFs for Viewing as 1-up or 2-up (with first page on its own or not); Single or Continuous pages.
* Horizontal or vertical PDF page layouts (in Single Page Continuous mode).
* Default view styles can be set in Preferences and saved.
* Individual pages can be rotated left or right.
* Individual pages can be deleted (with warning).
* Blank pages can be added.
* Print using accurate page positioning for duplexing with enhanced print panel.
* Applies Quartz Filters to PDF documents.
* Saves documents when asked, if altered.
* New PDF from Clipboard image data.
* Improved sidebar UI.
* App is now signed, so will run on any Mac without annoyance.
* Undo now supported for page rotation and deletion. (E.g. not for Quartz Filters.)



#### To Do List and Known problems:
* Dragging thumbnails is unreliable and not recommended.
* Editing and Viewing PDF Outlines (bookmarks) in sidebar.

