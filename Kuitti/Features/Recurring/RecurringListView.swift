import SwiftUI
import SwiftData

struct RecurringListView: View {
    @Query(sort: \RecurringTemplate.nextDueDate) private var templates: [RecurringTemplate]
    @Environment(\.modelContext) private var context
    @State private var editing: RecurringTemplate?
    @State private var showAdd = false
    @State private var pendingDelete: RecurringTemplate?

    var body: some View {
        Group {
            if templates.isEmpty {
                EmptyStateView(
                    systemImage: "repeat",
                    title: "No recurring transactions",
                    message: "Rent, salary, and subscriptions can post themselves each period."
                )
            } else {
                List {
                    section(title: "Active", active: true)
                    section(title: "Paused", active: false)
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            Button("Add", systemImage: "plus") { showAdd = true }
        }
        .sheet(isPresented: $showAdd) { RecurringEditView(existing: nil) }
        .sheet(item: $editing) { RecurringEditView(existing: $0) }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let template = pendingDelete {
                    context.delete(template)
                    try? context.save()
                }
                pendingDelete = nil
            }
        } message: {
            Text("Already-posted transactions are kept.")
        }
    }

    @ViewBuilder
    private func section(title: String, active: Bool) -> some View {
        let items = templates.filter { $0.isActive == active }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { template in
                    Button {
                        editing = template
                    } label: {
                        row(template)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = template
                        }
                    }
                }
            }
        }
    }

    private func row(_ template: RecurringTemplate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                Text("\(frequencyText(template)) · next \(template.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(
                minor: template.kind == .expense ? -template.amountMinor : template.amountMinor,
                kind: template.kind
            )
            Toggle("", isOn: Binding(
                get: { template.isActive },
                set: { template.isActive = $0; try? context.save() }
            ))
            .labelsHidden()
        }
    }

    private func frequencyText(_ template: RecurringTemplate) -> String {
        let unit: String = switch template.frequency {
        case .weekly: template.interval == 1 ? "Weekly" : "Every \(template.interval) weeks"
        case .monthly: template.interval == 1 ? "Monthly" : "Every \(template.interval) months"
        case .yearly: template.interval == 1 ? "Yearly" : "Every \(template.interval) years"
        }
        return unit
    }
}
