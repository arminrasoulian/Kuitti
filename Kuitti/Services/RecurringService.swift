import Foundation
import SwiftData

/// Materializes due recurring templates into ordinary (editable, deletable) transactions.
/// Runs on launch and foregrounding — no push/background infra needed for a personal app.
struct RecurringService {
    static func materializeDue(context: ModelContext, now: Date = Date()) throws {
        let fetch = FetchDescriptor<RecurringTemplate>(predicate: #Predicate { $0.isActive })
        let templates = (try? context.fetch(fetch)) ?? []
        guard !templates.isEmpty else { return }

        let editor = TransactionEditor(context: context)
        for template in templates {
            // Catch-up loop: the app may have been closed across several periods.
            // The guard bound only exists to stop a corrupt nextDueDate from spinning.
            var safety = 0
            while template.isActive, template.nextDueDate <= now, safety < 240 {
                safety += 1
                if let end = template.endDate, template.nextDueDate > end {
                    template.isActive = false
                    break
                }
                try editor.createManual(
                    kind: template.kind,
                    date: template.nextDueDate,
                    amountMinor: template.amountMinor,
                    payee: template.name,
                    account: template.account,
                    category: template.category,
                    notes: template.notes,
                    paymentMethod: .bankTransfer,
                    source: .recurring
                )
                guard let next = advance(template.nextDueDate, frequency: template.frequency, interval: template.interval) else {
                    template.isActive = false
                    break
                }
                template.nextDueDate = next
            }
        }
        if context.hasChanges {
            try context.save()
        }
    }

    static func advance(_ date: Date, frequency: RecurrenceFrequency, interval: Int) -> Date? {
        let component: Calendar.Component = switch frequency {
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        return Calendar.current.date(byAdding: component, value: max(interval, 1), to: date)
    }
}
