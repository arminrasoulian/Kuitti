import Foundation

/// The scope the Dashboard reports on: a single month, a calendar year, or a custom date range.
///
/// Pure value type (no `@Model`) so the date math is unit-testable off the main actor — kept
/// `nonisolated` like the app's other value types (`Money`, `NameDisplay`). It is the single
/// source of date truth for the Dashboard; it replaces the old `selectedMonth` `@State`.
nonisolated struct ReportPeriod: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case month, year, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .month: "Month"
            case .year: "Year"
            case .custom: "Custom"
            }
        }
    }

    var kind: Kind
    /// For `.month` / `.year`: any date inside the chosen period (the "anchor"). Ignored for `.custom`.
    var anchor: Date
    /// Only meaningful when `kind == .custom`.
    var customStart: Date
    var customEnd: Date

    private var calendar: Calendar { Calendar.current }

    /// The default period: the current month.
    static func current(now: Date = Date()) -> ReportPeriod {
        ReportPeriod(kind: .month, anchor: now, customStart: now, customEnd: now)
    }

    // MARK: - Resulting interval

    /// The interval to filter transactions against (matches the app's `interval.contains($0.date)`
    /// convention). For custom ranges the bounds are normalized to start-of-day(min)…start-of-day
    /// after max, and an inverted range (start > end) is repaired by ordering.
    var dateInterval: DateInterval {
        switch kind {
        case .month:
            return calendar.dateInterval(of: .month, for: anchor)
                ?? DateInterval(start: anchor, duration: 0)
        case .year:
            return calendar.dateInterval(of: .year, for: anchor)
                ?? DateInterval(start: anchor, duration: 0)
        case .custom:
            let lo = min(customStart, customEnd)
            let hi = max(customStart, customEnd)
            let start = calendar.startOfDay(for: lo)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: hi)) ?? hi
            return DateInterval(start: start, end: end)
        }
    }

    // MARK: - Display label

    var displayLabel: String {
        switch kind {
        case .month:
            // Standalone month name (LLLL) — in Finnish the nominative form, not the partitive MMMM.
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            return formatter.string(from: anchor)
        case .year:
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
            return formatter.string(from: anchor)
        case .custom:
            let lo = min(customStart, customEnd), hi = max(customStart, customEnd)
            let start = lo.formatted(date: .abbreviated, time: .omitted)
            if calendar.isDate(lo, inSameDayAs: hi) { return start }
            return "\(start) – \(hi.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    // MARK: - Stepping (month / year only)

    /// Step the anchor by ±1 unit, clamped so the period never starts in the future. Custom
    /// ranges don't step (returns `self`).
    func stepped(by delta: Int, now: Date = Date()) -> ReportPeriod {
        guard kind != .custom else { return self }
        let unit: Calendar.Component = (kind == .year) ? .year : .month
        guard let next = calendar.date(byAdding: unit, value: delta, to: anchor) else { return self }
        let nextStart = calendar.dateInterval(of: unit, for: next)?.start ?? next
        guard nextStart <= now else { return self }
        var copy = self
        copy.anchor = next
        return copy
    }

    /// True when the anchor's period contains `now` — disables the forward chevron. Custom is
    /// always "current" (no stepping).
    func isCurrent(now: Date = Date()) -> Bool {
        switch kind {
        case .month: return calendar.isDate(anchor, equalTo: now, toGranularity: .month)
        case .year: return calendar.isDate(anchor, equalTo: now, toGranularity: .year)
        case .custom: return true
        }
    }

    // MARK: - Month spans

    /// True when the period covers more than one calendar month (drives the trend card and
    /// budget scaling).
    var isMultiMonth: Bool {
        SpendingReport.monthStarts(in: dateInterval).count > 1
    }

    /// Months in the period that have already started as of `now` (≥ 1). Drives budget scaling:
    /// a still-running year counts only the elapsed months, so the bars stay a fair "on track?"
    /// signal.
    func elapsedMonthCount(now: Date = Date()) -> Int {
        SpendingReport.elapsedMonthCount(in: dateInterval, now: now)
    }

    // MARK: - Previous period (for the summary comparison line)

    /// The comparable previous period of the same kind; `nil` for custom (no natural predecessor).
    func previousInterval() -> DateInterval? {
        switch kind {
        case .month:
            guard let prev = calendar.date(byAdding: .month, value: -1, to: anchor) else { return nil }
            return calendar.dateInterval(of: .month, for: prev)
        case .year:
            guard let prev = calendar.date(byAdding: .year, value: -1, to: anchor) else { return nil }
            return calendar.dateInterval(of: .year, for: prev)
        case .custom:
            return nil
        }
    }

    /// Caption for the expenses comparison line ("vs last month" / "vs last year"); `nil` for custom.
    var comparisonLabel: String? {
        switch kind {
        case .month: "vs last month"
        case .year: "vs last year"
        case .custom: nil
        }
    }
}
