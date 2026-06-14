import Foundation
import Testing
@testable import Kuitti

/// Date math for the Dashboard's period scope. Pure value type → no model context needed.
struct ReportPeriodTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func monthIntervalSpansOneMonth() {
        let period = ReportPeriod(kind: .month, anchor: date(2026, 6, 14),
                                  customStart: date(2026, 6, 1), customEnd: date(2026, 6, 30))
        let interval = period.dateInterval
        #expect(interval.contains(date(2026, 6, 1)))
        #expect(interval.contains(date(2026, 6, 30)))
        #expect(!interval.contains(date(2026, 7, 1)))
        #expect(SpendingReport.monthStarts(in: interval).count == 1)
        #expect(period.isMultiMonth == false)
    }

    @Test func yearIntervalSpansTwelveMonths() {
        let period = ReportPeriod(kind: .year, anchor: date(2025, 3, 9),
                                  customStart: date(2025, 1, 1), customEnd: date(2025, 12, 31))
        #expect(SpendingReport.monthStarts(in: period.dateInterval).count == 12)
        #expect(period.isMultiMonth)
    }

    @Test func customRangeCrossingMonthBoundary() {
        let period = ReportPeriod(kind: .custom, anchor: date(2026, 1, 1),
                                  customStart: date(2026, 1, 28), customEnd: date(2026, 2, 3))
        let starts = SpendingReport.monthStarts(in: period.dateInterval)
        #expect(starts.count == 2)
        #expect(period.isMultiMonth)
        #expect(period.dateInterval.contains(date(2026, 2, 3)))
    }

    @Test func customRangeCrossingYearBoundary() {
        let period = ReportPeriod(kind: .custom, anchor: date(2025, 12, 1),
                                  customStart: date(2025, 12, 15), customEnd: date(2026, 1, 15))
        #expect(SpendingReport.monthStarts(in: period.dateInterval).count == 2)
    }

    @Test func customRangeRepairsInvertedBounds() {
        let period = ReportPeriod(kind: .custom, anchor: date(2026, 6, 1),
                                  customStart: date(2026, 6, 20), customEnd: date(2026, 6, 5))
        let interval = period.dateInterval
        #expect(interval.contains(date(2026, 6, 5)))
        #expect(interval.contains(date(2026, 6, 20)))
    }

    @Test func steppingClampsAtCurrentPeriod() {
        let now = date(2026, 6, 14)
        let period = ReportPeriod(kind: .month, anchor: now, customStart: now, customEnd: now)
        // Forward refuses to advance past the current month.
        let forward = period.stepped(by: 1, now: now)
        #expect(Calendar.current.isDate(forward.anchor, equalTo: now, toGranularity: .month))
        #expect(period.isCurrent(now: now))
        // Backward then re-checks current.
        let back = period.stepped(by: -1, now: now)
        #expect(Calendar.current.isDate(back.anchor, equalTo: date(2026, 5, 14), toGranularity: .month))
        #expect(!back.isCurrent(now: now))
    }

    @Test func elapsedMonthCountForCurrentYearCountsMonthsSoFar() {
        let now = date(2026, 6, 14)
        let period = ReportPeriod(kind: .year, anchor: now, customStart: now, customEnd: now)
        #expect(period.elapsedMonthCount(now: now) == 6)   // Jan…Jun started
    }

    @Test func elapsedMonthCountForPastYearIsFull() {
        let now = date(2026, 6, 14)
        let period = ReportPeriod(kind: .year, anchor: date(2024, 4, 1), customStart: now, customEnd: now)
        #expect(period.elapsedMonthCount(now: now) == 12)
    }

    @Test func previousIntervalOnlyForMonthAndYear() {
        let now = date(2026, 6, 14)
        let month = ReportPeriod(kind: .month, anchor: now, customStart: now, customEnd: now)
        let year = ReportPeriod(kind: .year, anchor: now, customStart: now, customEnd: now)
        let custom = ReportPeriod(kind: .custom, anchor: now, customStart: now, customEnd: now)
        #expect(month.previousInterval()?.contains(date(2026, 5, 14)) == true)
        #expect(year.previousInterval()?.contains(date(2025, 5, 14)) == true)
        #expect(custom.previousInterval() == nil)
        #expect(custom.comparisonLabel == nil)
    }
}
