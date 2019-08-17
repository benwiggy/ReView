# ReView
A better attempt at Apple's own Preview app

MacOS has some incredibly powerful and flexible APIs for viewing, printing and converting images to other formats. It's such a shame that Apple's own Preview application has been woeful in implementing them. This project hopes to improve on Preview in the following ways:

1. Loaded documents will not be re-saved without the user's express permission. By default, alteration suggests saving with a new name.

2. Improved Exporting of file types and modification of PDFs using Quartz Filters. Currently, Preview has both "Export As PDF" and "Export...." with format PDF. They work in different ways, of course, but it's a terrible UI.

3. Improved AppleScript support.


Much of this is currently far beyond my abilities, so please feel free to contribute! The project goals are as follows:

* Open, view and print PDFs
* Open view and print other images
* Export files to other formats
* Apply Quartz Filters to PDFs
* Add Bookmarks (actual PDF-spec 'Outlines', not Apple's unique Bookmarks metadata!)

