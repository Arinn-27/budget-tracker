import Foundation
import AppIntents
import SwiftUI

// MARK: - 1. Dynamic Category Picker (Loads Categories from the App)
struct ShortcutCategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var defaultQuery = ShortcutCategoryQuery()
    
    var id: String
    var name: String
    var isIncome: Bool
    var iconName: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: isIncome ? "Income Category" : "Expense Category",
            image: .init(systemName: iconName)
        )
    }
}

struct ShortcutCategoryQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ShortcutCategoryEntity] {
        let all = try await suggestedEntities()
        let lowerIDs = Set(identifiers.map { $0.lowercased() })
        var matched = all.filter { lowerIDs.contains($0.id.lowercased()) || lowerIDs.contains($0.name.lowercased()) }
        
        for rawID in identifiers {
            let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !matched.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                let style = CategoryStyle.style(for: trimmed)
                matched.append(
                    ShortcutCategoryEntity(
                        id: trimmed,
                        name: trimmed,
                        isIncome: style.isIncome,
                        iconName: style.icon
                    )
                )
            }
        }
        return matched
    }
    
    @MainActor
    func entities(matching string: String) async throws -> [ShortcutCategoryEntity] {
        let all = try await suggestedEntities()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    
    @MainActor
    func suggestedEntities() async throws -> [ShortcutCategoryEntity] {
        let db = DatabaseManager.shared
        let dbCategories = db.categories.filter { !$0.name.lowercased().contains("transfer") }
        if !dbCategories.isEmpty {
            return dbCategories.map { cat in
                let style = CategoryStyle.style(for: cat.name)
                return ShortcutCategoryEntity(
                    id: cat.name,
                    name: cat.name,
                    isIncome: style.isIncome,
                    iconName: style.icon
                )
            }
        }
        return WidgetExpenseShortcut.defaultCatalog.map { item in
            ShortcutCategoryEntity(
                id: item.name,
                name: item.name,
                isIncome: false,
                iconName: item.iconName
            )
        }
    }
}

// MARK: - 2. Dynamic Account Picker (Loads Linked Accounts & Cards from the App)
struct ShortcutAccountEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static var defaultQuery = ShortcutAccountQuery()
    
    var id: String
    var name: String
    var institution: String
    var typeLabel: String
    var iconName: String
    
    var displayRepresentation: DisplayRepresentation {
        let subtitleText = institution.isEmpty ? typeLabel : "\(institution) • \(typeLabel)"
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitleText)",
            image: .init(systemName: iconName)
        )
    }
}

struct ShortcutAccountQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ShortcutAccountEntity] {
        let all = try await suggestedEntities()
        return all.filter { acc in
            identifiers.contains(where: {
                $0.caseInsensitiveCompare(acc.id) == .orderedSame ||
                $0.caseInsensitiveCompare(acc.name) == .orderedSame ||
                acc.name.localizedCaseInsensitiveContains($0)
            })
        }
    }
    
    @MainActor
    func entities(matching string: String) async throws -> [ShortcutAccountEntity] {
        let all = try await suggestedEntities()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.institution.localizedCaseInsensitiveContains(query)
        }
    }
    
    @MainActor
    func suggestedEntities() async throws -> [ShortcutAccountEntity] {
        let db = DatabaseManager.shared
        var list = db.accounts.map { acc in
            ShortcutAccountEntity(
                id: acc.id,
                name: db.accountBreadcrumb(for: acc.id),
                institution: acc.institution,
                typeLabel: acc.type.rawValue,
                iconName: acc.iconName
            )
        }
        if list.isEmpty {
            list.append(
                ShortcutAccountEntity(
                    id: "default_primary",
                    name: "Primary Account",
                    institution: "BudgetTracker",
                    typeLabel: "Default",
                    iconName: "creditcard.fill"
                )
            )
        }
        return list
    }
}

// MARK: - 3. Dynamic Merchant Options Provider (Loads Saved & Recent Merchants from the App)
struct ShortcutMerchantOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        let db = DatabaseManager.shared
        var merchants: [String] = []
        
        // 1. All saved merchants / sub-categories across categories in the app
        for m in db.allKnownMerchants(for: nil) {
            let clean = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty, !merchants.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                merchants.append(clean)
            }
        }
        
        // 2. Any additional merchants from logged transactions in the app
        for tx in db.transactions {
            let clean = tx.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty,
               tx.source != "transfer",
               !merchants.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                merchants.append(clean)
            }
        }
        
        // 3. Fallback defaults if database is empty
        if merchants.isEmpty {
            merchants = ["Costco", "Walmart", "Whole Foods", "Starbucks", "Tim Hortons", "Uber", "Amazon", "Shell"]
        }
        return merchants
    }
}

