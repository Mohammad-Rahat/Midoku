//
//  GeneralSettings.swift
//  Midoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct GeneralSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            incognitoMode,
            appLock,
            icloudSync
        ]
    }

    let incognitoMode = SettingsKey<Bool>("General.incognitoMode", default: false)
    let appLock = SettingsKey<Bool>("General.appLock", default: false)
    let icloudSync = SettingsKey<Bool>("General.icloudSync", default: false)
}
