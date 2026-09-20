//
//  AppearanceSettings.swift
//  Midoku
//
//  Created by skitty on 8/29/26.
//

import UIKit

struct AppearanceSettings: Sendable {
    var keys: [any SettingsDefault] {
        [
            useSystemAppearance,
            appearance,
            accent,
            chapterGrid,
            chapterGridStyle,
            chapterPortraitColumns,
            chapterLandscapeColumns,
            layout,
            customPortraitRows,
            customLandscapeRows
        ]
    }

    let useSystemAppearance = SettingsKey<Bool>("General.useSystemAppearance", default: true)
    let appearance = SettingsKey<Int>("General.appearance", default: 0)
    let accent = SettingsKey<MidokuAccent>("Appearance.accent", default: .forest)
    let chapterGrid = SettingsKey<Bool>("Midoku.chapterGrid", default: false)
    let chapterGridStyle = SettingsKey<ChapterGridStyle>("Appearance.chapterGridStyle", default: .standard)
    let chapterPortraitColumns = SettingsKey<Int>("Appearance.chapterPortraitColumns", default: 3)
    let chapterLandscapeColumns = SettingsKey<Int>("Appearance.chapterLandscapeColumns", default: 5)

    let layout = SettingsKey<Layout>("Appearance.layout", default: .standard)
    let customPortraitRows = SettingsKey<Int>("Appearance.customPortraitRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 2)
    let customLandscapeRows = SettingsKey<Int>("Appearance.customLandscapeRows", default: UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4)
}