// MARK: - 4. Dynamic Note Options Provider (Loads Recent Notes from the App + Quick Note Options)
struct ShortcutNoteOptionsProvider: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        let db = DatabaseManager.shared
        var notesList: [String] = ["None"]
        
        // Pull recent distinct notes entered in the app
        for tx in db.transactions {
            if let rawNote = tx.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawNote.isEmpty,
               !notesList.contains(where: { $0.caseInsensitiveCompare(rawNote) == .orderedSame }) {
                notesList.append(rawNote)
            }
            if notesList.count >= 25 { break }
        }
        
        return notesList
    }
}

// MARK: - 5. Transaction Type & Recurring Enums
enum ShortcutTransactionTypeOption: String, AppEnum {
    case expense = "Expense"
    case income = "Income"
    case refund = "Refund"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction Type"
    
    static var caseDisplayRepresentations: [ShortcutTransactionTypeOption: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "Expense", image: .init(systemName: "arrow.up.right.circle.fill")),
        .income: DisplayRepresentation(title: "Income", image: .init(systemName: "arrow.down.left.circle.fill")),
        .refund: DisplayRepresentation(title: "Refund", image: .init(systemName: "arrow.uturn.backward.circle.fill"))
    ]
}

enum ShortcutRecurringOption: String, AppEnum {
    case oneTime = "One-Time"
    case daily = "Daily"
    case weekly = "Weekly"
    case biWeekly = "Bi-Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recurring Frequency"
    
    static var caseDisplayRepresentations: [ShortcutRecurringOption: DisplayRepresentation] = [
        .oneTime: DisplayRepresentation(title: "One-Time (Not Recurring)", image: .init(systemName: "1.circle")),
        .daily: DisplayRepresentation(title: "Daily", image: .init(systemName: "repeat")),
        .weekly: DisplayRepresentation(title: "Weekly", image: .init(systemName: "repeat")),
        .biWeekly: DisplayRepresentation(title: "Bi-Weekly", image: .init(systemName: "repeat")),
        .monthly: DisplayRepresentation(title: "Monthly", image: .init(systemName: "repeat.circle.fill")),
        .yearly: DisplayRepresentation(title: "Yearly", image: .init(systemName: "calendar.badge.clock"))
    ]
}

