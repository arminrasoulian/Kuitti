import Foundation
import SwiftData

@Model
final class Category {
    var uuid: UUID = UUID()
    var name: String = ""
    var iconName: String = "tag.fill"
    var colorHex: String = "#999999"
    var kindRaw: String = CategoryKind.expense.rawValue
    var monthlyBudgetMinor: Int?
    var sortOrder: Int = 0
    var isUserCreated: Bool = true
    var seedIdentifier: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \LineItem.category)
    var lineItems: [LineItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTemplate.category)
    var recurringTemplates: [RecurringTemplate]? = []

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, kind: CategoryKind = .expense, iconName: String = "tag.fill", colorHex: String = "#999999") {
        self.name = name
        self.kindRaw = kind.rawValue
        self.iconName = iconName
        self.colorHex = colorHex
    }
}
