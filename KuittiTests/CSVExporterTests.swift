import Foundation
import SwiftData
import Testing
@testable import Kuitti

struct CSVExporterTests {
    @Test func finnishExcelFormat() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let transaction = try editor.createManual(
            kind: .expense, date: Date(), amountMinor: 1234,
            payee: "Lidl; Kannelmäki", account: nil, category: nil,
            notes: "ä ö test", paymentMethod: .card
        )

        let csv = CSVExporter.transactionsCSV([transaction], format: .finnishExcel)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines.count == 2)
        // Comma decimals, semicolon delimiter, payee quoted because it contains ';'.
        #expect(lines[1].contains("-12,34"))
        #expect(lines[1].contains("\"Lidl; Kannelmäki\""))
        #expect(lines[1].contains("ä ö test"))
    }

    @Test func rfc4180Format() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let transaction = try editor.createManual(
            kind: .income, date: Date(), amountMinor: 250000,
            payee: "Employer", account: nil, category: nil,
            notes: "", paymentMethod: .bankTransfer
        )

        let csv = CSVExporter.transactionsCSV([transaction], format: .rfc4180)
        #expect(csv.contains("2500.00"))
        #expect(csv.components(separatedBy: "\r\n")[0].contains("Date,Type"))
    }

    @Test func quoteEscaping() {
        #expect(CSVExporter.escape("plain", delimiter: ";") == "plain")
        #expect(CSVExporter.escape("has \"quotes\"", delimiter: ";") == "\"has \"\"quotes\"\"\"")
        #expect(CSVExporter.escape("a;b", delimiter: ";") == "\"a;b\"")
    }

    @Test func exportWritesBOMFile() throws {
        let context = try makeContext()
        let editor = TransactionEditor(context: context)
        let transaction = try editor.createManual(
            kind: .expense, date: Date(), amountMinor: 500,
            payee: "Test", account: nil, category: nil, notes: "", paymentMethod: .card
        )
        let url = try CSVExporter.export(transactions: [transaction], scope: .transactions, format: .finnishExcel)
        let data = try Data(contentsOf: url)
        // UTF-8 BOM so Finnish Excel detects the encoding.
        #expect(data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        try? FileManager.default.removeItem(at: url)
    }
}
