import SwiftUI
import LocalAuthentication
import Observation
import UIKit

@MainActor
@Observable
final class AppLockController {
    private(set) var state = LockState()
    private(set) var authenticating = false
    private(set) var message: String?
    private var context: LAContext?
    private var privacyWindow: UIWindow?
    private var epoch = UUID()

    func configure(enabled: Bool) { state.configure(enabled: enabled) }
    func changeEnabled(_ enabled: Bool, settings: AppSettingsStore) async {
        // Disabling is authenticated as well, even when a delayed unlock is still valid.
        guard await authenticate(reason: enabled ? "Protect your reading activity." : "Turn off the app lock.") else { return }
        do {
            try await settings.setAppLock(enabled)
            state.authenticated()
        } catch { message = "The app-lock change could not be saved. Your previous lock setting is still in use." }
    }
    func unlock() async {
        if await authenticate(reason: "Unlock your reading activity.") { state.authenticated(); privacyWindow?.isHidden = true }
    }
    private func authenticate(reason: String) async -> Bool {
        guard !authenticating else { return false }
        let token = epoch
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "Device authentication is unavailable. Set up a device passcode in iOS Settings, then try again."
            return false
        }
        self.context = context
        authenticating = true
        message = nil
        defer { authenticating = false; self.context = nil }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            guard epoch == token else { return false }
            return success
        } catch {
            message = "Authentication was not completed. Your reading activity stays protected. Try again when you are ready."
            return false
        }
    }
    func sceneChanged(_ phase: ScenePhase, preferences: AppPreferences) {
        switch phase {
        case .active:
            state.activate(at: Date(), enabled: preferences.appLock, delay: preferences.lockDelay)
            if state.isLocked { showLockWindow() } else { privacyWindow?.isHidden = true }
        case .inactive:
            if preferences.protectAppSwitcher || preferences.appLock { coverAllContent() }
        case .background:
            epoch = UUID()
            context?.invalidate()
            state.background(at: Date(), enabled: preferences.appLock, delay: preferences.lockDelay)
            if preferences.protectAppSwitcher || preferences.appLock { coverAllContent() }
        @unknown default: break
        }
    }
    private func showLockWindow() {
        coverAllContent()
        privacyWindow?.rootViewController = UIHostingController(rootView: AppLockView(lock: self))
    }
    // A separate opaque window also covers sheets, file pickers, and source verification views.
    private func coverAllContent() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState != .unattached && $0.activationState != .background }) else { return }
        if privacyWindow?.windowScene !== scene {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: PrivacyCover())
            privacyWindow = window
        }
        privacyWindow?.rootViewController = UIHostingController(rootView: PrivacyCover())
        privacyWindow?.isHidden = false
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            MidokuTheme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "book.closed").font(.largeTitle)
                Text("Midoku").font(.title2.weight(.semibold))
            }
            .foregroundStyle(MidokuTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Midoku content is hidden")
    }
}

struct AppLockView: View {
    let lock: AppLockController
    var body: some View {
        ZStack {
            MidokuTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                MidokuBrandTile(size: 80)
                Text("Your reading, just for you").font(.title2.bold()).multilineTextAlignment(.center)
                Text(lock.message ?? "Unlock Midoku with Face ID, Touch ID, or your device passcode.")
                    .foregroundStyle(MidokuTheme.secondaryText).multilineTextAlignment(.center)
                Button { Task { await lock.unlock() } } label: {
                    Label(lock.authenticating ? "Unlocking…" : "Unlock Midoku", systemImage: "lock.open")
                }
                .buttonStyle(MidokuPrimaryButtonStyle()).disabled(lock.authenticating)
            }.padding(32).frame(maxWidth: 480)
        }
    }
}
