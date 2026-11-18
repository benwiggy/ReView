//
//  SettingsView.swift
//  ReView
//
//  Created by Ben on 26/10/2026.
//

import SwiftUI

/// The Settings window's content. (AppDelegate.showSettings creates the window.)
struct SettingsView: View {
    @AppStorage(AppSettings.Key.pageStyle) private var pageStyle = 1
    @AppStorage(AppSettings.Key.direction) private var direction = 0
    @AppStorage(AppSettings.Key.firstPageIsCover) private var firstPageIsCover = false
    @AppStorage(AppSettings.Key.pageBreaks) private var pageBreaks = true
    @AppStorage(AppSettings.Key.showSidebar) private var showSidebar = true
    @AppStorage(AppSettings.Key.sidebarTab) private var sidebarTab = 0
    @AppStorage(AppSettings.Key.sidebarWidth) private var sidebarWidth = 250.0
    @AppStorage(AppSettings.Key.thumbnailWidth) private var thumbnailWidth = 200.0
    @AppStorage(AppSettings.Key.authorName) private var authorName = ""

    var body: some View {
        Form {
            Section("Page display") {
                Picker("Style", selection: $pageStyle) {
                    Text("Single Page").tag(0)
                    Text("Single Page Continuous").tag(1)
                    Text("Two Pages").tag(2)
                    Text("Two Pages Continuous").tag(3)
                }
                Picker("Scrolling", selection: $direction) {
                    Text("Vertical").tag(0)
                    Text("Horizontal").tag(1)
                }
                .disabled(pageStyle != 1)
                if pageStyle != 1 {
                    Text("Scroll direction can only be changed for Single Page Continuous.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("First page is cover (two-page styles)", isOn: $firstPageIsCover)
                Toggle("Show page breaks", isOn: $pageBreaks)
            }
            
            Section("Annotations") {
                TextField("Author", text: $authorName, prompt: Text(NSFullUserName()))
                Text("Recorded on highlights, notes and other markup. Leave empty to use your Mac user name.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sidebar") {
                Toggle("Show sidebar when a document opens", isOn: $showSidebar)
                Picker("Show", selection: $sidebarTab) {
                    Text("Thumbnails").tag(0)
                    Text("Bookmarks").tag(1)
                    Text("Annotations").tag(2)
                }
                HStack {
                    Text("Sidebar width")
                    Slider(value: $sidebarWidth, in: AppSettings.sidebarWidthRange, step: 10)
                    Text("\(Int(sidebarWidth)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text("Thumbnail width")
                    Slider(value: $thumbnailWidth, in: AppSettings.thumbnailWidthRange, step: 10)
                    Text("\(Int(thumbnailWidth)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }

            Text("Page display and sidebar options apply to documents you open from now on. "
                 + "Thumbnail width changes open windows straight away. "
                 + "View > Save Current View as Default stores the front window's settings here.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 540)
    }
}
