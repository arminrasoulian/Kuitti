# Kuitti

**Kuitti** is a private, offline-first personal-finance app for iPhone. Photograph a receipt and an AI turns it into a fully itemized transaction; over time Kuitti builds a cross-store **price history for every product** you buy. All data lives on your device — there is no backend, no account, and nothing to sign up for.

> *Kuitti* is Finnish for "receipt." Finnish receipts are the most common case, but Kuitti reads receipts in any European language and shows product names translated into the app's language.

- **Platform:** iOS 17+, SwiftUI, SwiftData, Swift Charts. **Zero third-party packages.**
- **AI:** Google **Gemini 2.5 Flash** for receipt parsing and product identification, using *your own* API key (stored only in the iOS Keychain).
- **Privacy:** offline-first. The only network calls are the receipt/product parse to Gemini and barcode lookups to Open Food Facts. Money never leaves the device.

---

## Features

### 📷 Receipt scanning & AI parsing
- **Document camera** (VisionKit) with automatic edge detection, perspective crop, deskew, and **multi-page** capture for long receipts.
- Each page is downscaled and sent to **Gemini**, which returns structured data: store, date/time, payment method, line items (raw + cleaned name, quantity, unit, unit price, line total), VAT breakdown, subtotal, total, and confidence/warnings.
- Robust ingestion: money is parsed from decimal strings into **integer cents** (never `Double`), comma/period decimal separators are normalized, grams convert to kilograms, and per-line arithmetic is sanity-checked.

### 📥 Getting receipts in — four ways
1. **Scan** with the camera.
2. **Choose from Library** — pick a photo, or a file (image **or PDF**) from the Files app. PDFs are rendered to page images.
3. **Share into Kuitti** — from another app (e.g. a store or bank app), use the share sheet's **"Copy to Kuitti"** for an image or PDF; Kuitti asks you to confirm, then imports it.
4. **Add manually** — create a transaction by hand, with optional line items.

### ✅ Review & correct
- The **Review screen** is the correction point: edit the store, date, payment method, and account; edit each line's name, quantity, unit, price, and category; see confidence chips and uncertainty badges; add or delete lines.
- A live **Σ(line items) = total** check shows a non-blocking warning when a receipt doesn't add up (with a cash-rounding tolerance). Saving never gets blocked — warnings are stored on the transaction.

### 🧺 Products & price history
- Saving a receipt automatically maintains **canonical products** so the *same* real-world product is recognized across stores and spellings. Resolution order: exact alias → local fuzzy match → AI proposal; saving "teaches" Kuitti by minting/repointing **aliases** so the next receipt resolves instantly with no AI.
- **Multilingual product names:** each product keeps its **original-language name** plus an **app-language translation** (shown when they differ). Matching is size-aware and bridges languages (e.g. *Banaani* ↔ *Banana*).
- **Product detail** shows purchase count, last price/store, a price-direction indicator, and a **Swift Charts unit-price timeline** colored by store. You can rename a product.

### 🔁 Duplicate detection & merge
- A background scan proposes products that look like the same thing (same barcode, near-identical or cross-language names), while **never** suggesting different sizes (1 L vs 2 L) as duplicates.
- Suggestions surface unobtrusively: a **badge** on the Products tab, a **banner**, a Settings entry, and a gentle **post-scan nudge**.
- **Review duplicates** screen + a **merge preview** (pick which to keep, see the combined purchase count) consolidates all purchase history under the survivor. "Keep separate" is remembered so a rejected pair never reappears.

### 🏷️ Barcode lookup
- Live **EAN-8/13** scanning. First scan: local `ean` lookup → **Open Food Facts** lookup → fuzzy-match to your existing products → confirming **stamps the barcode** onto the product so every future scan resolves locally and instantly.
- OFF miss (common for store brands) is a first-class flow: name it yourself or **photograph the package** for Gemini to identify.

### 💸 Transactions
- **List:** day-grouped, reverse-chronological, with search and a filter sheet (date range, category, store, account, amount, type, keyword).
- **Detail:** read-only view of store, date, account, payment method, notes, receipt thumbnails, VAT rows, and itemized line items with categories.
- **Edit / Manual add:** amount, account, category, date, payee, notes, payment method, and editable line items. Editing a saved line item can re-link it to the right product and learn the alias.

### 📊 Dashboard & insights
- Month income / expense / net, a **category donut**, a 6-month **trend chart**, month-over-month delta, and **budget progress** — with a month picker.

