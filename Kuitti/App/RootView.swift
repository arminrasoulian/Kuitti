import SwiftUI

/// Top-level container: plays the launch `SplashView` over the app on cold
/// launch, then fades it away to reveal `RootTabView`. Onboarding (for new
/// users) is held back until the splash finishes so it never flashes underneath.
struct RootView: View {
    /// Intro finished playing — release onboarding / App Lock. They mount beneath
    /// the still-visible splash, which then cross-fades to reveal them.
    @State private var introDone = false
    /// Splash fully faded out — drop it from the hierarchy.
    @State private var showSplash = true

    var body: some View {
        ZStack {
            RootTabView(splashFinished: introDone)

            if showSplash {
                SplashView(
                    onReady: { introDone = true },
                    onFinished: { showSplash = false }
                )
                .zIndex(1)
            }
        }
    }
}
