//
//  AppSettings.swift
//  ReView
//
//  Created by Ben on 26/10/2026.
//


import Foundation
import CoreGraphics

/// Default view options, saved in UserDefaults and edited in the Settings window.
/// New documents read them when they open.
enum AppSettings {
    enum Key {
        static let pageStyle = "pageStyle"                 // 0 single, 1 single continuous, 2 two-up, 3 two-up continuous
        static let direction = "scrollDirection"           // 0 vertical, 1 horizontal
        static let firstPageIsCover = "firstPageIsCover"
        static let pageBreaks = "showPageBreaks"
        static let showSidebar = "showSidebar"
        static let sidebarTab = "sidebarTab"               // 0 thumbnails, 1 bookmarks
        static let sidebarWidth = "sidebarWidth"
        static let thumbnailWidth = "thumbnailWidth"
    }

    static let sidebarWidthRange: ClosedRange<Double> = 200...420
    static let thumbnailWidthRange: ClosedRange<Double> = 100...300

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.pageStyle: 1,
            Key.direction: 0,
            Key.firstPageIsCover: false,
            Key.pageBreaks: true,
            Key.showSidebar: true,
            Key.sidebarTab: 0,
            Key.sidebarWidth: 210.0,
            Key.thumbnailWidth: 200.0
        ])
    }

    static var thumbnailWidth: CGFloat {
        let value = UserDefaults.standard.double(forKey: Key.thumbnailWidth)
        return CGFloat(min(max(value, thumbnailWidthRange.lowerBound), thumbnailWidthRange.upperBound))
    }
}
