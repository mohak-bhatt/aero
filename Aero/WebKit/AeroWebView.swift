//
//  AeroWebView.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import WebKit

/// WKWebView whose right-click menu talks about tabs instead of windows.
final class AeroWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items where item.title.contains("Window") {
            item.title = item.title.replacingOccurrences(of: "Window", with: "Tab")
        }
    }
}
