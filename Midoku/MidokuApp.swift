//
//  MidokuApp.swift
//  Midoku
//
//  Created by Mohammad Rahat on 18/9/26.
//

import SwiftUI

@main
struct MidokuApp: App {
    @UIApplicationDelegateAdaptor(MidokuAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