// MARK: - 6. Form-Style "Log Transaction" Shortcut Action
struct LogTransactionShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Transaction"
    static var description = IntentDescription(
        "A form-style Shortcut that asks for Date, Amount, Category, Account, Tag, and Note—with dropdown options populated directly from your BudgetTracker app.",
        categoryName: "Transactions"
    )
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Category", description: "Choose from your categories in the app")
    var category: ShortcutCategoryEntity?
    
    @Parameter(title: "Date", description: "Choose the transaction date")
    var date: Date?
    
    @Parameter(title: "Amount", description: "Enter the dollar amount", controlStyle: .field)
    var amount: Double?
    
    @Parameter(title: "Account", description: "Choose from your accounts & cards in the app")
    var account: ShortcutAccountEntity?
    
    @Parameter(
        title: "Tag",
        description: "Choose from tags in your app or type a new one",
        optionsProvider: ShortcutMerchantOptionsProvider()
    )
    var merchant: String?
    
    @Parameter(
        title: "Note",
        description: "Choose from recent notes in your app or type a new note",
        optionsProvider: ShortcutNoteOptionsProvider()
    )
    var notes: String?
    
    @Parameter(title: "Type", default: .expense)
    var transactionType: ShortcutTransactionTypeOption
    
    @Parameter(title: "Recurring", default: .oneTime)
    var recurring: ShortcutRecurringOption
    
    // Placing the fields inside the trailing block of Summary renders them as a vertical Form of labeled rows in the Shortcuts app!
    static var parameterSummary: some ParameterSummary {
        Summary("Transaction Form (\(\.$category))") {
            \.$date
            \.$amount
            \.$account
            \.$merchant
            \.$notes
            \.$transactionType
            \.$recurring
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let db = DatabaseManager.shared
        
        // 1. Category (Choose from categories in the app)
        let resolvedCategoryEntity: ShortcutCategoryEntity
        if let c = category {
            resolvedCategoryEntity = c
        } else {
            let appCategories = try await ShortcutCategoryQuery().suggestedEntities()
            resolvedCategoryEntity = try await $category.requestDisambiguation(
                among: appCategories,
                dialog: "Choose a Category:"
            )
        }
        let categoryName = resolvedCategoryEntity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. Date (Ask for date if not provided)
        let resolvedDate: Date
        if let d = date {
            resolvedDate = d
        } else {
            resolvedDate = (try? await $date.requestValue("Choose the Transaction Date:")) ?? Date()
        }
        
        // 3. Amount (Ask for amount if not provided)
        let cleanAmount: Double
        if let a = amount, abs(a) > 0 {
            cleanAmount = abs(a)
        } else {
            let entered = try await $amount.requestValue("Enter the Transaction Amount:")
            guard abs(entered) > 0 else {
                throw $amount.needsValueError("Please enter an amount greater than 0.")
            }
            cleanAmount = abs(entered)
        }
        
        // 4. Account (Choose from accounts in the app)
        let resolvedAccountEntity: ShortcutAccountEntity?
        if let acc = account {
            resolvedAccountEntity = acc
        } else {
            let appAccounts = try await ShortcutAccountQuery().suggestedEntities()
            if appAccounts.count > 1 {
                resolvedAccountEntity = try? await $account.requestDisambiguation(
                    among: appAccounts,
                    dialog: "Choose the Account / Card:"
                )
            } else {
                resolvedAccountEntity = appAccounts.first
            }
        }
        
        let resolvedAccountID: String? = {
            if let pickedAccount = resolvedAccountEntity, pickedAccount.id != "default_primary" {
                if let exact = db.accounts.first(where: { $0.id == pickedAccount.id }) {
                    return exact.id
                }
                if let byName = db.accounts.first(where: {
                    $0.name.localizedCaseInsensitiveContains(pickedAccount.name) ||
                    db.accountBreadcrumb(for: $0.id).localizedCaseInsensitiveContains(pickedAccount.name)
                }) {
                    return byName.id
                }
            }
            return db.accounts.first?.id
        }()
        
        // 5. Tag / Merchant (Choose from tags in the app for this category, or type custom)
        let trimmedMerchant: String
        if let m = merchant?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            trimmedMerchant = m
        } else {
            var categoryMerchants = db.allKnownMerchants(for: categoryName)
            if categoryMerchants.isEmpty {
                categoryMerchants = Category.suggestedMerchants(for: categoryName)
            }
            var options = categoryMerchants
            let customOption = "Other (Type Custom Tag)..."
            if !options.contains(customOption) {
                options.append(customOption)
            }
            let selectedMerch = (try? await $merchant.requestDisambiguation(
                among: options,
                dialog: "Choose a Tag for \(categoryName):"
            )) ?? ""
            if selectedMerch == customOption {
                let typed = (try? await $merchant.requestValue("Type the Tag Name:")) ?? ""
                trimmedMerchant = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                trimmedMerchant = selectedMerch.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let resolvedMerchant = trimmedMerchant.isEmpty ? categoryName : trimmedMerchant
        
        // 6. Note (Choose from recent notes in the app or type custom)
        let resolvedNotes: String?
        if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            resolvedNotes = (n.caseInsensitiveCompare("None") == .orderedSame) ? nil : n
        } else {
            let typedNote = (try? await $notes.requestValue("Add a Note (or type 'None' to skip):"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if typedNote.isEmpty || typedNote.caseInsensitiveCompare("None") == .orderedSame {
                resolvedNotes = nil
            } else {
                resolvedNotes = typedNote
            }
        }
        
        // Ensure Category & Merchant are persisted in SQLite
        var targetCat = db.categories.first(where: { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame })
        if targetCat == nil {
            db.addCategory(name: categoryName)
            targetCat = db.categories.first(where: { $0.name.caseInsensitiveCompare(categoryName) == .orderedSame })
        }
        
        if !trimmedMerchant.isEmpty {
            db.addSubCategory(name: trimmedMerchant, for: categoryName)
        }
        
        let signedAmount: Double = (transactionType == .refund) ? -cleanAmount : cleanAmount
        let txSource: String = (transactionType == .refund) ? "refund" : "shortcut"
        let isRecurringTx = recurring != .oneTime
        let recurringFreqRaw: String? = isRecurringTx ? recurring.rawValue : nil
        
        db.addTransaction(
            date: resolvedDate,
            amount: signedAmount,
            categoryID: targetCat?.id,
            merchant: resolvedMerchant,
            subCategory: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            notes: resolvedNotes,
            source: txSource,
            accountID: resolvedAccountID,
            isRecurring: isRecurringTx,
            recurringFrequency: recurringFreqRaw
        )
        
        let currency = UserDefaults.standard.string(forKey: "selectedCurrencySymbol") ?? "$"
        let formattedAmt = String(format: "%@%.2f", currency, cleanAmount)
        let merchantSuffix = trimmedMerchant.isEmpty ? "" : " at \(trimmedMerchant)"
        
        return .result(
            value: cleanAmount,
            dialog: "Logged \(transactionType.rawValue.lowercased()) of \(formattedAmt) in \(categoryName)\(merchantSuffix)."
        )
    }
}

// MARK: - 7. AppShortcutsProvider
struct BudgetTrackerShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue
    
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTransactionShortcutIntent(),
            phrases: [
                "Log a transaction in \(.applicationName)",
                "Log an expense in \(.applicationName)"
            ],
            shortTitle: "Log Transaction Form",
            systemImageName: "list.bullet.clipboard.fill"
        )
    }
}