### 🎯 Budgets
- Optional monthly budget per category; the dashboard shows progress against the current calendar month.

### 🏦 Accounts
- Multiple accounts (bank / cash / credit) with **computed balances** (initial balance + signed transaction sums), default account, reordering, archiving, and a per-account filtered transaction list.

### 🗂️ Categories
- Predefined + custom categories with usage counts, SF Symbol icon and color, optional budget, and a safe delete (reassigns/nullifies rather than destroying history).

### ⏰ Recurring transactions
- Templates (rent, salary, subscriptions…) with frequency and interval. They **materialize automatically** on launch/foreground, catching up across missed periods, and become ordinary editable transactions.

### 📤 Export
- **CSV export** of transactions or detailed line items, with a **Finnish-Excel-friendly** default (`;`-delimited, comma decimals, UTF-8 BOM) and a standard RFC-4180 toggle. Shared via the system share sheet.

### 💾 Backup & restore
- **Create a full backup** (`.kuittibackup`, a compressed JSON archive of *everything except the API key*), manage backups in-app (date/size, share, delete), and **restore** — either an in-app backup or a file picked from Files.
- Restore is **replace-all** behind a clear confirmation; the Gemini API key is never touched.
- **Native iOS backup** works automatically: the data store lives in a backed-up location, so the app is included in iCloud/device backups (in-app archive copies are excluded to avoid doubling the backup size).

### 🔒 Privacy & security
- The **Gemini API key** lives only in the Keychain (device-only; never in the repo, the binary, or backups) and is entered in Settings.
- Optional **App Lock** with Face ID.
- **Appearance**: system / light / dark.

---

## Architecture & tech

- **SwiftUI + SwiftData + Swift Charts**, Swift 6 with **MainActor** default isolation (DTO/value types are `nonisolated` so their `Codable` works off the main actor).
- **Money is `Int` minor units (EUR cents)** everywhere authoritative; the two `Double` exceptions (quantity, unit price) are derived-only and never summed.
- **`TransactionEditor` is the single choke point** for all transaction/line-item mutations, keeping denormalized invariants (line-item dates, product stats, account balances) consistent.
- **CloudKit-ready schema** (every model has a `uuid`, every property optional/defaulted, no unique constraints, logical uniqueness via fetch-before-insert) — sync is deferred but the door is open.
- **Gemini** (`GeminiClient` + JSON-schema-constrained responses) and **Open Food Facts** (`OpenFoodFactsClient`) are the only external services.
- No third-party Swift packages; the Xcode project is generated by **XcodeGen** from `project.yml` and is not committed.

### Project layout
```
Kuitti/
  App/        App entry, root tab view, environment, model container
  Models/     SwiftData @Model types + SchemaV1
  DraftModels/ Value types for the receipt-import pipeline + Gemini DTOs
  Services/   Gemini, Open Food Facts, product matching/similarity, transaction editing,
              recurring, CSV export, backup, image processing, keychain, seeding
  Features/   One folder per screen area (Dashboard, Transactions, Products, ReceiptImport,
              Barcode, Accounts, Categories, Budgets, Recurring, Settings)
  Shared/     Formatters, components, helpers
  Resources/  Assets + Localizable.xcstrings
KuittiTests/  Unit tests
```

---

## Build & run

> `xcode-select` may point at the Command Line Tools on this machine, so prefix builds with `DEVELOPER_DIR` to use the full Xcode toolchain. The `.xcodeproj` is generated and git-ignored — regenerate it after pulling or changing `project.yml`.

```bash
brew install xcodegen

# from the repo root:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Kuitti.xcodeproj -scheme Kuitti \
  -destination "platform=iOS Simulator,name=iPhone 17" build
```

Open `Kuitti.xcodeproj` in Xcode to run on a simulator or device. (The document camera and barcode scanner need a real device; the simulator offers the photo-library fallback.)

### Tests
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Kuitti.xcodeproj -scheme Kuitti \
  -destination "platform=iOS Simulator,name=iPhone 17" test
```

### Configuration
1. Get a Google **Gemini API key**.
2. Run the app → **Settings → Gemini API key** → paste it. It's stored only in the Keychain. Receipt scanning is enabled once a key is set; barcode lookup and manual entry work without one.

---

## Maintaining this README

**When you add, remove, or change a user-facing feature, update this README in the same change** so the feature list stays accurate. This expectation is also recorded in `CLAUDE.md` for assisted edits.
