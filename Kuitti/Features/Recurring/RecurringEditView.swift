import SwiftUI
import SwiftData

struct RecurringEditView: View {
    let existing: RecurringTemplate?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var name = ""
    @State private var kind: TransactionKind = .expense
    @State private var amountMinor = 0
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var nextDueDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var accountUUID: UUID?
    @State private var categoryUUID: UUID?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                scheduleSection
                detailsSection
            }
            .navigationTitle(existing == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amountMinor <= 0)
                }
            }
            .onChange(of: kind) { _, newKind in
                // Category list is kind-filtered; clear a now-invalid selection.
                let matching: CategoryKind = newKind == .expense ? .expense : .income
                if let uuid = categoryUUID,
                   categories.first(where: { $0.uuid == uuid })?.kind != matching {
                    categoryUUID = nil
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private var basicsSection: some View {
        Section {
            TextField("Name (e.g. Vuokra, Palkka)", text: $name)
            Picker("Type", selection: $kind) {
                Text("Expense").tag(TransactionKind.expense)
                Text("Income").tag(TransactionKind.income)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Amount")
                EuroAmountField("0,00", minor: $amountMinor)
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Repeats", selection: $frequency) {
                Text("Weekly").tag(RecurrenceFrequency.weekly)
                Text("Monthly").tag(RecurrenceFrequency.monthly)
                Text("Yearly").tag(RecurrenceFrequency.yearly)
            }
            Stepper(value: $interval, in: 1...12) {
                Text(intervalLabel)
            }
            DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
            Toggle("Ends", isOn: $hasEndDate)
            if hasEndDate {
                DatePicker("End date", selection: $endDate, displayedComponents: .date)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Account", selection: $accountUUID) {
                Text("None").tag(UUID?.none)
                ForEach(accounts.filter { !$0.isArchived }) { account in
                    Text(account.name).tag(UUID?.some(account.uuid))
                }
            }
            Picker("Category", selection: $categoryUUID) {
                Text("None").tag(UUID?.none)
                ForEach(categories.filter { $0.kind == matchingCategoryKind }) { category in
                    Text(category.name).tag(UUID?.some(category.uuid))
                }
            }
            TextField("Notes", text: $notes, axis: .vertical)
        }
    }

    private var matchingCategoryKind: CategoryKind {
        kind == .expense ? .expense : .income
    }

    private var intervalLabel: String {
        let unit: String = switch frequency {
        case .weekly: interval == 1 ? "week" : "weeks"
        case .monthly: interval == 1 ? "month" : "months"
        case .yearly: interval == 1 ? "year" : "years"
        }
        return "Every \(interval) \(unit)"
    }

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        kind = existing.kind
        amountMinor = existing.amountMinor
        frequency = existing.frequency
        interval = existing.interval
        nextDueDate = existing.nextDueDate
        hasEndDate = existing.endDate != nil
        endDate = existing.endDate ?? Date()
        accountUUID = existing.account?.uuid
        categoryUUID = existing.category?.uuid
        notes = existing.notes
    }

    private func save() {
        let template = existing ?? RecurringTemplate(
            name: "", kind: kind, amountMinor: 0, frequency: frequency, nextDueDate: nextDueDate
        )
        template.name = name.trimmingCharacters(in: .whitespaces)
        template.kind = kind
        template.amountMinor = amountMinor
        template.frequency = frequency
        template.interval = interval
        template.nextDueDate = Calendar.current.startOfDay(for: nextDueDate)
        template.endDate = hasEndDate ? endDate : nil
        template.account = accounts.first { $0.uuid == accountUUID }
        template.category = categories.first { $0.uuid == categoryUUID }
        template.notes = notes
        template.updatedAt = Date()
        if existing == nil { context.insert(template) }
        try? context.save()
        dismiss()
    }
}
