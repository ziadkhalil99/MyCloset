//
//  My_ClosetApp.swift
//  My Closet
//
//  Created by Ziad Ali Khalil on 07/11/2026.
//

import SwiftUI

@main
struct My_ClosetApp: App {
    /// Receives iOS's wake-ups for studio photos that finished uploading in the background.
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
