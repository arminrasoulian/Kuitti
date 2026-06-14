import SwiftUI

/// The animated launch experience. It opens on the *exact* composition the
/// static launch screen shows (spruce field + the `LaunchLogo` receipt mark,
/// centered) so there is no visible pop when the app's first frame replaces the
/// system launch image. It then "brings the receipt to life": the price-history
/// trend line draws itself across the receipt and breaks past the top edge into
/// an arrow, data dots pop, and the wordmark fades up — ending on the same mark
/// as the home-screen icon.
///
/// Honors Reduce Motion (no draw-on; a calm fade instead).
struct SplashView: View {
    /// Fired when the intro animation has played and the app may take over —
    /// the parent lets onboarding / App Lock present *beneath* the still-opaque
    /// splash, which then cross-fades to reveal them.
    var onReady: () -> Void = {}
    /// Fired after the splash has fully faded out; the parent removes it.
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lineProgress: CGFloat = 0
    @State private var showMidDot = false
    @State private var showLeadDot = false
    @State private var showArrow = false
    @State private var showWordmark = false
    @State private var finishing = false

    /// Point size of the centered mark — matches the `LaunchLogo` asset's
    /// natural size so the splash mark sits exactly where the launch image did.
    private let markSize: CGFloat = 240

    private var scale: CGFloat { markSize / Mark.cropSide }

