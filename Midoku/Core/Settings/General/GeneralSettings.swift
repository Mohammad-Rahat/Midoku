//
//  GeneralSettings.swift
//  Midoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct GeneralSettings: Sendable {
    enum AppLockDelay: String, SettingsValue, CaseIterable {
        case immediately
        case fifteenSeconds
        case thirtySeconds
        case oneMinute
        case fiveMinutes
        case fifteenMinutes

        var seconds: TimeInterval {
            switch self {
            case .immediately: 0
            case .fifteenSeconds: 15
            case .thirtySeconds: 30
            case .oneMinute: 60
            case .fiveMinutes: 300
            case .fifteenMinutes: 900
            }
        }

        var title: String {
            switch self {
            case .immediately: "Immediately"
            case .fifteenSeconds: "After 15 seconds"
            case .thirtySeconds: "After 30 seconds"
            case .oneMinute: "After 1 minute"
            case .fiveMinutes: "After 5 minutes"
            case .fifteenMinutes: "After 15 minutes"
            }
        }
    }

    var keys: [any SettingsDefault] {
        [
            incognitoMode,
            appLock,
            appLockDelay,
            blurAppSwitcher,
            icloudSync
        ]
    }

    let incognitoMode = SettingsKey<Bool>("General.incognitoMode", default: false)
    let appLock = SettingsKey<Bool>("General.appLock", default: false)
    let appLockDelay = SettingsKey<AppLockDelay>("General.appLockDelay", default: .oneMinute)
    let blurAppSwitcher = SettingsKey<Bool>("General.blurAppSwitcher", default: true)
    let icloudSync = SettingsKey<Bool>("General.icloudSync", default: false)
}
