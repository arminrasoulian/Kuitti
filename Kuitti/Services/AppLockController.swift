import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID/passcode gate, off by default; toggled in Settings.
@Observable
final class AppLockController {
    static let enabledKey = "appLockEnabled"

    var isLocked = false
    var isAuthenticating = false

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    func lockIfEnabled() {
        if Self.isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedReason = "Unlock Kuitti"
        do {
            // .deviceOwnerAuthentication = Face ID with passcode fallback.
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Kuitti"
            )
            if success { isLocked = false }
        } catch {
            Log.ui.error("App lock evaluation failed: \(String(describing: error))")
        }
    }
}