    var body: some View {
        ZStack {
            Color("LaunchBG")
            RadialGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0)],
                center: .center, startRadius: 0, endRadius: markSize * 1.3)
            .blendMode(.softLight)

            mark
                .scaleEffect(finishing && !reduceMotion ? 1.08 : 1)

            wordmark
                .offset(y: 168)
                .opacity(showWordmark ? 1 : 0)
                .offset(y: showWordmark ? 0 : 12)
        }
        .opacity(finishing ? 0 : 1)   // the whole splash cross-fades to the app
        .ignoresSafeArea()
        .task { await playIntro() }
        .accessibilityElement()
        .accessibilityLabel("Kuitti")
    }

    // MARK: - Mark (receipt image + animated trend overlay)

    private var mark: some View {
        ZStack {
            // The receipt itself == the static launch image, so the hand-off is
            // seamless. Only the trend is animated on top of it.
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)

            trendOverlay
                .frame(width: markSize, height: markSize)
        }
    }

    private var trendOverlay: some View {
        ZStack {
            // white halo + green line, revealed left→right
            TrendLineShape()
                .trim(from: 0, to: lineProgress)
                .stroke(.white, style: .init(lineWidth: 50 * scale,
                                             lineCap: .round, lineJoin: .round))
            TrendLineShape()
                .trim(from: 0, to: lineProgress)
                .stroke(Mark.line, style: .init(lineWidth: 28 * scale,
                                                lineCap: .round, lineJoin: .round))

            // arrowhead (white halo behind a bright emerald head)
            ZStack {
                ArrowheadShape()
                    .stroke(.white, style: .init(lineWidth: 30 * scale, lineJoin: .round))
                ArrowheadShape().fill(.white)
                ArrowheadShape().fill(Mark.lineHi)
            }
            .opacity(showArrow ? 1 : 0)
            .scaleEffect(showArrow ? 1 : 0.4, anchor: .init(x: 0.87, y: 0.21))

            dot(at: Mark.midDot, halo: 21, inner: 11, color: Mark.line, shown: showMidDot)
            dot(at: Mark.leadDot, halo: 23, inner: 12, color: Mark.lineHi, shown: showLeadDot)
        }
    }

    private func dot(at p: CGPoint, halo: CGFloat, inner: CGFloat,
                     color: Color, shown: Bool) -> some View {
        let center = Mark.map(p, in: CGRect(x: 0, y: 0, width: markSize, height: markSize))
        return ZStack {
            Circle().fill(.white).frame(width: halo * 2 * scale, height: halo * 2 * scale)
            Circle().fill(color).frame(width: inner * 2 * scale, height: inner * 2 * scale)
        }
        .position(center)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.2)
    }

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("Kuitti")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Receipts, understood")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    // MARK: - Timeline

    private func playIntro() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) {
                lineProgress = 1; showMidDot = true; showLeadDot = true
                showArrow = true; showWordmark = true
            }
            await sleep(1.3)
            await finish()
            return
        }

        await sleep(0.15)
        withAnimation(.easeInOut(duration: 0.85)) { lineProgress = 1 }   // draw trend
        await sleep(0.40)
        withAnimation(.easeOut(duration: 0.55)) { showWordmark = true }   // wordmark fades up
        await sleep(0.25)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showMidDot = true }
        await sleep(0.22)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showLeadDot = true }
        await sleep(0.10)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { showArrow = true }  // arrow pops
        await sleep(0.95)                                                 // hold the finished mark
        await finish()
    }

    private func finish() async {
        // Let the app (and any onboarding / App Lock) mount beneath the still-
        // opaque splash, then cross-fade — with a slight zoom — to reveal it.
        onReady()
        withAnimation(.easeIn(duration: 0.5)) { finishing = true }
        await sleep(0.52)
        onFinished()
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Mark geometry (mirrors Design/icon.py — keep in sync)

/// The trend mark in the 1024 icon design space, cropped to the launch window.
/// `map` projects a design-space point into a SwiftUI rect. Pure value math, so
/// it is `nonisolated` — `Shape.path(in:)` (a nonisolated requirement) calls it.
nonisolated enum Mark {
    static let cropX: CGFloat = 180
    static let cropY: CGFloat = 180
    static let cropSide: CGFloat = 664

    static let trend: [CGPoint] = [
        CGPoint(x: 372, y: 686), CGPoint(x: 452, y: 612), CGPoint(x: 536, y: 648),
        CGPoint(x: 628, y: 470), CGPoint(x: 700, y: 388),
    ]
    static let tip = CGPoint(x: 814, y: 248)
    static let headLen: CGFloat = 92
    static let headHalf: CGFloat = 54

    static var midDot: CGPoint { trend[1] }
    static var leadDot: CGPoint { trend[4] }

    static let line = Color(red: 21 / 255, green: 128 / 255, blue: 95 / 255)   // #157F5F
    static let lineHi = Color(red: 31 / 255, green: 180 / 255, blue: 136 / 255) // #1FB488

    static func map(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        let u = (p.x - cropX) / cropSide
        let v = (p.y - cropY) / cropSide
        return CGPoint(x: rect.minX + u * rect.width, y: rect.minY + v * rect.height)
    }

    /// (tip, barb1, barb2, base) of the breakout arrowhead, in design space.
    static func arrowhead() -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let lp = trend[trend.count - 1]
        let dx = tip.x - lp.x, dy = tip.y - lp.y
        let len = (dx * dx + dy * dy).squareRoot()
        let ux = dx / len, uy = dy / len
        let px = -uy, py = ux
        let base = CGPoint(x: tip.x - ux * headLen, y: tip.y - uy * headLen)
        let b1 = CGPoint(x: base.x + px * headHalf, y: base.y + py * headHalf)
        let b2 = CGPoint(x: base.x - px * headHalf, y: base.y - py * headHalf)
        return (tip, b1, b2, base)
    }
}

/// The rising trend polyline (open path, so `.trim` reveals it left→right),
/// ending at the arrowhead's base.
private struct TrendLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let (_, _, _, base) = Mark.arrowhead()
        let pts = (Mark.trend + [base]).map { Mark.map($0, in: rect) }
        var path = Path()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }
}

/// The filled breakout arrowhead triangle.
private struct ArrowheadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let (tip, b1, b2, _) = Mark.arrowhead()
        var path = Path()
        path.move(to: Mark.map(tip, in: rect))
        path.addLine(to: Mark.map(b1, in: rect))
        path.addLine(to: Mark.map(b2, in: rect))
        path.closeSubpath()
        return path
    }
}

#Preview {
    SplashView(onFinished: {})
}
