import SwiftUI
import SwiftData

struct ExportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var scope: CSVExporter.Scope = .transactions
    @State private var format: CSVExporter.Format = .finnishExcel
    @State private var allTime = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var rowCount = 0
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("What") {
                Picker("Scope", selection: $scope) {
                    Text("Transactions").tag(CSVExporter.Scope.transactions)
                    Text("Line items").tag(CSVExporter.Scope.lineItems)
                }
                Picker("Format", selection: $format) {
                    Text("Regional Excel (;)").tag(CSVExporter.Format.finnishExcel)
                    Text("Standard CSV (,)").tag(CSVExporter.Format.rfc4180)
                }
            }

            Section("Date range") {
                Toggle("All time", isOn: $allTime)
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .disabled(allTime)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .disabled(allTime)
            }

            Section {
                Button("Export") { export() }
                    .disabled(rowCount == 0)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(exportURL.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }
            } footer: {
                Text(previewText)
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshCount() }
        .onChange(of: scope) { _, _ in invalidate() }
        .onChange(of: format) { _, _ in invalidate() }
        .onChange(of: allTime) { _, _ in invalidate() }
        .onChange(of: startDate) { _, _ in invalidate() }
        .onChange(of: endDate) { _, _ in invalidate() }
        .alert("Export failed", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var previewText: String {
        let noun = scope == .transactions ? "transaction" : "line item"
        return "\(rowCount) \(noun) row\(rowCount == 1 ? "" : "s") will be exported."
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    // Predicate stays on Transaction's own `date` field; line items are joined in memory.
    private func rangeDescriptor() -> FetchDescriptor<Transaction> {
        var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        if !allTime {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
            descriptor.predicate = #Predicate<Transaction> { $0.date >= start && $0.date < end }
        }
        return descriptor
    }

    private func invalidate() {
        // Any input change makes a previously generated file stale.
        exportURL = nil
        refreshCount()
    }

    private func refreshCount() {
        do {
            let transactions = try modelContext.fetch(rangeDescriptor())
            rowCount = scope == .transactions
                ? transactions.count
                : transactions.reduce(0) { $0 + ($1.lineItems?.count ?? 0) }
        } catch {
            rowCount = 0
        }
    }

    private func export() {
        do {
            let transactions = try modelContext.fetch(rangeDescriptor())
            exportURL = try CSVExporter.export(transactions: transactions, scope: scope, format: format)
        } catch {
            errorMessage = (error as? UserPresentable)?.userMessage ?? "Export failed. Try again."
        }
    }
}
