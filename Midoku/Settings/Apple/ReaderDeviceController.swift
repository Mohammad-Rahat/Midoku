import SwiftUI
import UIKit
import Observation

@MainActor
final class MidokuAppDelegate: NSObject, UIApplicationDelegate {
    static var readerOrientations: UIInterfaceOrientationMask = .allButUpsideDown
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.readerOrientations
    }
}

@MainActor
@Observable
final class ReaderDeviceController {
    private var brightness: CGFloat?
    private var idleTimerDisabled: Bool?
    private var previousOrientation: UIInterfaceOrientationMask?
    private(set) var orientationMessage: String?

    func begin(_ preferences: ReaderPreferences) {
        if brightness == nil { brightness = UIScreen.main.brightness }
        if idleTimerDisabled == nil { idleTimerDisabled = UIApplication.shared.isIdleTimerDisabled }
        if previousOrientation == nil { previousOrientation = MidokuAppDelegate.readerOrientations }
        apply(preferences)
    }
    func apply(_ preferences: ReaderPreferences) {
        guard brightness != nil else { return }
        UIScreen.main.brightness = preferences.customBrightness ? preferences.brightness : (brightness ?? UIScreen.main.brightness)
        UIApplication.shared.isIdleTimerDisabled = preferences.keepAwake
        let mask: UIInterfaceOrientationMask
        switch preferences.orientation {
        case .automatic: mask = .allButUpsideDown
        case .portrait: mask = .portrait
        case .landscape: mask = .landscape
        }
        updateOrientation(mask)
    }
    func suspend() {
        if let brightness { UIScreen.main.brightness = brightness }
        if let idleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = idleTimerDisabled }
    }
    func end() {
        suspend()
        if let previousOrientation { updateOrientation(previousOrientation) }
        brightness = nil; idleTimerDisabled = nil; previousOrientation = nil
    }
    private func updateOrientation(_ mask: UIInterfaceOrientationMask) {
        guard MidokuAppDelegate.readerOrientations != mask else { return }
        MidokuAppDelegate.readerOrientations = mask
        orientationMessage = nil
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where scene.activationState == .foregroundActive {
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
                Task { @MainActor in self?.orientationMessage = "Rotation is unavailable in the current window. You can keep reading or choose Automatic." }
            }
        }
    }
}
