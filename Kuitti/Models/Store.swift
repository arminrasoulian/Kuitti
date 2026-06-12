import Foundation
import SwiftData

/// Chain-level store ("Lidl", "K-Market") — "is this banana price good?" is a chain
/// question, not a branch question. A branchName can be added additively later.
@Model
final class Store {
    var uuid: UUID = UUID()
    var name: String = ""
    var normalizedKey: String = ""
    var iconName: String = "cart.fill"
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Transaction.store)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \ProductAlias.store)
    var aliases: [ProductAlias]? = []

    init(name: String, normalizedKey: String) {
        self.name = name
        self.normalizedKey = normalizedKey
    }
}
