import Foundation
import SwiftData

nonisolated struct SeedCategoryDef {
    let id: String
    let name: String
    let kind: CategoryKind
    let icon: String
    let color: String
    /// One-line semantic hint passed to Gemini so the model knows what the category means.
    let hint: String
}

nonisolated struct SeedAccountDef {
    let id: String
    let name: String
    let type: AccountType
    let isDefault: Bool
}

nonisolated enum SeedCatalog {
    static let categories: [SeedCategoryDef] = [
        // Expense
        .init(id: "seed.cat.groceries", name: "Ruokakauppa", kind: .expense, icon: "cart.fill", color: "#34A853",
              hint: "groceries, food and drink from supermarkets"),
        .init(id: "seed.cat.restaurants", name: "Ravintolat ja kahvilat", kind: .expense, icon: "fork.knife", color: "#FF9500",
              hint: "restaurants, cafes, takeaway, lunch"),
        .init(id: "seed.cat.housing", name: "Asuminen", kind: .expense, icon: "house.fill", color: "#5856D6",
              hint: "rent, vastike, mortgage, home insurance"),
        .init(id: "seed.cat.utilities", name: "Sähkö ja vesi", kind: .expense, icon: "bolt.fill", color: "#FFCC00",
              hint: "electricity, water, heating, internet, phone plans"),
        .init(id: "seed.cat.transport", name: "Liikenne", kind: .expense, icon: "tram.fill", color: "#007AFF",
              hint: "public transport, HSL, taxis, train and bus tickets"),
        .init(id: "seed.cat.car", name: "Auto ja polttoaine", kind: .expense, icon: "fuelpump.fill", color: "#64D2FF",
              hint: "fuel, parking, car maintenance, car wash"),
        .init(id: "seed.cat.health", name: "Terveys ja apteekki", kind: .expense, icon: "cross.case.fill", color: "#FF3B30",
              hint: "pharmacy, medicine, doctor, dentist, vitamins"),
        .init(id: "seed.cat.clothing", name: "Vaatteet", kind: .expense, icon: "tshirt.fill", color: "#AF52DE",
              hint: "clothing, shoes, accessories"),
        .init(id: "seed.cat.kids", name: "Lapset", kind: .expense, icon: "figure.and.child.holdinghands", color: "#FF2D55",
              hint: "children's items, toys, daycare, baby products, diapers"),
        .init(id: "seed.cat.pets", name: "Lemmikit", kind: .expense, icon: "pawprint.fill", color: "#C7843D",
              hint: "pet food, vet, pet supplies"),
        .init(id: "seed.cat.hobbies", name: "Harrastukset ja urheilu", kind: .expense, icon: "figure.run", color: "#30B0C7",
              hint: "sports, gym, hobby gear and fees"),
        .init(id: "seed.cat.entertainment", name: "Viihde ja tilaukset", kind: .expense, icon: "tv.fill", color: "#5AC8FA",
              hint: "streaming subscriptions, games, movies, events, books"),
        .init(id: "seed.cat.household", name: "Kodin tarvikkeet", kind: .expense, icon: "lamp.table.fill", color: "#A2845E",
              hint: "household goods, cleaning supplies, kitchenware, tools, furniture"),
        .init(id: "seed.cat.gifts", name: "Lahjat ja juhlat", kind: .expense, icon: "gift.fill", color: "#BF5AF2",
              hint: "gifts, celebrations, parties"),
        .init(id: "seed.cat.other", name: "Muut menot", kind: .expense, icon: "ellipsis.circle.fill", color: "#8E8E93",
              hint: "anything that fits no other category"),
        // Income
        .init(id: "seed.cat.salary", name: "Palkka", kind: .income, icon: "banknote.fill", color: "#34C759",
              hint: "salary and wages"),
        .init(id: "seed.cat.benefits", name: "Etuudet (Kela)", kind: .income, icon: "building.columns.fill", color: "#32ADE6",
              hint: "Kela benefits and allowances"),
        .init(id: "seed.cat.otherIncome", name: "Muut tulot", kind: .income, icon: "plus.circle.fill", color: "#98989D",
              hint: "other income, refunds, sales"),
    ]

    static let accounts: [SeedAccountDef] = [
        .init(id: "seed.acct.joint", name: "Yhteinen tili", type: .bank, isDefault: true),
        .init(id: "seed.acct.cash", name: "Käteinen", type: .cash, isDefault: false),
    ]

    /// The undeletable fallback category name, used by Gemini decode fallback and category deletion.
    static let fallbackCategoryName = "Muut menot"
    static let fallbackCategorySeedID = "seed.cat.other"
}

/// Insert-if-absent seeding, run on every launch (cheap). User renames/recolors survive;
/// user deletions of seeded rows are recorded as tombstones so they are never resurrected.
struct SeedDataService {
    private static let tombstoneKey = "dismissedSeedIdentifiers"

    static func seedIfNeeded(context: ModelContext) throws {
        let tombstones = Set(UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? [])

        let existingCategoryIDs = Set(
            try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.seedIdentifier != nil }))
                .compactMap(\.seedIdentifier)
        )
        for (index, def) in SeedCatalog.categories.enumerated()
        where !existingCategoryIDs.contains(def.id) && !tombstones.contains(def.id) {
            let category = Category(name: def.name, kind: def.kind, iconName: def.icon, colorHex: def.color)
            category.isUserCreated = false
            category.seedIdentifier = def.id
            category.sortOrder = index
            context.insert(category)
        }

        let existingAccountIDs = Set(
            try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.seedIdentifier != nil }))
                .compactMap(\.seedIdentifier)
        )
        for (index, def) in SeedCatalog.accounts.enumerated()
        where !existingAccountIDs.contains(def.id) && !tombstones.contains(def.id) {
            let account = Account(name: def.name, type: def.type)
            account.isDefault = def.isDefault
            account.seedIdentifier = def.id
            account.sortOrder = index
            context.insert(account)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    /// Call when the user deletes a seeded row so seeding never resurrects it.
    static func recordDismissed(seedIdentifier: String) {
        var tombstones = Set(UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? [])
        tombstones.insert(seedIdentifier)
        UserDefaults.standard.set(Array(tombstones), forKey: tombstoneKey)
    }
}
