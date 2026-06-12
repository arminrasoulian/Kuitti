import Foundation
import SwiftData

@Model
final class Account {
    var uuid: UUID = UUID()
    var name: String = ""
    var typeRaw: String = AccountType.bank.rawValue
    // Current balance is always computed (initialBalanceMinor + signed transaction sums);
    // a stored balance would drift the moment any historical transaction is edited.
    var initialBalanceMinor: Int = 0
    var iconName: String = "creditcard.fill"
    var colorHex: String = "#4A90D9"
    var isDefault: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var seedIdentifier: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTemplate.account)
    var recurringTemplates: [RecurringTemplate]? = []

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .bank }
        set { typeRaw = newValue.rawValue }
    }

    init(name: String, type: AccountType = .bank, initialBalanceMinor: Int = 0) {
        self.name = name
        self.typeRaw = type.rawValue
        self.initialBalanceMinor = initialBalanceMinor
    }
}
