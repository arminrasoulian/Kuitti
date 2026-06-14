import Foundation
import SwiftData
import Testing
@testable import Kuitti

/// Full backup round-trip: export → encode → decode → restore into a fresh store, asserting
/// the graph, binary data, value blobs, and preferences come back, and that restore is
/// replace-all (it wipes whatever was there first).
@MainActor
struct BackupServiceTests {
    @Test func roundTripRebuildsGraphAndPreferences() throws {
        let defaults = UserDefaults.standard
        // Snapshot the (global) prefs this test mutates, restore them afterwards.
        let snapAppearance = defaults.string(forKey: "appearancePreference")
        let snapOnboarded = defaults.bool(forKey: "hasOnboarded")
        let snapLock = AppLockController.isEnabled
        let snapTombstones = defaults.stringArray(forKey: "dismissedSeedIdentifiers")
        let snapAIProvider = defaults.string(forKey: AISettings.providerKey)
        let snapAIModel = defaults.string(forKey: AISettings.modelKey)
        defer {
            if let v = snapAppearance { defaults.set(v, forKey: "appearancePreference") } else { defaults.removeObject(forKey: "appearancePreference") }
            defaults.set(snapOnboarded, forKey: "hasOnboarded")
            AppLockController.isEnabled = snapLock
            if let v = snapTombstones { defaults.set(v, forKey: "dismissedSeedIdentifiers") } else { defaults.removeObject(forKey: "dismissedSeedIdentifiers") }
            if let v = snapAIProvider { defaults.set(v, forKey: AISettings.providerKey) } else { defaults.removeObject(forKey: AISettings.providerKey) }
            if let v = snapAIModel { defaults.set(v, forKey: AISettings.modelKey) } else { defaults.removeObject(forKey: AISettings.modelKey) }
        }

        // Build a representative graph in an empty source store.
        let source = try makeContext(seeded: false)
        let account = Account(name: "Joint"); source.insert(account)
        let category = Kuitti.Category(name: "Groceries"); source.insert(category)
        let store = Store(name: "Lidl", normalizedKey: "lidl"); source.insert(store)
        let product = Product(canonicalName: "Banaani", normalizedKey: "banaani")
        product.translatedName = "Banana"; product.translatedNormalizedKey = "banana"; product.sourceLanguage = "fi"
        source.insert(product)
        let alias = ProductAlias(rawName: "BANAANI", normalizedRawName: "banaani", source: .user)
        alias.store = store; alias.product = product; source.insert(alias)
        let tx = Transaction(kind: .expense, date: Date(), amountMinor: 250, payee: "Lidl", source: .receiptScan)
        tx.account = account; tx.category = category; tx.store = store
        tx.vatLines = [VatLine(ratePercent: 14, baseMinor: 219, taxMinor: 31)]
        tx.importWarnings = ["check total"]
        source.insert(tx)
        let line = LineItem(rawName: "BANAANI", displayName: "Banaani", quantity: 1, unit: .kilogram, lineTotalMinor: 250)
        line.translatedName = "Banana"; line.transaction = tx; line.category = category; line.product = product
        source.insert(line)
        let image = ReceiptImage(imageData: Data([0xDE, 0xAD, 0xBE, 0xEF]), pageIndex: 0)
        image.transaction = tx; source.insert(image)
        let recurring = RecurringTemplate(name: "Netflix", kind: .expense, amountMinor: 1599, frequency: .monthly, nextDueDate: Date())
        recurring.account = account; recurring.category = category; source.insert(recurring)
        source.insert(DismissedDuplicatePair(productA: UUID(), productB: UUID()))
        try source.save()

        // Preferences to capture.
        defaults.set("dark", forKey: "appearancePreference")
        defaults.set(true, forKey: "hasOnboarded")
        AppLockController.isEnabled = true
        defaults.set(["seed.cat.x"], forKey: "dismissedSeedIdentifiers")
        AISettings.provider = .google
        AISettings.modelID = "gemini-2.5-pro-test"

        // Export → compressed file bytes → decode.
        let archive = try BackupService(context: source).export()
        let data = try BackupService.encode(archive)
        let decoded = try BackupService.decode(data)

        // Restore into a DIFFERENT store that already has data (proves replace-all).
        let dest = try makeContext(seeded: false)
        dest.insert(Account(name: "Stale"))
        try dest.save()
        defaults.set("light", forKey: "appearancePreference")   // changed; restore must overwrite
        AppLockController.isEnabled = false
        AISettings.modelID = "changed-model"                    // changed; restore must overwrite

        try BackupService(context: dest).restore(decoded)

        // Counts (the stale account is replaced, not added to).
        #expect(try dest.fetch(FetchDescriptor<Account>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<Kuitti.Category>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<Store>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<Product>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<ProductAlias>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<Transaction>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<LineItem>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<ReceiptImage>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<RecurringTemplate>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<DismissedDuplicatePair>()).count == 1)

        // The single surviving account is the restored one.
        #expect(try dest.fetch(FetchDescriptor<Account>()).first?.name == "Joint")

        // Relationships + values reconstructed by uuid.
        let rLine = try #require(try dest.fetch(FetchDescriptor<LineItem>()).first)
        #expect(rLine.product?.canonicalName == "Banaani")
        #expect(rLine.transaction?.payee == "Lidl")
        #expect(rLine.category?.name == "Groceries")
        #expect(rLine.translatedName == "Banana")

        let rTx = try #require(try dest.fetch(FetchDescriptor<Transaction>()).first)
        #expect(rTx.account?.name == "Joint")
        #expect(rTx.store?.name == "Lidl")
        #expect(rTx.vatLines.first?.taxMinor == 31)
        #expect(rTx.importWarnings == ["check total"])

        let rImage = try #require(try dest.fetch(FetchDescriptor<ReceiptImage>()).first)
        #expect(rImage.imageData == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(rImage.transaction?.uuid == rTx.uuid)

        let rAlias = try #require(try dest.fetch(FetchDescriptor<ProductAlias>()).first)
        #expect(rAlias.store?.name == "Lidl")
        #expect(rAlias.product?.canonicalName == "Banaani")

        // Preferences restored from the archive (overwriting the changed values).
        #expect(defaults.string(forKey: "appearancePreference") == "dark")
        #expect(AppLockController.isEnabled == true)
        #expect(defaults.stringArray(forKey: "dismissedSeedIdentifiers") == ["seed.cat.x"])
        #expect(defaults.string(forKey: AISettings.providerKey) == "google")
        #expect(defaults.string(forKey: AISettings.modelKey) == "gemini-2.5-pro-test")
    }

    /// Archives written before the model picker have no aiProvider/aiModel — they must still
    /// decode (the fields are optional), defending the no-formatVersion-bump choice.
    @Test func preferencesDecodeWithoutAIFields() throws {
        let json = """
        {
          "appearancePreference": "dark",
          "hasOnboarded": true,
          "appLockEnabled": false,
          "dismissedSeedIdentifiers": ["seed.cat.x"]
        }
        """
        let prefs = try JSONDecoder().decode(PreferencesDTO.self, from: Data(json.utf8))
        #expect(prefs.aiProvider == nil)
        #expect(prefs.aiModel == nil)
        #expect(prefs.appearancePreference == "dark")
    }
}
