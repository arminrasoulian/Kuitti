import Foundation

/// Default format is Finnish-Excel-friendly: ';' delimiter, comma decimals, UTF-8 BOM
/// (a ','/dot RFC-4180 file imports as one garbage column on a fi-locale machine).
struct CSVExporter {
    enum Format {
        case finnishExcel
        case rfc4180

        var delimiter: String {
            switch self {
            case .finnishExcel: ";"
            case .rfc4180: ","
            }
        }

        func money(_ minor: Int) -> String {
            let plain = Money.plainDecimalString(minor)
            switch self {
            case .finnishExcel: return plain.replacingOccurrences(of: ".", with: ",")
            case .rfc4180: return plain
            }
        }

        func number(_ value: Double) -> String {
            let plain = String(format: "%.3f", value)
            switch self {
            case .finnishExcel: return plain.replacingOccurrences(of: ".", with: ",")
            case .rfc4180: return plain
            }
        }
    }

    enum Scope: String {
        case transactions
        case lineItems
    }

    static func export(transactions: [Transaction], scope: Scope, format: Format) throws -> URL {
        let content: String = switch scope {
        case .transactions: transactionsCSV(transactions, format: format)
        case .lineItems: lineItemsCSV(transactions, format: format)
        }
        let filename = "kuitti-\(scope.rawValue)-\(Date().formatted(.iso8601.year().month().day())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        // BOM so Excel detects UTF-8 (ä/ö in product names otherwise mojibake).
        guard let data = ("\u{FEFF}" + content).data(using: .utf8) else { throw ExportError.writeFailed }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed
        }
        return url
    }

    static func transactionsCSV(_ transactions: [Transaction], format: Format) -> String {
        var rows = [row(["Date", "Type", "Amount (EUR)", "Payee", "Account", "Category", "Payment method", "Source", "Notes", "Warnings"], format: format)]
        for transaction in transactions.sorted(by: { $0.date < $1.date }) {
            rows.append(row([
                transaction.date.formatted(.iso8601.year().month().day()),
                transaction.kindRaw,
                format.money(transaction.signedAmountMinor),
                transaction.payee,
                transaction.account?.name ?? "",
                transaction.category?.name ?? "",
                transaction.paymentMethodRaw,
                transaction.sourceRaw,
                transaction.notes,
                transaction.importWarnings.joined(separator: " | "),
            ], format: format))
        }
        return rows.joined(separator: "\r\n")
    }

    static func lineItemsCSV(_ transactions: [Transaction], format: Format) -> String {
        var rows = [row(["Date", "Store", "Product", "Raw name", "Quantity", "Unit", "Unit price (EUR)", "Line total (EUR)", "Category", "Uncertain", "Discount/deposit"], format: format)]
        let items = transactions
            .flatMap { $0.lineItems ?? [] }
            .sorted { ($0.purchaseDate, $0.sortOrder) < ($1.purchaseDate, $1.sortOrder) }
        for item in items {
            rows.append(row([
                item.purchaseDate.formatted(.iso8601.year().month().day()),
                item.transaction?.store?.name ?? item.transaction?.payee ?? "",
                item.displayName,
                item.rawName,
                format.number(item.quantity),
                item.unitRaw,
                format.number(item.unitPrice),
                format.money(item.lineTotalMinor),
                item.category?.name ?? "",
                item.quantityIsUncertain ? "yes" : "",
                item.isDiscountOrDeposit ? "yes" : "",
            ], format: format))
        }
        return rows.joined(separator: "\r\n")
    }

    static func row(_ fields: [String], format: Format) -> String {
        fields.map { escape($0, delimiter: format.delimiter) }.joined(separator: format.delimiter)
    }

    static func escape(_ field: String, delimiter: String) -> String {
        if field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
