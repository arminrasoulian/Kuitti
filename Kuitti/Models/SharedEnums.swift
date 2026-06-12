import Foundation

enum AccountType: String, Codable, CaseIterable {
    case bank, cash, credit
}

enum CategoryKind: String, Codable, CaseIterable {
    case expense, income
}

enum TransactionKind: String, Codable, CaseIterable {
    case expense, income
}

enum TransactionSource: String, Codable, CaseIterable {
    case manual, receiptScan, recurring
}

enum PaymentMethod: String, Codable, CaseIterable {
    case card, cash, mobilePay, bankTransfer, other, unknown
}

enum UnitKind: String, Codable, CaseIterable {
    case piece, kilogram, litre, other
}

enum AliasSource: String, Codable, CaseIterable {
    case user, gemini, fuzzyAuto
}

enum RecurrenceFrequency: String, Codable, CaseIterable {
    case weekly, monthly, yearly
}
