import SwiftUI

struct AppLockGateView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Kuitti is locked")
                    .font(.title2.weight(.semibold))
                Button("Unlock") {
                    Task { await env.appLock.unlock() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(env.appLock.isAuthenticating)
            }
        }
        .task { await env.appLock.unlock() }
    }
}
