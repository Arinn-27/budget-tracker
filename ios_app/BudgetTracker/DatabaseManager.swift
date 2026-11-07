import Foundation
import SQLite3
import SwiftUI
import CryptoKit

public class DatabaseManager: ObservableObject {
    public static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let dbName = "budget_tracker.sqlite"
    
    @Published public var categories: [Category] = []
    @Published public var budgets: [Budget] = []
    @Published public private(set) var budgetsByCategoryID: [Int: Double] = [:]
    @Published public var transactions: [Transaction] = []
    @Published public var accounts: [Account] = []
    @Published public private(set) var accountsByID: [String: Account] = [:]
    @Published public var subCategoriesByCategory: [String: [String]] = [:]
    @Published public var recurringPayments: [RecurringPayment] = []
    @Published public var pendingQuickLogCategoryName: String? = nil
    @Published public var pendingOpenFullExpenseForm: Bool = false
    
    public func requestQuickLogCategory(named categoryName: String) {
        DispatchQueue.main.async {
            self.pendingQuickLogCategoryName = categoryName
        }
    }
    
    public func requestOpenFullExpenseForm() {
        DispatchQueue.main.async {
            self.pendingOpenFullExpenseForm = true
        }
    }
    
    public var totalMonthlyRecurringSpend: Double {
        recurringPayments.filter { $0.isActive }.reduce(0.0) { $0 + $1.normalizedMonthlyAmount }
    }
    
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private let currentSchemaVersion: Int32 = 4
    
    private func getUserVersion() -> Int32 {
        var stmt: OpaquePointer? = nil
        var version: Int32 = 0
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
        }
        sqlite3_finalize(stmt)
        return version
    }
    
    private func setUserVersion(_ version: Int32) {
        execute(sql: "PRAGMA user_version = \(version);")
    }
    
    private init() {
        openDatabase()
        createTables()
        if getUserVersion() < currentSchemaVersion {
            migrateIfNeeded()
            deduplicateLegacyCategories()
            purgeFakeSeedDataIfNeeded()
            setUserVersion(currentSchemaVersion)
        }
        purgeTransferCategoryRecords()
        ensureAccountRewardsSchema()
        ensureRecurringPaymentsSchema()
        seedCategories()
        seedSubCategoriesIfNeeded()
        refreshData()
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    private func openDatabase() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Could not locate Document Directory.")
            return
        }
        let dbPath = documentsURL.appendingPathComponent(dbName).path
        print("SQLite Database Path: \(dbPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error: Could not open database.")
        }
        
        // Enable Foreign Keys support
        execute(sql: "PRAGMA foreign_keys = ON;")
        // WAL gives crash-safe, concurrent-friendly writes
        execute(sql: "PRAGMA journal_mode = WAL;")
        execute(sql: "PRAGMA synchronous = NORMAL;")
    }
    
    private func execute(sql: String) {
        var err: UnsafeMutablePointer<Int8>? = nil
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let errMsg = err != nil ? String(cString: err!) : "Unknown error"
            print("SQLite execute error: \(errMsg) for statement: \(sql)")
            sqlite3_free(err)
        }
    }
    
    private func createTables() {
        execute(sql: """
            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS sub_categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_name TEXT NOT NULL,
                name TEXT NOT NULL,
                UNIQUE(category_name, name)
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS budgets (
                category_id INTEGER PRIMARY KEY,
                monthly_limit REAL NOT NULL,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS accounts (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                balance REAL NOT NULL,
                institution TEXT NOT NULL,
                icon_name TEXT NOT NULL,
                color_hex TEXT NOT NULL,
                parent_id TEXT,
                include_in_net_worth INTEGER DEFAULT 1,
                account_number TEXT,
                base_rate REAL DEFAULT 0.0,
                bonus_rate REAL DEFAULT 0.0,
                bonus_categories TEXT,
                bonus_tiers_json TEXT,
                FOREIGN KEY (parent_id) REFERENCES accounts(id) ON DELETE SET NULL
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS transactions (
                uuid TEXT PRIMARY KEY,
                date TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                merchant TEXT NOT NULL,
                source TEXT CHECK(source IN ('manual', 'csv', 'ai', 'transfer', 'refund')) NOT NULL,
                account_id TEXT,
                tx_hash TEXT,
                sub_category TEXT,
                notes TEXT,
                transfer_pair_id TEXT,
                refund_original_uuid TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS imported_statements (
                statement_hash TEXT PRIMARY KEY,
                institution TEXT,
                period_start TEXT,
                period_end TEXT,
                total_debits REAL,
                total_credits REAL,
                tx_count INTEGER,
                imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS recurring_payments (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                account_id TEXT,
                frequency TEXT NOT NULL,
                start_date TEXT NOT NULL,
                next_due_date TEXT NOT NULL,
                is_active INTEGER DEFAULT 1,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
            );
        """)
    }
    
    // MARK: - Schema Migration
    private func getTableColumns(tableName: String) -> [String] {
        var columns: [String] = []
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(tableName));", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 1) {
                    columns.append(String(cString: c))
                }
            }
        }
        sqlite3_finalize(stmt)
        return columns
    }

    private func migrateIfNeeded() {
        var tableSQL = ""
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type='table' AND name='transactions';", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            tableSQL = String(cString: c)
        }
        sqlite3_finalize(stmt)
        
        let hasAccountID = tableSQL.contains("account_id")
        let allowsAI = tableSQL.contains("'ai'")
        let allowsTransfer = tableSQL.contains("'transfer'")
        let allowsRefund = tableSQL.contains("'refund'")
        
        if !(hasAccountID && allowsAI && allowsTransfer && allowsRefund) {
            let existingCols = getTableColumns(tableName: "transactions")
            let targetCols: Set<String> = [
                "uuid", "date", "amount", "category_id", "merchant", "source", 
                "account_id", "tx_hash", "sub_category", "notes", "is_recurring", 
                "recurring_frequency", "transfer_pair_id", "refund_original_uuid", "created_at"
            ]
            let colsToCopy = existingCols.filter { targetCols.contains($0) }
            let colString = colsToCopy.joined(separator: ", ")
            
            execute(sql: "PRAGMA foreign_keys = OFF;")
            execute(sql: "BEGIN IMMEDIATE;")
            execute(sql: "ALTER TABLE transactions RENAME TO transactions_legacy;")
            execute(sql: """
                CREATE TABLE transactions (
                    uuid TEXT PRIMARY KEY,
                    date TEXT NOT NULL,
                    amount REAL NOT NULL,
                    category_id INTEGER,
                    merchant TEXT NOT NULL,
                    source TEXT CHECK(source IN ('manual', 'csv', 'ai', 'transfer', 'refund')) NOT NULL,
                    account_id TEXT,
                    tx_hash TEXT,
                    sub_category TEXT,
                    notes TEXT,
                    is_recurring INTEGER DEFAULT 0,
                    recurring_frequency TEXT,
                    transfer_pair_id TEXT,
                    refund_original_uuid TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
                    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
                );
            """)
            if !colsToCopy.isEmpty {
                execute(sql: """
                    INSERT INTO transactions (\(colString))
                    SELECT \(colString) FROM transactions_legacy;
                """)
            }
            execute(sql: "DROP TABLE transactions_legacy;")
            execute(sql: "COMMIT;")
            execute(sql: "PRAGMA foreign_keys = ON;")
        }
        
        // Refresh tableSQL after potential table rebuild
        tableSQL = ""
        if sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type='table' AND name='transactions';", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            tableSQL = String(cString: c)
        }
        sqlite3_finalize(stmt)
        
        if !tableSQL.contains("tx_hash") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN tx_hash TEXT;")
        }
        if !tableSQL.contains("sub_category") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN sub_category TEXT;")
        }
        if !tableSQL.contains("notes") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN notes TEXT;")
        }
        if !tableSQL.contains("is_recurring") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN is_recurring INTEGER DEFAULT 0;")
        }
        if !tableSQL.contains("recurring_frequency") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN recurring_frequency TEXT;")
        }
        if !tableSQL.contains("transfer_pair_id") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN transfer_pair_id TEXT;")
        }
        if !tableSQL.contains("refund_original_uuid") {
            execute(sql: "ALTER TABLE transactions ADD COLUMN refund_original_uuid TEXT;")
        }
        
        var accountsSQL = ""
        if sqlite3_prepare_v2(db, "SELECT sql FROM sqlite_master WHERE type='table' AND name='accounts';", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            accountsSQL = String(cString: c)
        }
        sqlite3_finalize(stmt)
        
        if !accountsSQL.contains("parent_id") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN parent_id TEXT;")
        }
        if !accountsSQL.contains("include_in_net_worth") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN include_in_net_worth INTEGER DEFAULT 1;")
        }
        if !accountsSQL.contains("account_number") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN account_number TEXT;")
        }
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS sub_categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                category_name TEXT NOT NULL,
                name TEXT NOT NULL,
                UNIQUE(category_name, name)
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS imported_statements (
                statement_hash TEXT PRIMARY KEY,
                institution TEXT,
                period_start TEXT,
                period_end TEXT,
                total_debits REAL,
                total_credits REAL,
                tx_count INTEGER,
                imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
        
        execute(sql: """
            CREATE TABLE IF NOT EXISTS recurring_payments (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                amount REAL NOT NULL,
                category_id INTEGER,
                account_id TEXT,
                frequency TEXT NOT NULL,
                start_date TEXT NOT NULL,
                next_due_date TEXT NOT NULL,
                is_active INTEGER DEFAULT 1,
                notes TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
            );
        """)
        
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id);")
        execute(sql: "CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_hash ON transactions(tx_hash) WHERE tx_hash IS NOT NULL;")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_accounts_parent ON accounts(parent_id);")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_recurring_active ON recurring_payments(is_active);")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_tx_transfer_pair ON transactions(transfer_pair_id);")
        execute(sql: "CREATE INDEX IF NOT EXISTS idx_tx_refund_original ON transactions(refund_original_uuid);")
        
        deduplicateLegacyCategories()
        linkExistingTransferPairs()
    }
    
    private func linkExistingTransferPairs() {
        // Find pairs of transfers on the same date where amount1 == -amount2 and neither is paired yet
        let sql = """
            SELECT t1.uuid, t2.uuid
            FROM transactions t1
            JOIN transactions t2 ON t1.source = 'transfer'
                AND t2.source = 'transfer'
                AND t1.uuid != t2.uuid
                AND t1.date = t2.date
                AND ABS(t1.amount + t2.amount) < 0.001
                AND (t1.transfer_pair_id IS NULL OR t1.transfer_pair_id = '')
                AND (t2.transfer_pair_id IS NULL OR t2.transfer_pair_id = '');
        """
        var statement: OpaquePointer? = nil
        var pairs: [(String, String)] = []
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            var pairedUUIDs = Set<String>()
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let u1C = sqlite3_column_text(statement, 0),
                      let u2C = sqlite3_column_text(statement, 1) else { continue }
                let u1 = String(cString: u1C)
                let u2 = String(cString: u2C)
                if !pairedUUIDs.contains(u1) && !pairedUUIDs.contains(u2) {
                    pairs.append((u1, u2))
                    pairedUUIDs.insert(u1)
                    pairedUUIDs.insert(u2)
                }
            }
        }
        sqlite3_finalize(statement)
        
        for (u1, u2) in pairs {
            let updateSQL = "UPDATE transactions SET transfer_pair_id = ? WHERE uuid = ?;"
            var s1: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, updateSQL, -1, &s1, nil) == SQLITE_OK {
                sqlite3_bind_text(s1, 1, u2, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(s1, 2, u1, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(s1)
            }
            sqlite3_finalize(s1)
            
            var s2: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, updateSQL, -1, &s2, nil) == SQLITE_OK {
                sqlite3_bind_text(s2, 1, u1, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(s2, 2, u2, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(s2)
            }
            sqlite3_finalize(s2)
        }
    }
    
    private func addCategoryRaw(name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty, lower != "transfer", lower != "transfers" else { return nil }
        let sql = "INSERT OR IGNORE INTO categories (name) VALUES (?);"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, trimmed, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        return getCategoryID(name: trimmed)
    }
    
    private func purgeTransferCategoryRecords() {
        execute(sql: "BEGIN IMMEDIATE;")
        execute(sql: """
            UPDATE transactions
            SET source = 'transfer', category_id = NULL
            WHERE category_id IN (SELECT id FROM categories WHERE LOWER(TRIM(name)) IN ('transfer', 'transfers'));
        """)
        execute(sql: "UPDATE transactions SET category_id = NULL WHERE source = 'transfer' AND category_id IS NOT NULL;")
        execute(sql: "DELETE FROM budgets WHERE category_id IN (SELECT id FROM categories WHERE LOWER(TRIM(name)) IN ('transfer', 'transfers'));")
        execute(sql: "DELETE FROM sub_categories WHERE LOWER(TRIM(category_name)) IN ('transfer', 'transfers');")
        execute(sql: "DELETE FROM categories WHERE LOWER(TRIM(name)) IN ('transfer', 'transfers');")
        execute(sql: "COMMIT;")
    }
    
    public func deduplicateLegacyCategories() {
        let mappings: [(old: String, canonical: String)] = [
            ("Groceries", "Grocery"),
            ("groceries", "Grocery"),
            ("grocery", "Grocery"),
            ("Dining", "Food & Drink"),
            ("dining", "Food & Drink"),
            ("Food", "Food & Drink"),
            ("food", "Food & Drink"),
            ("Drink", "Food & Drink"),
            ("drinks", "Food & Drink"),
            ("Transport", "Transportation"),
            ("transport", "Transportation"),
            ("Transit", "Transportation"),
            ("transit", "Transportation"),
            ("Utilities", "Housing & Utilities"),
            ("utilities", "Housing & Utilities"),
            ("Housing", "Housing & Utilities"),
            ("housing", "Housing & Utilities"),
            ("Entertainment", "Social Life"),
            ("entertainment", "Social Life"),
            ("Income", "Salary"),
            ("income", "Salary"),
            ("shopping", "Shopping"),
            ("health", "Health Care"),
            ("Health", "Health Care")
        ]
        
        execute(sql: "BEGIN IMMEDIATE;")
        for map in mappings {
            guard let canonicalID = addCategoryRaw(name: map.canonical) else { continue }
            
            var selectStmt: OpaquePointer? = nil
            var oldIDs: [Int] = []
            let selectSQL = "SELECT id FROM categories WHERE name = ? COLLATE NOCASE AND id != ?;"
            if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(selectStmt, 1, map.old, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(selectStmt, 2, Int32(canonicalID))
                while sqlite3_step(selectStmt) == SQLITE_ROW {
                    oldIDs.append(Int(sqlite3_column_int(selectStmt, 0)))
                }
            }
            sqlite3_finalize(selectStmt)
            
            for oldID in oldIDs {
                execute(sql: "UPDATE transactions SET category_id = \(canonicalID) WHERE category_id = \(oldID);")
                execute(sql: "INSERT OR IGNORE INTO budgets (category_id, monthly_limit) SELECT \(canonicalID), monthly_limit FROM budgets WHERE category_id = \(oldID);")
                execute(sql: "DELETE FROM budgets WHERE category_id = \(oldID);")
                execute(sql: "DELETE FROM categories WHERE id = \(oldID);")
            }
        }
        execute(sql: "COMMIT;")
    }
    
    private func seedCategories() {
        let defaultCategories = [
            "Grocery", "Food & Drink", "Social Life", "Transportation",
            "Housing & Utilities", "Personal Care", "Shopping", "Health Care",
            "Membership", "Giving", "Salary", "Investment", "Gifts/Grants", "Miscellaneous"
        ]
        
        for category in defaultCategories {
            let sql = "INSERT OR IGNORE INTO categories (name) VALUES (?);"
            var statement: OpaquePointer? = nil
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, category, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
        }
    }
    
    private func seedSubCategoriesIfNeeded() {
        let seedKey = "did_seed_merchants_v1"
        if !UserDefaults.standard.bool(forKey: seedKey) {
            let defaultCategories = [
                "Grocery", "Food & Drink", "Social Life", "Transportation",
                "Housing & Utilities", "Personal Care", "Shopping", "Health Care",
                "Membership", "Giving", "Salary", "Investment", "Gifts/Grants", "Miscellaneous"
            ]
            execute(sql: "BEGIN IMMEDIATE;")
            execute(sql: "DELETE FROM sub_categories;")
            let insertSQL = "INSERT OR IGNORE INTO sub_categories (category_name, name) VALUES (?, ?);"
            for cat in defaultCategories {
                for merch in Category.suggestedMerchants(for: cat) {
                    var stmt: OpaquePointer? = nil
                    if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(stmt, 1, cat, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(stmt, 2, merch, -1, SQLITE_TRANSIENT)
                        _ = sqlite3_step(stmt)
                    }
                    sqlite3_finalize(stmt)
                }
            }
            // Also seed any existing transaction merchants per category
            execute(sql: """
                INSERT OR IGNORE INTO sub_categories (category_name, name)
                SELECT COALESCE(c.name, 'Miscellaneous'), t.merchant
                FROM transactions t
                LEFT JOIN categories c ON t.category_id = c.id
                WHERE t.merchant IS NOT NULL
                  AND TRIM(t.merchant) != ''
                  AND t.source != 'transfer'
                  AND LOWER(TRIM(t.merchant)) != LOWER(COALESCE(c.name, 'Miscellaneous'));
            """)
            execute(sql: "COMMIT;")
            UserDefaults.standard.set(true, forKey: seedKey)
        }
    }
    
    private func purgeFakeSeedDataIfNeeded() {
        execute(sql: "BEGIN IMMEDIATE;")
        execute(sql: "DELETE FROM transactions WHERE account_id LIKE 'acc-%';")
        execute(sql: "DELETE FROM accounts WHERE id LIKE 'acc-%';")
        execute(sql: "COMMIT;")
    }
    
    public func clearAllData(keepCategories: Bool = true) {
        execute(sql: "BEGIN IMMEDIATE;")
        execute(sql: "DELETE FROM transactions;")
        execute(sql: "DELETE FROM accounts;")
        execute(sql: "DELETE FROM budgets;")
        execute(sql: "DELETE FROM imported_statements;")
        if !keepCategories {
            execute(sql: "DELETE FROM categories;")
        }
        execute(sql: "COMMIT;")
        refreshData()
    }
    
    public func clearImportedStatementsHistory() {
        execute(sql: "DELETE FROM imported_statements;")
    }
    
    public func getCategoryID(name: String) -> Int? {
        let sql = "SELECT id FROM categories WHERE name = ? COLLATE NOCASE;"
        var statement: OpaquePointer? = nil
        var id: Int? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW {
                id = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return id
    }
    
    public func refreshData() {
        let loadedCategories = loadCategories()
        let loadedSubCategories = loadSubCategories()
        let loadedBudgets = loadBudgets()
        let loadedTransactions = loadTransactions()
        let loadedAccounts = loadAccounts()
        let loadedRecurring = loadRecurringPayments()
        
        var accMap: [String: Account] = [:]
        accMap.reserveCapacity(loadedAccounts.count)
        for acc in loadedAccounts {
            accMap[acc.id] = acc
        }
        
        var budgMap: [Int: Double] = [:]
        budgMap.reserveCapacity(loadedBudgets.count)
        for b in loadedBudgets {
            budgMap[b.categoryID] = b.monthlyLimit
        }
        
        DispatchQueue.main.async {
            self.categories = loadedCategories
            self.subCategoriesByCategory = loadedSubCategories
            self.budgets = loadedBudgets
            self.budgetsByCategoryID = budgMap
            self.transactions = loadedTransactions
            self.accounts = loadedAccounts
            self.accountsByID = accMap
            self.recurringPayments = loadedRecurring
            self.syncWidgetSnapshot(categories: loadedCategories, transactions: loadedTransactions)
        }
    }
    
    public func syncWidgetSnapshot(categories: [Category]? = nil, transactions: [Transaction]? = nil) {
        let cats = categories ?? self.categories
        let txs = transactions ?? self.transactions
        
        let expenseShortcuts: [WidgetExpenseShortcut] = cats
            .filter { !CategoryStyle.style(for: $0.name).isIncome && !$0.name.lowercased().contains("transfer") }
            .map { WidgetExpenseShortcut(name: $0.name) }
        
        let now = Date()
        var catSpendMap: [String: [String: Double]] = [:]
        var totalSpendMap: [String: Double] = [:]
        
        for tf in WidgetTimeframe.allCases {
            let range = tf.dateRange(from: now)
            var rawCatSpend: [String: Double] = [:]
            var rawTotal: Double = 0.0
            
            for tx in txs {
                guard tx.date >= range.start && tx.date <= range.end else { continue }
                guard tx.source != "transfer", !tx.isIncome else { continue }
                let impact = tx.netExpenseImpact
                rawTotal += impact
                let catKey = (tx.categoryName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !catKey.isEmpty {
                    rawCatSpend[catKey, default: 0.0] += impact
                }
            }
            
            var clampedCatSpend: [String: Double] = [:]
            for (k, v) in rawCatSpend {
                clampedCatSpend[k] = max(0.0, v)
            }
            catSpendMap[tf.rawValue] = clampedCatSpend
            totalSpendMap[tf.rawValue] = max(0.0, rawTotal)
        }
        
        let monthlyTotal = totalSpendMap[WidgetTimeframe.monthly.rawValue] ?? 0.0
        let currency = UserDefaults.standard.string(forKey: "selectedCurrencySymbol") ?? "$"
        let selectedNames = WidgetDataStore.loadSelectedCategoryNames()
        let selectedTimeframe = WidgetDataStore.loadSelectedTimeframe()
        
        let payload = WidgetSnapshotPayload(
            selectedCategoryNames: selectedNames,
            allExpenseCategories: expenseShortcuts.isEmpty ? WidgetExpenseShortcut.defaultCatalog : expenseShortcuts,
            monthlySpendTotal: monthlyTotal,
            currencySymbol: currency,
            selectedTimeframeRaw: selectedTimeframe.rawValue,
            categorySpendByTimeframe: catSpendMap,
            totalSpendByTimeframe: totalSpendMap,
            updatedAt: now
        )
        WidgetDataStore.saveSnapshot(payload)
    }
    
    internal func loadSubCategories() -> [String: [String]] {
        let sql = "SELECT category_name, name FROM sub_categories ORDER BY id ASC;"
        var statement: OpaquePointer? = nil
        var loaded: [String: [String]] = [:]
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let catC = sqlite3_column_text(statement, 0),
                      let nameC = sqlite3_column_text(statement, 1) else { continue }
                let cat = String(cString: catC)
                let name = String(cString: nameC)
                var arr = loaded[cat] ?? []
                if !arr.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    arr.append(name)
                }
                loaded[cat] = arr
            }
        }
        sqlite3_finalize(statement)
        return loaded
    }
    
    internal func loadCategories() -> [Category] {
        let sql = "SELECT id, name FROM categories WHERE LOWER(TRIM(name)) NOT IN ('transfer', 'transfers') ORDER BY name;"
        var statement: OpaquePointer? = nil
        var loadedCategories: [Category] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(statement, 0))
                if let nameCString = sqlite3_column_text(statement, 1) {
                    let name = String(cString: nameCString)
                    loadedCategories.append(Category(id: id, name: name))
                }
            }
        }
        sqlite3_finalize(statement)
        return loadedCategories
    }
    
    internal func loadBudgets() -> [Budget] {
        let sql = """
            SELECT c.id, c.name, COALESCE(b.monthly_limit, 0.0)
            FROM categories c
            LEFT JOIN budgets b ON c.id = b.category_id
            WHERE LOWER(TRIM(c.name)) NOT IN ('transfer', 'transfers')
            ORDER BY c.name;
        """
        var statement: OpaquePointer? = nil
        var loadedBudgets: [Budget] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let categoryID = Int(sqlite3_column_int(statement, 0))
                guard let nameCString = sqlite3_column_text(statement, 1) else { continue }
                let categoryName = String(cString: nameCString)
                let monthlyLimit = sqlite3_column_double(statement, 2)
                
                loadedBudgets.append(Budget(categoryID: categoryID, categoryName: categoryName, monthlyLimit: monthlyLimit))
            }
        }
        sqlite3_finalize(statement)
        return loadedBudgets
    }
    
    private func ensureAccountRewardsSchema() {
        let cols = getTableColumns(tableName: "accounts")
        if !cols.contains("base_rate") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN base_rate REAL DEFAULT 0.0;")
        }
        if !cols.contains("bonus_rate") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN bonus_rate REAL DEFAULT 0.0;")
        }
        if !cols.contains("bonus_categories") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN bonus_categories TEXT;")
        }
        if !cols.contains("bonus_tiers_json") {
            execute(sql: "ALTER TABLE accounts ADD COLUMN bonus_tiers_json TEXT;")
        }
    }
    
    internal func loadAccounts() -> [Account] {
        let sql = "SELECT id, name, type, balance, institution, icon_name, color_hex, parent_id, COALESCE(include_in_net_worth, 1), account_number, COALESCE(base_rate, 0.0), COALESCE(bonus_rate, 0.0), bonus_categories, bonus_tiers_json FROM accounts ORDER BY type, name;"
        var statement: OpaquePointer? = nil
        var loadedAccounts: [Account] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(statement, 0),
                      let nameC = sqlite3_column_text(statement, 1),
                      let typeC = sqlite3_column_text(statement, 2),
                      let instC = sqlite3_column_text(statement, 4),
                      let iconC = sqlite3_column_text(statement, 5),
                      let colorC = sqlite3_column_text(statement, 6) else { continue }
                
                let id = String(cString: idC)
                let name = String(cString: nameC)
                let typeRaw = String(cString: typeC)
                let balance = sqlite3_column_double(statement, 3)
                let inst = String(cString: instC)
                let icon = String(cString: iconC)
                let color = String(cString: colorC)
                let parentID: String? = {
                    if sqlite3_column_type(statement, 7) != SQLITE_NULL, let pC = sqlite3_column_text(statement, 7) {
                        let str = String(cString: pC)
                        return str.isEmpty ? nil : str
                    }
                    return nil
                }()
                let includeInNetWorth = sqlite3_column_int(statement, 8) != 0
                let accountNumber: String? = {
                    if sqlite3_column_type(statement, 9) != SQLITE_NULL, let aC = sqlite3_column_text(statement, 9) {
                        let str = String(cString: aC).trimmingCharacters(in: .whitespacesAndNewlines)
                        return str.isEmpty ? nil : str
                    }
                    return nil
                }()
                let baseRate = sqlite3_column_count(statement) > 10 ? sqlite3_column_double(statement, 10) : 0.0
                let bonusRate = sqlite3_column_count(statement) > 11 ? sqlite3_column_double(statement, 11) : 0.0
                let bonusCategories: [String] = {
                    if sqlite3_column_count(statement) > 12,
                       sqlite3_column_type(statement, 12) != SQLITE_NULL,
                       let bC = sqlite3_column_text(statement, 12) {
                        let raw = String(cString: bC)
                        return raw
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                    return []
                }()
                let bonusTiers: [CardBonusTier] = {
                    if sqlite3_column_count(statement) > 13,
                       sqlite3_column_type(statement, 13) != SQLITE_NULL,
                       let tC = sqlite3_column_text(statement, 13) {
                        let jsonStr = String(cString: tC)
                        if let data = jsonStr.data(using: .utf8),
                           let decoded = try? JSONDecoder().decode([CardBonusTier].self, from: data) {
                            return decoded
                        }
                    }
                    return []
                }()
                
                let type = AccountType(fromRaw: typeRaw) ?? AccountType(rawValue: typeRaw) ?? .debit
                loadedAccounts.append(Account(
                    id: id,
                    name: name,
                    type: type,
                    balance: balance,
                    institution: inst,
                    iconName: icon,
                    colorHex: color,
                    parentID: parentID,
                    includeInNetWorth: includeInNetWorth,
                    accountNumber: accountNumber,
                    baseRate: baseRate,
                    bonusRate: bonusRate,
                    bonusCategories: bonusCategories,
                    bonusTiers: bonusTiers
                ))
            }
        }
        sqlite3_finalize(statement)
        return loadedAccounts
    }
    
    internal func loadTransactions() -> [Transaction] {
        let sql = """
            SELECT t.uuid, t.date, t.amount, t.category_id, c.name, t.merchant, t.source, t.account_id, t.sub_category, t.notes, t.tx_hash, t.is_recurring, t.recurring_frequency, t.transfer_pair_id, t.refund_original_uuid
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            ORDER BY t.date DESC, t.created_at DESC;
        """
        var statement: OpaquePointer? = nil
        var loadedTransactions: [Transaction] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let uuidCString = sqlite3_column_text(statement, 0),
                      let dateCString = sqlite3_column_text(statement, 1),
                      let merchantCString = sqlite3_column_text(statement, 5),
                      let sourceCString = sqlite3_column_text(statement, 6) else { continue }
                
                let uuid = String(cString: uuidCString)
                let dateStr = String(cString: dateCString)
                let amount = sqlite3_column_double(statement, 2)
                
                let categoryID = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 3))
                let categoryName = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4))
                
                let merchant = String(cString: merchantCString)
                let source = String(cString: sourceCString)
                
                let accountID = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 7))
                let subCategory: String? = {
                    if sqlite3_column_type(statement, 8) != SQLITE_NULL, let c = sqlite3_column_text(statement, 8) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                let notes: String? = {
                    if sqlite3_column_type(statement, 9) != SQLITE_NULL, let c = sqlite3_column_text(statement, 9) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                let txHash: String? = {
                    if sqlite3_column_type(statement, 10) != SQLITE_NULL, let c = sqlite3_column_text(statement, 10) {
                        let s = String(cString: c)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                let isRecurring: Bool = {
                    if sqlite3_column_count(statement) > 11 && sqlite3_column_type(statement, 11) != SQLITE_NULL {
                        return sqlite3_column_int(statement, 11) == 1
                    }
                    return false
                }()
                let recurringFrequency: String? = {
                    if sqlite3_column_count(statement) > 12 && sqlite3_column_type(statement, 12) != SQLITE_NULL, let c = sqlite3_column_text(statement, 12) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                let transferPairID: String? = {
                    if sqlite3_column_count(statement) > 13 && sqlite3_column_type(statement, 13) != SQLITE_NULL, let c = sqlite3_column_text(statement, 13) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                let refundOriginalUUID: String? = {
                    if sqlite3_column_count(statement) > 14 && sqlite3_column_type(statement, 14) != SQLITE_NULL, let c = sqlite3_column_text(statement, 14) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                
                let date = dateFormatter.date(from: dateStr) ?? Date()
                
                loadedTransactions.append(Transaction(
                    uuid: uuid,
                    date: date,
                    amount: amount,
                    categoryID: categoryID,
                    categoryName: categoryName,
                    merchant: merchant,
                    source: source,
                    accountID: accountID,
                    subCategory: subCategory,
                    notes: notes,
                    txHash: txHash,
                    isRecurring: isRecurring,
                    recurringFrequency: recurringFrequency,
                    transferPairID: transferPairID,
                    refundOriginalUUID: refundOriginalUUID
                ))
            }
        }
        sqlite3_finalize(statement)
        return loadedTransactions
    }
    
    public func addTransaction(
        date: Date,
        amount: Double,
        categoryID: Int?,
        merchant: String,
        subCategory: String? = nil,
        notes: String? = nil,
        source: String = "manual",
        accountID: String? = nil,
        txHash: String? = nil,
        isRecurring: Bool = false,
        recurringFrequency: String? = nil,
        refundOriginalUUID: String? = nil
    ) {
        let sql = """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, tx_hash, is_recurring, recurring_frequency, refund_original_uuid)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer? = nil
        
        execute(sql: "BEGIN IMMEDIATE;")
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let txUUID = UUID().uuidString
            let dateStr = dateFormatter.string(from: date)
            
            sqlite3_bind_text(statement, 1, txUUID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, amount)
            
            if let catID = categoryID {
                sqlite3_bind_int(statement, 4, Int32(catID))
            } else {
                sqlite3_bind_null(statement, 4)
            }
            
            sqlite3_bind_text(statement, 5, merchant, -1, SQLITE_TRANSIENT)
            
            if let sub = subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
                sqlite3_bind_text(statement, 6, sub, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(statement, 7, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            
            sqlite3_bind_text(statement, 8, source, -1, SQLITE_TRANSIENT)
            
            if let accID = accountID {
                sqlite3_bind_text(statement, 9, accID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            
            if let hash = txHash, !hash.isEmpty {
                sqlite3_bind_text(statement, 10, hash, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            
            sqlite3_bind_int(statement, 11, isRecurring ? 1 : 0)
            
            if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                sqlite3_bind_text(statement, 12, rf, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 12)
            }
            
            if let refUUID = refundOriginalUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !refUUID.isEmpty {
                sqlite3_bind_text(statement, 13, refUUID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 13)
            }
            
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        let catNameForMerch = categories.first(where: { $0.id == categoryID })?.name ?? "Miscellaneous"
        let trimmedMerch = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMerch.isEmpty && source != "transfer" && trimmedMerch.caseInsensitiveCompare(catNameForMerch) != .orderedSame {
            insertSubCategoryRaw(name: trimmedMerch, categoryName: catNameForMerch)
        }
        if let sub = subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            insertSubCategoryRaw(name: sub, categoryName: catNameForMerch)
        }
        
        // Update account balance:
        // Asset account: -amount decreases balance on expense (+amount), increases on income (-amount).
        // Liability account: +amount increases balance (amount owed) on expense (+amount), decreases on payment (-amount).
        if let accID = accountID {
            adjustAccountBalance(id: accID, delta: balanceDelta(accountID: accID, amount: amount))
        }
        execute(sql: "COMMIT;")
        
        if isRecurring && amount != 0 {
            let catName = categories.first(where: { $0.id == categoryID })?.name
            let freq = RecurringFrequency(rawValue: recurringFrequency ?? "Monthly") ?? .monthly
            let recType: RecurringTransactionType = {
                if source == "transfer" { return .transfer }
                if amount < 0 || CategoryStyle.style(for: catName ?? "").isIncome { return .income }
                return .expense
            }()
            addOrUpdateRecurringPaymentForTransaction(
                name: merchant,
                amount: abs(amount),
                categoryID: categoryID,
                categoryName: catName,
                accountID: accountID,
                frequency: freq,
                startDate: dateFormatter.string(from: date),
                notes: notes,
                type: recType
            )
        }
        
        refreshData()
    }
    
    public func deleteTransaction(uuid: String) {
        execute(sql: "BEGIN IMMEDIATE;")
        
        // 1. Fetch current transaction record to atomically reverse account balance
        var oldAmount: Double? = nil
        var oldAccountID: String? = nil
        var oldSource: String? = nil
        var transferPairID: String? = nil
        var txDate: String? = nil
        var selectStmt: OpaquePointer? = nil
        let selectSQL = "SELECT amount, account_id, source, transfer_pair_id, date FROM transactions WHERE uuid = ?;"
        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(selectStmt, 1, uuid, -1, SQLITE_TRANSIENT)
            if sqlite3_step(selectStmt) == SQLITE_ROW {
                oldAmount = sqlite3_column_double(selectStmt, 0)
                if sqlite3_column_type(selectStmt, 1) != SQLITE_NULL, let c = sqlite3_column_text(selectStmt, 1) {
                    oldAccountID = String(cString: c)
                }
                if sqlite3_column_type(selectStmt, 2) != SQLITE_NULL, let c = sqlite3_column_text(selectStmt, 2) {
                    oldSource = String(cString: c)
                }
                if sqlite3_column_type(selectStmt, 3) != SQLITE_NULL, let c = sqlite3_column_text(selectStmt, 3) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { transferPairID = s }
                }
                if sqlite3_column_type(selectStmt, 4) != SQLITE_NULL, let c = sqlite3_column_text(selectStmt, 4) {
                    txDate = String(cString: c)
                }
            }
        }
        sqlite3_finalize(selectStmt)
        
        guard let primaryAmt = oldAmount else {
            execute(sql: "COMMIT;")
            return
        }
        
        // 2. Atomically reverse the primary account balance
        if let primaryAcc = oldAccountID {
            adjustAccountBalance(id: primaryAcc, delta: -balanceDelta(accountID: primaryAcc, amount: primaryAmt))
        }
        
        // 3. Find paired transfer transaction if applicable
        var pairedUUID: String? = transferPairID
        var pairedAmount: Double? = nil
        var pairedAccountID: String? = nil
        
        if let pairID = pairedUUID {
            var pairStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "SELECT amount, account_id FROM transactions WHERE uuid = ?;", -1, &pairStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(pairStmt, 1, pairID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(pairStmt) == SQLITE_ROW {
                    pairedAmount = sqlite3_column_double(pairStmt, 0)
                    if sqlite3_column_type(pairStmt, 1) != SQLITE_NULL, let c = sqlite3_column_text(pairStmt, 1) {
                        pairedAccountID = String(cString: c)
                    }
                }
            }
            sqlite3_finalize(pairStmt)
        } else if oldSource == "transfer", let d = txDate {
            // Fallback heuristic for legacy unlinked transfers
            var fallbackStmt: OpaquePointer? = nil
            let fallbackSQL = """
                SELECT uuid, amount, account_id FROM transactions
                WHERE source = 'transfer' AND uuid != ? AND date = ? AND ABS(amount + ?) < 0.001
                LIMIT 1;
            """
            if sqlite3_prepare_v2(db, fallbackSQL, -1, &fallbackStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(fallbackStmt, 1, uuid, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(fallbackStmt, 2, d, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(fallbackStmt, 3, primaryAmt)
                if sqlite3_step(fallbackStmt) == SQLITE_ROW {
                    if let u = sqlite3_column_text(fallbackStmt, 0) {
                        pairedUUID = String(cString: u)
                    }
                    pairedAmount = sqlite3_column_double(fallbackStmt, 1)
                    if sqlite3_column_type(fallbackStmt, 2) != SQLITE_NULL, let c = sqlite3_column_text(fallbackStmt, 2) {
                        pairedAccountID = String(cString: c)
                    }
                }
            }
            sqlite3_finalize(fallbackStmt)
        }
        
        // 4. Atomically reverse the paired account balance and delete the paired transaction
        if let pAcc = pairedAccountID, let pAmt = pairedAmount {
            adjustAccountBalance(id: pAcc, delta: -balanceDelta(accountID: pAcc, amount: pAmt))
        }
        
        if let pUUID = pairedUUID {
            var delPairStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "DELETE FROM transactions WHERE uuid = ?;", -1, &delPairStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delPairStmt, 1, pUUID, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(delPairStmt)
            }
            sqlite3_finalize(delPairStmt)
        }
        
        // 5. Unlink any child refund records referencing this transaction
        var unlinkStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "UPDATE transactions SET refund_original_uuid = NULL WHERE refund_original_uuid = ?;", -1, &unlinkStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(unlinkStmt, 1, uuid, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(unlinkStmt)
        }
        sqlite3_finalize(unlinkStmt)
        
        // 6. Delete the primary transaction
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "DELETE FROM transactions WHERE uuid = ?;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, uuid, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        execute(sql: "COMMIT;")
        refreshData()
    }
    
    public func updateTransaction(
        uuid: String,
        date: Date,
        amount: Double,
        categoryID: Int?,
        merchant: String,
        subCategory: String? = nil,
        notes: String? = nil,
        accountID: String?,
        isRecurring: Bool = false,
        recurringFrequency: String? = nil,
        source: String? = nil
    ) {
        execute(sql: "BEGIN IMMEDIATE;")
        
        // 1. Fetch current transaction record to reverse old balance
        var oldAmount: Double? = nil
        var oldAccountID: String? = nil
        var selectStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "SELECT amount, account_id FROM transactions WHERE uuid = ?;", -1, &selectStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(selectStmt, 1, uuid, -1, SQLITE_TRANSIENT)
            if sqlite3_step(selectStmt) == SQLITE_ROW {
                oldAmount = sqlite3_column_double(selectStmt, 0)
                if sqlite3_column_type(selectStmt, 1) != SQLITE_NULL, let c = sqlite3_column_text(selectStmt, 1) {
                    oldAccountID = String(cString: c)
                }
            }
        }
        sqlite3_finalize(selectStmt)
        
        if let oldAcc = oldAccountID, let oldAmt = oldAmount {
            adjustAccountBalance(id: oldAcc, delta: -balanceDelta(accountID: oldAcc, amount: oldAmt))
        }
        
        // 2. Update transaction
        let sql = """
            UPDATE transactions
            SET date = ?, amount = ?, category_id = ?, merchant = ?, sub_category = ?, notes = ?, account_id = ?, is_recurring = ?, recurring_frequency = ?, source = COALESCE(?, source)
            WHERE uuid = ?;
        """
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let dateStr = dateFormatter.string(from: date)
            sqlite3_bind_text(stmt, 1, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, amount)
            if let catID = categoryID {
                sqlite3_bind_int(stmt, 3, Int32(catID))
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, merchant, -1, SQLITE_TRANSIENT)
            if let sub = subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
                sqlite3_bind_text(stmt, 5, sub, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(stmt, 6, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let acc = accountID {
                sqlite3_bind_text(stmt, 7, acc, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_int(stmt, 8, isRecurring ? 1 : 0)
            if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                sqlite3_bind_text(stmt, 9, rf, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            if let src = source?.trimmingCharacters(in: .whitespacesAndNewlines), !src.isEmpty {
                sqlite3_bind_text(stmt, 10, src, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            sqlite3_bind_text(stmt, 11, uuid, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        let catNameForMerch = categories.first(where: { $0.id == categoryID })?.name ?? "Miscellaneous"
        let trimmedMerch = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMerch.isEmpty && source != "transfer" && trimmedMerch.caseInsensitiveCompare(catNameForMerch) != .orderedSame {
            insertSubCategoryRaw(name: trimmedMerch, categoryName: catNameForMerch)
        }
        if let sub = subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            insertSubCategoryRaw(name: sub, categoryName: catNameForMerch)
        }
        
        // 3. Apply new balance delta
        if let newAcc = accountID {
            adjustAccountBalance(id: newAcc, delta: balanceDelta(accountID: newAcc, amount: amount))
        }
        
        // 4. Synchronize paired transfer transaction if applicable
        var pairUUID: String? = nil
        var pairAccountID: String? = nil
        var pairOldAmount: Double? = nil
        var pairStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "SELECT t2.uuid, t2.account_id, t2.amount FROM transactions t1 JOIN transactions t2 ON t1.transfer_pair_id = t2.uuid WHERE t1.uuid = ?;", -1, &pairStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(pairStmt, 1, uuid, -1, SQLITE_TRANSIENT)
            if sqlite3_step(pairStmt) == SQLITE_ROW {
                if let u = sqlite3_column_text(pairStmt, 0) { pairUUID = String(cString: u) }
                if sqlite3_column_type(pairStmt, 1) != SQLITE_NULL, let a = sqlite3_column_text(pairStmt, 1) { pairAccountID = String(cString: a) }
                pairOldAmount = sqlite3_column_double(pairStmt, 2)
            }
        }
        sqlite3_finalize(pairStmt)
        
        if let pUUID = pairUUID, let pAcc = pairAccountID, let pOldAmt = pairOldAmount {
            // Reverse paired account's old balance
            adjustAccountBalance(id: pAcc, delta: -balanceDelta(accountID: pAcc, amount: pOldAmt))
            // Update paired transaction with opposite amount, matching date, and recurring status
            let newPairAmount = -amount
            let updatePairSQL = "UPDATE transactions SET date = ?, amount = ?, is_recurring = ?, recurring_frequency = ? WHERE uuid = ?;"
            var upStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, updatePairSQL, -1, &upStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(upStmt, 1, dateFormatter.string(from: date), -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(upStmt, 2, newPairAmount)
                sqlite3_bind_int(upStmt, 3, isRecurring ? 1 : 0)
                if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                    sqlite3_bind_text(upStmt, 4, rf, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(upStmt, 4)
                }
                sqlite3_bind_text(upStmt, 5, pUUID, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(upStmt)
            }
            sqlite3_finalize(upStmt)
            // Apply new balance delta to paired account
            adjustAccountBalance(id: pAcc, delta: balanceDelta(accountID: pAcc, amount: newPairAmount))
        }
        
        execute(sql: "COMMIT;")
        
        if isRecurring && amount != 0 {
            let catName = categories.first(where: { $0.id == categoryID })?.name
            let freq = RecurringFrequency(rawValue: recurringFrequency ?? "Monthly") ?? .monthly
            let recType: RecurringTransactionType = {
                if source == "transfer" { return .transfer }
                if amount < 0 || CategoryStyle.style(for: catName ?? "").isIncome { return .income }
                return .expense
            }()
            addOrUpdateRecurringPaymentForTransaction(
                name: merchant,
                amount: abs(amount),
                categoryID: categoryID,
                categoryName: catName,
                accountID: accountID,
                frequency: freq,
                startDate: dateFormatter.string(from: date),
                notes: notes,
                type: recType
            )
        }
        
        refreshData()
    }
    
    // MARK: - Refund Transactions Management
    
    public func refunds(for originalUUID: String) -> [Transaction] {
        return transactions.filter { $0.refundOriginalUUID == originalUUID }
    }
    
    public func refundedAmount(for originalUUID: String) -> Double {
        return refunds(for: originalUUID).reduce(0.0) { $0 + abs($1.amount) }
    }
    
    public func remainingRefundableAmount(for originalUUID: String) -> Double {
        guard let original = transactions.first(where: { $0.uuid == originalUUID }),
              original.amount > 0 else {
            return 0.0
        }
        let refunded = refundedAmount(for: originalUUID)
        return max(0.0, original.amount - refunded)
    }
    
    public func isFullyRefunded(uuid: String) -> Bool {
        guard let original = transactions.first(where: { $0.uuid == uuid }), original.amount > 0 else {
            return false
        }
        let refunded = refundedAmount(for: uuid)
        return refunded >= (original.amount - 0.001) && refunded > 0
    }
    
    public func isPartiallyRefunded(uuid: String) -> Bool {
        guard let original = transactions.first(where: { $0.uuid == uuid }), original.amount > 0 else {
            return false
        }
        let refunded = refundedAmount(for: uuid)
        return refunded > 0.001 && refunded < (original.amount - 0.001)
    }
    
    @discardableResult
    public func recordRefund(
        originalTransaction: Transaction,
        refundAmount: Double,
        accountID: String? = nil,
        date: Date = Date(),
        notes: String? = nil
    ) -> Transaction? {
        let maxRefundable = remainingRefundableAmount(for: originalTransaction.uuid)
        guard maxRefundable > 0.001 else { return nil }
        
        let validAmount = min(refundAmount, maxRefundable)
        guard validAmount > 0.001 else { return nil }
        
        let targetAccountID = accountID ?? originalTransaction.accountID
        let refundMerchant = originalTransaction.merchant.hasPrefix("Refund:") 
            ? originalTransaction.merchant 
            : "Refund: \(originalTransaction.merchant)"
        
        let refundTxUUID = UUID().uuidString
        let dateStr = dateFormatter.string(from: date)
        let negativeAmount = -abs(validAmount)
        
        let sql = """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, refund_original_uuid)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'refund', ?, ?);
        """
        
        execute(sql: "BEGIN IMMEDIATE;")
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, refundTxUUID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, negativeAmount)
            
            if let catID = originalTransaction.categoryID {
                sqlite3_bind_int(statement, 4, Int32(catID))
            } else {
                sqlite3_bind_null(statement, 4)
            }
            
            sqlite3_bind_text(statement, 5, refundMerchant, -1, SQLITE_TRANSIENT)
            
            if let sub = originalTransaction.subCategory, !sub.isEmpty {
                sqlite3_bind_text(statement, 6, sub, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(statement, 7, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            
            if let accID = targetAccountID {
                sqlite3_bind_text(statement, 8, accID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 8)
            }
            
            sqlite3_bind_text(statement, 9, originalTransaction.uuid, -1, SQLITE_TRANSIENT)
            
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        // Update account balance
        if let accID = targetAccountID {
            adjustAccountBalance(id: accID, delta: balanceDelta(accountID: accID, amount: negativeAmount))
        }
        
        execute(sql: "COMMIT;")
        refreshData()
        
        return transactions.first(where: { $0.uuid == refundTxUUID })
    }
    
    // MARK: - Sub-Category Management (Add, Edit/Rename, Delete)
    
    private func insertSubCategoryRaw(name: String, categoryName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sql = "INSERT OR IGNORE INTO sub_categories (category_name, name) VALUES (?, ?);"
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, categoryName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, trimmed, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    /// Returns persisted sub-categories for a given category (editable and deletable by the user)
    public func allKnownSubCategories(for categoryName: String?) -> [String] {
        if let cat = categoryName {
            if let match = subCategoriesByCategory.first(where: { $0.key.caseInsensitiveCompare(cat) == .orderedSame }) {
                return match.value
            }
            // Fallback synchronous query if called before async publish
            var result: [String] = []
            var stmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "SELECT name FROM sub_categories WHERE category_name = ? COLLATE NOCASE ORDER BY id ASC;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cat, -1, SQLITE_TRANSIENT)
                while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c)
                    if !result.contains(where: { $0.caseInsensitiveCompare(s) == .orderedSame }) {
                        result.append(s)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return result
        } else {
            var all: [String] = []
            for list in subCategoriesByCategory.values {
                for item in list where !all.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) {
                    all.append(item)
                }
            }
            return all
        }
    }
    
    public func addSubCategory(name: String, for categoryName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insertSubCategoryRaw(name: trimmed, categoryName: categoryName)
        syncSubCategoriesToLocalFile()
        refreshData()
    }
    
    private func syncSubCategoriesToLocalFile() {
        var map: [String: [String]] = [:]
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "SELECT category_name, name FROM sub_categories ORDER BY id ASC;", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW,
                  let catC = sqlite3_column_text(stmt, 0),
                  let nameC = sqlite3_column_text(stmt, 1) {
                let cat = String(cString: catC)
                let name = String(cString: nameC)
                var list = map[cat] ?? []
                if !list.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    list.append(name)
                }
                map[cat] = list
            }
        }
        sqlite3_finalize(stmt)
        Category.saveLocalMerchantsMap(map)
    }
    
    public func allKnownMerchants(for categoryName: String?) -> [String] {
        allKnownSubCategories(for: categoryName)
    }
    
    public func addMerchant(name: String, for categoryName: String) {
        addSubCategory(name: name, for: categoryName)
    }
    
    public func renameMerchant(oldName: String, newName: String, for categoryName: String?) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else { return }
        
        execute(sql: "BEGIN IMMEDIATE;")
        if let cat = categoryName, !cat.isEmpty, let catID = getCategoryID(name: cat) {
            var txStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE transactions SET merchant = ? WHERE category_id = ? AND merchant = ? COLLATE NOCASE;", -1, &txStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(txStmt, 1, trimmedNew, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(txStmt, 2, Int32(catID))
                sqlite3_bind_text(txStmt, 3, trimmedOld, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(txStmt)
            }
            sqlite3_finalize(txStmt)
        } else {
            var txStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE transactions SET merchant = ? WHERE merchant = ? COLLATE NOCASE;", -1, &txStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(txStmt, 1, trimmedNew, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(txStmt, 2, trimmedOld, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(txStmt)
            }
            sqlite3_finalize(txStmt)
        }
        execute(sql: "COMMIT;")
        renameSubCategory(oldName: trimmedOld, newName: trimmedNew, for: categoryName)
    }
    
    public func deleteMerchant(name: String, for categoryName: String?) {
        deleteSubCategory(name: name, for: categoryName, clearFromTransactions: false)
    }
    
    public func renameSubCategory(oldName: String, newName: String, for categoryName: String?) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else { return }
        
        execute(sql: "BEGIN IMMEDIATE;")
        if let cat = categoryName, !cat.isEmpty {
            // Remove potential duplicate if renaming to an existing name in same category
            var delStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "DELETE FROM sub_categories WHERE category_name = ? COLLATE NOCASE AND name = ? COLLATE NOCASE AND name != ?;", -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, cat, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(delStmt, 2, trimmedNew, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(delStmt, 3, trimmedOld, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)
            
            var stmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE OR IGNORE sub_categories SET name = ? WHERE category_name = ? COLLATE NOCASE AND name = ? COLLATE NOCASE;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, trimmedNew, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, cat, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, trimmedOld, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            if let catID = getCategoryID(name: cat) {
                var txStmt: OpaquePointer? = nil
                if sqlite3_prepare_v2(db, "UPDATE transactions SET sub_category = ? WHERE category_id = ? AND sub_category = ? COLLATE NOCASE;", -1, &txStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(txStmt, 1, trimmedNew, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(txStmt, 2, Int32(catID))
                    sqlite3_bind_text(txStmt, 3, trimmedOld, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(txStmt)
                }
                sqlite3_finalize(txStmt)
            }
        } else {
            var stmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE OR IGNORE sub_categories SET name = ? WHERE name = ? COLLATE NOCASE;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, trimmedNew, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, trimmedOld, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            var txStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE transactions SET sub_category = ? WHERE sub_category = ? COLLATE NOCASE;", -1, &txStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(txStmt, 1, trimmedNew, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(txStmt, 2, trimmedOld, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(txStmt)
            }
            sqlite3_finalize(txStmt)
        }
        execute(sql: "COMMIT;")
        syncSubCategoriesToLocalFile()
        refreshData()
    }
    
    public func deleteSubCategory(name: String, for categoryName: String?, clearFromTransactions: Bool = true) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        execute(sql: "BEGIN IMMEDIATE;")
        if let cat = categoryName, !cat.isEmpty {
            var stmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "DELETE FROM sub_categories WHERE category_name = ? COLLATE NOCASE AND name = ? COLLATE NOCASE;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, cat, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, trimmed, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            if clearFromTransactions, let catID = getCategoryID(name: cat) {
                var txStmt: OpaquePointer? = nil
                if sqlite3_prepare_v2(db, "UPDATE transactions SET sub_category = NULL WHERE category_id = ? AND sub_category = ? COLLATE NOCASE;", -1, &txStmt, nil) == SQLITE_OK {
                    sqlite3_bind_int(txStmt, 1, Int32(catID))
                    sqlite3_bind_text(txStmt, 2, trimmed, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(txStmt)
                }
                sqlite3_finalize(txStmt)
            }
        } else {
            var stmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "DELETE FROM sub_categories WHERE name = ? COLLATE NOCASE;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
            
            if clearFromTransactions {
                var txStmt: OpaquePointer? = nil
                if sqlite3_prepare_v2(db, "UPDATE transactions SET sub_category = NULL WHERE sub_category = ? COLLATE NOCASE;", -1, &txStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(txStmt, 1, trimmed, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(txStmt)
                }
                sqlite3_finalize(txStmt)
            }
        }
        execute(sql: "COMMIT;")
        syncSubCategoriesToLocalFile()
        refreshData()
    }
    
    public func transactions(for accountID: String, includeSubAccounts: Bool = true) -> [Transaction] {
        if includeSubAccounts {
            let validIDs = Set([accountID] + allDescendantAccountIDs(of: accountID))
            return transactions.filter { tx in
                guard let accID = tx.accountID else { return false }
                return validIDs.contains(accID)
            }
        } else {
            return transactions.filter { $0.accountID == accountID }
        }
    }
    
    // MARK: - Account Management & Sub-Account Hierarchy
    public func rootAccounts(for type: AccountType? = nil) -> [Account] {
        accounts.filter { acc in
            let isRoot = acc.parentID == nil || !accounts.contains(where: { $0.id == acc.parentID })
            if let t = type {
                return isRoot && acc.type == t
            }
            return isRoot
        }
    }
    
    public func subAccounts(of parentID: String) -> [Account] {
        accounts.filter { $0.parentID == parentID }
    }
    
    public func hasSubAccounts(_ accountID: String) -> Bool {
        accounts.contains(where: { $0.parentID == accountID })
    }
    
    public func allDescendantAccountIDs(of parentID: String) -> [String] {
        var result: [String] = []
        let children = subAccounts(of: parentID)
        for child in children {
            result.append(child.id)
            result.append(contentsOf: allDescendantAccountIDs(of: child.id))
        }
        return result
    }
    
    public func accountHierarchyDepth(for accountID: String) -> Int {
        var depth = 0
        var current = accounts.first(where: { $0.id == accountID })
        var visited = Set<String>()
        while let pID = current?.parentID, !visited.contains(pID), let parent = accounts.first(where: { $0.id == pID }) {
            visited.insert(pID)
            depth += 1
            current = parent
        }
        return depth
    }
    
    public func accountBreadcrumb(for accountID: String) -> String {
        var parts: [String] = []
        var current = accounts.first(where: { $0.id == accountID })
        var visited = Set<String>()
        while let acc = current, !visited.contains(acc.id) {
            visited.insert(acc.id)
            parts.insert(acc.name, at: 0)
            if let pID = acc.parentID {
                current = accounts.first(where: { $0.id == pID })
            } else {
                current = nil
            }
        }
        return parts.joined(separator: " › ")
    }
    
    /// Effective balance of an account:
    /// - If the account has sub-accounts (parent container), its balance equals the sum of its included children (`total of kids = parent`).
    /// - If the account is a leaf account (no sub-accounts), its balance is its own `balance`.
    public func effectiveBalance(for accountID: String) -> Double {
        var visited = Set<String>()
        return computeEffectiveBalance(for: accountID, visited: &visited)
    }
    
    private func computeEffectiveBalance(for accountID: String, visited: inout Set<String>) -> Double {
        guard !visited.contains(accountID) else { return 0.0 }
        visited.insert(accountID)
        
        let ownBalance = accounts.first(where: { $0.id == accountID })?.balance ?? 0.0
        let children = subAccounts(of: accountID)
        guard !children.isEmpty else { return ownBalance }
        
        let childrenSum = children.reduce(0.0) { sum, child in
            guard child.includeInNetWorth else { return sum }
            return sum + computeEffectiveBalance(for: child.id, visited: &visited)
        }
        return ownBalance + childrenSum
    }
    
    /// Alias for effectiveBalance so parent total = sum of included kids everywhere
    public func cumulativeBalance(for accountID: String) -> Double {
        effectiveBalance(for: accountID)
    }
    
    /// Total Assets across all included root asset accounts (each root parent sums its included sub-accounts)
    public var totalAssets: Double {
        rootAccounts().filter { !$0.isLiability && $0.includeInNetWorth }.reduce(0.0) { sum, root in
            sum + effectiveBalance(for: root.id)
        }
    }
    
    /// Total Liabilities across all included root liability accounts (each root parent sums its included sub-accounts)
    public var totalLiabilities: Double {
        rootAccounts().filter { $0.isLiability && $0.includeInNetWorth }.reduce(0.0) { sum, root in
            sum + effectiveBalance(for: root.id)
        }
    }
    
    /// Overall Net Worth respecting the `includeInNetWorth` toggle on accounts & sub-accounts
    public var netWorth: Double {
        totalAssets - totalLiabilities
    }
    
    /// Potential parent accounts for a given debit account (prevents self-parenting or cycles, strictly debit accounts)
    public func validParentCandidates(excluding accountID: String? = nil) -> [Account] {
        let debitAccounts = accounts.filter { $0.type == .debit }
        guard let excludedID = accountID else {
            return debitAccounts.filter { accountHierarchyDepth(for: $0.id) < 2 }
        }
        let invalidIDs = Set([excludedID] + allDescendantAccountIDs(of: excludedID))
        return debitAccounts.filter { !invalidIDs.contains($0.id) && accountHierarchyDepth(for: $0.id) < 2 }
    }
    
    /// All credit card accounts
    public var creditCards: [Account] {
        accounts.filter { $0.type == .credit }
    }
    
    /// Ranks all credit cards for a given expense category by reward percentage (highest to lowest)
    public func rankedCreditCards(forCategory categoryName: String) -> [(card: Account, rate: Double, isBonus: Bool)] {
        creditCards
            .map { card in
                let info = card.rewardInfo(for: categoryName)
                return (card: card, rate: info.rate, isBonus: info.isBonus)
            }
            .sorted { a, b in
                if abs(a.rate - b.rate) > 0.0001 {
                    return a.rate > b.rate
                }
                if a.isBonus != b.isBonus {
                    return a.isBonus && !b.isBonus
                }
                return a.card.name.localizedCaseInsensitiveCompare(b.card.name) == .orderedAscending
            }
    }
    
    /// Returns the single best credit card (and any tied winners) for a given category
    public func bestCreditCard(forCategory categoryName: String) -> (card: Account, rate: Double, isBonus: Bool)? {
        rankedCreditCards(forCategory: categoryName).first
    }
    
    public func addAccount(
        name: String,
        type: AccountType,
        balance: Double = 0.0,
        institution: String = "",
        icon: String = "",
        colorHex: String = "#0A84FF",
        parentID: String? = nil,
        includeInNetWorth: Bool = true,
        accountNumber: String? = nil,
        baseRate: Double = 0.0,
        bonusRate: Double = 0.0,
        bonusCategories: [String] = [],
        bonusTiers: [CardBonusTier] = []
    ) {
        let sql = """
            INSERT INTO accounts (id, name, type, balance, institution, icon_name, color_hex, parent_id, include_in_net_worth, account_number, base_rate, bonus_rate, bonus_categories, bonus_tiers_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer? = nil
        let newID = UUID().uuidString
        let cleanCats = bonusCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ",")
        let tiersJSON: String? = {
            guard !bonusTiers.isEmpty, let data = try? JSONEncoder().encode(bonusTiers) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, newID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 4, balance)
            sqlite3_bind_text(statement, 5, institution, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 6, icon.isEmpty ? type.defaultIcon : icon, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 7, colorHex, -1, SQLITE_TRANSIENT)
            if let pID = parentID, !pID.isEmpty {
                sqlite3_bind_text(statement, 8, pID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 8)
            }
            sqlite3_bind_int(statement, 9, includeInNetWorth ? 1 : 0)
            if let accNum = accountNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !accNum.isEmpty {
                sqlite3_bind_text(statement, 10, accNum, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_double(statement, 11, baseRate)
            sqlite3_bind_double(statement, 12, bonusRate)
            if !cleanCats.isEmpty {
                sqlite3_bind_text(statement, 13, cleanCats, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 13)
            }
            if let json = tiersJSON {
                sqlite3_bind_text(statement, 14, json, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 14)
            }
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        refreshData()
    }
    
    public func updateAccount(
        id: String,
        name: String,
        type: AccountType,
        balance: Double,
        institution: String,
        parentID: String? = nil,
        includeInNetWorth: Bool = true,
        accountNumber: String? = nil,
        baseRate: Double? = nil,
        bonusRate: Double? = nil,
        bonusCategories: [String]? = nil,
        bonusTiers: [CardBonusTier]? = nil
    ) {
        let existing = accounts.first(where: { $0.id == id })
        let oldBalance = existing?.balance
        let finalBaseRate = baseRate ?? existing?.baseRate ?? 0.0
        let finalBonusRate = bonusRate ?? existing?.bonusRate ?? 0.0
        let finalBonusCats = bonusCategories ?? existing?.bonusCategories ?? []
        let finalBonusTiers = bonusTiers ?? existing?.bonusTiers ?? []
        let cleanCats = finalBonusCats.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ",")
        let tiersJSON: String? = {
            guard !finalBonusTiers.isEmpty, let data = try? JSONEncoder().encode(finalBonusTiers) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        
        let sql = "UPDATE accounts SET name = ?, type = ?, balance = ?, institution = ?, parent_id = ?, include_in_net_worth = ?, account_number = ?, base_rate = ?, bonus_rate = ?, bonus_categories = ?, bonus_tiers_json = ? WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, balance)
            sqlite3_bind_text(statement, 4, institution, -1, SQLITE_TRANSIENT)
            if let pID = parentID, !pID.isEmpty, pID != id {
                sqlite3_bind_text(statement, 5, pID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_int(statement, 6, includeInNetWorth ? 1 : 0)
            if let accNum = accountNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !accNum.isEmpty {
                sqlite3_bind_text(statement, 7, accNum, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            sqlite3_bind_double(statement, 8, finalBaseRate)
            sqlite3_bind_double(statement, 9, finalBonusRate)
            if !cleanCats.isEmpty {
                sqlite3_bind_text(statement, 10, cleanCats, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            if let json = tiersJSON {
                sqlite3_bind_text(statement, 11, json, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 11)
            }
            sqlite3_bind_text(statement, 12, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        // Log a manual balance edit as a ledger entry (excluded from spending/income analytics)
        if let oldBalance = oldBalance, abs(balance - oldBalance) > 0.001 {
            logBalanceAdjustment(accountID: id, oldBalance: oldBalance, newBalance: balance, isLiability: type.isLiability)
        }
        refreshData()
    }
    
    /// Records that an account balance was manually changed. The balance itself is already updated;
    /// this only writes the audit entry. Deleting the entry reverses the adjustment.
    private func logBalanceAdjustment(accountID: String, oldBalance: Double, newBalance: Double, isLiability: Bool) {
        let delta = newBalance - oldBalance
        let amount = isLiability ? delta : -delta
        let sql = """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, transfer_pair_id)
            VALUES (?, ?, ?, ?, 'Balance Adjustment', 'Balance Adjustment', ?, 'transfer', ?, ?);
        """
        let uuid = UUID().uuidString
        let note = String(format: "Balance manually changed from $%.2f to $%.2f", oldBalance, newBalance)
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, uuid, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dateFormatter.string(from: Date()), -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, amount)
            if let cat = getCategoryID(name: "Miscellaneous") { sqlite3_bind_int(stmt, 4, Int32(cat)) } else { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, note, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, accountID, -1, SQLITE_TRANSIENT)
            // Marker pair id (matches no real row) so deletion never touches another transfer
            sqlite3_bind_text(stmt, 7, "adjustment-\(uuid)", -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    /// Records a credit card payment funded from outside the tracked accounts (cash, someone else, etc.)
    public func recordExternalCardPayment(
        toId: String,
        amount: Double,
        payer: String? = nil,
        isRecurring: Bool = false,
        recurringFrequency: String? = nil
    ) {
        guard amount > 0 else { return }
        execute(sql: "BEGIN IMMEDIATE;")
        // Credit liability decreases by amount; entry stored as inflow (-amount)
        adjustAccountBalance(id: toId, delta: balanceDelta(accountID: toId, amount: -amount))
        let uuid = UUID().uuidString
        let dateStr = dateFormatter.string(from: Date())
        let merchantName = "Payment Received - \(payer ?? "Other")"
        let sql = """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, transfer_pair_id, is_recurring, recurring_frequency)
            VALUES (?, ?, ?, ?, ?, 'Credit Card Payment', ?, 'transfer', ?, ?, ?, ?);
        """
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, uuid, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, -amount)
            if let cat = getCategoryID(name: "Miscellaneous") { sqlite3_bind_int(stmt, 4, Int32(cat)) } else { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, merchantName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, "Paid from outside tracked accounts", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, toId, -1, SQLITE_TRANSIENT)
            // Marker pair id (matches no real row) so deletion never touches another transfer
            sqlite3_bind_text(stmt, 8, "external-\(uuid)", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 9, isRecurring ? 1 : 0)
            if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                sqlite3_bind_text(stmt, 10, rf, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        execute(sql: "COMMIT;")
        
        if isRecurring && amount > 0 {
            let freq = RecurringFrequency(rawValue: recurringFrequency ?? "Monthly") ?? .monthly
            addOrUpdateRecurringPaymentForTransaction(
                name: merchantName,
                amount: amount,
                categoryID: nil,
                categoryName: nil,
                accountID: toId,
                frequency: freq,
                startDate: dateStr,
                notes: "External payment for card",
                type: .transfer
            )
        }
        
        refreshData()
    }
    
    public func toggleAccountIncludeInNetWorth(id: String) {
        guard let current = accounts.first(where: { $0.id == id }) else { return }
        let newValue = !current.includeInNetWorth
        let sql = "UPDATE accounts SET include_in_net_worth = ? WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, newValue ? 1 : 0)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        refreshData()
    }
    
    public func renameAccount(id: String, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sql = "UPDATE accounts SET name = ? WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, trimmed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        refreshData()
    }
    
    public func updateAccountBalance(id: String, newBalance: Double) {
        let oldBalance = accounts.first(where: { $0.id == id })?.balance
        let isLiab = accounts.first(where: { $0.id == id })?.isLiability ?? false
        let sql = "UPDATE accounts SET balance = ? WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, newBalance)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        
        if let oldBalance = oldBalance, abs(newBalance - oldBalance) > 0.001 {
            logBalanceAdjustment(accountID: id, oldBalance: oldBalance, newBalance: newBalance, isLiability: isLiab)
        }
        refreshData()
    }
    
    public func adjustAccountBalance(id: String, delta: Double) {
        let sql = "UPDATE accounts SET balance = balance + ? WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, delta)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    public func transferFunds(
        fromId: String,
        toId: String,
        amount: Double,
        notes: String? = nil,
        isRecurring: Bool = false,
        recurringFrequency: String? = nil
    ) {
        guard amount > 0, fromId != toId else { return }
        execute(sql: "BEGIN IMMEDIATE;")
        
        let toIsLiability = isLiability(toId)
        let fromIsLiability = isLiability(fromId)
        
        // Outflow from source account:
        // Asset decreases by amount (-amount); Liability increases debt (+amount)
        adjustAccountBalance(id: fromId, delta: fromIsLiability ? amount : -amount)
        
        // Inflow to destination account:
        // Asset increases by amount (+amount); Liability reduces debt (-amount)
        adjustAccountBalance(id: toId, delta: toIsLiability ? -amount : amount)
        
        let fromAcc = accounts.first(where: { $0.id == fromId })?.name ?? "Account"
        let toAcc = accounts.first(where: { $0.id == toId })?.name ?? "Account"
        let transferDate = Date()
        let dateStr = dateFormatter.string(from: transferDate)
        
        let fromMerchant = toIsLiability ? "Credit Card Payment - \(toAcc)" : "Transfer to \(toAcc)"
        let toMerchant = toIsLiability ? "Payment Received - \(fromAcc)" : "Transfer from \(fromAcc)"
        let subCategory = toIsLiability ? "Credit Card Payment" : "Transfer"
        
        let uuid1 = UUID().uuidString
        let uuid2 = UUID().uuidString
        
        let insertSQL = """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, transfer_pair_id, is_recurring, recurring_frequency)
            VALUES (?, ?, ?, NULL, ?, ?, ?, 'transfer', ?, ?, ?, ?);
        """
        var stmt1: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt1, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt1, 1, uuid1, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt1, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt1, 3, amount) // Outflow
            sqlite3_bind_text(stmt1, 4, fromMerchant, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt1, 5, subCategory, -1, SQLITE_TRANSIENT)
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(stmt1, 6, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt1, 6)
            }
            sqlite3_bind_text(stmt1, 7, fromId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt1, 8, uuid2, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt1, 9, isRecurring ? 1 : 0)
            if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                sqlite3_bind_text(stmt1, 10, rf, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt1, 10)
            }
            _ = sqlite3_step(stmt1)
        }
        sqlite3_finalize(stmt1)
        
        var stmt2: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt2, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt2, 1, uuid2, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt2, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt2, 3, -amount) // Inflow
            sqlite3_bind_text(stmt2, 4, toMerchant, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt2, 5, subCategory, -1, SQLITE_TRANSIENT)
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(stmt2, 6, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt2, 6)
            }
            sqlite3_bind_text(stmt2, 7, toId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt2, 8, uuid1, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt2, 9, isRecurring ? 1 : 0)
            if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                sqlite3_bind_text(stmt2, 10, rf, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt2, 10)
            }
            _ = sqlite3_step(stmt2)
        }
        sqlite3_finalize(stmt2)
        
        execute(sql: "COMMIT;")
        
        if isRecurring && amount > 0 {
            let freq = RecurringFrequency(rawValue: recurringFrequency ?? "Monthly") ?? .monthly
            addOrUpdateRecurringPaymentForTransaction(
                name: fromMerchant,
                amount: amount,
                categoryID: nil,
                categoryName: nil,
                accountID: fromId,
                frequency: freq,
                startDate: dateStr,
                notes: notes,
                type: .transfer
            )
        }
        
        refreshData()
    }
    
    public func recordOtherTransfer(
        fromId: String,
        amount: Double,
        recipient: String,
        categoryID: Int?,
        subCategory: String? = nil,
        notes: String? = nil,
        isRecurring: Bool = false,
        recurringFrequency: String? = nil
    ) {
        guard amount > 0 else { return }
        execute(sql: "BEGIN IMMEDIATE;")
        
        // Outflow from source account:
        adjustAccountBalance(id: fromId, delta: isLiability(fromId) ? amount : -amount)
        
        let dateStr = dateFormatter.string(from: Date())
        let recipientClean = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantName = recipientClean.isEmpty ? "Other Transfer" : "Transfer: \(recipientClean)"
        let sub = (subCategory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? "Other Transfer" : subCategory!
        
        let insertSQL = """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, is_recurring, recurring_frequency)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'transfer', ?, ?, ?);
        """
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, amount) // Outflow
            if let cat = categoryID { sqlite3_bind_int(stmt, 4, Int32(cat)) } else { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, merchantName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, sub, -1, SQLITE_TRANSIENT)
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(stmt, 7, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_text(stmt, 8, fromId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 9, isRecurring ? 1 : 0)
            if let rf = recurringFrequency?.trimmingCharacters(in: .whitespacesAndNewlines), !rf.isEmpty {
                sqlite3_bind_text(stmt, 10, rf, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        execute(sql: "COMMIT;")
        
        if isRecurring && amount > 0 {
            let freq = RecurringFrequency(rawValue: recurringFrequency ?? "Monthly") ?? .monthly
            let catName = categories.first(where: { $0.id == categoryID })?.name
            addOrUpdateRecurringPaymentForTransaction(
                name: merchantName,
                amount: amount,
                categoryID: categoryID,
                categoryName: catName,
                accountID: fromId,
                frequency: freq,
                startDate: dateStr,
                notes: notes,
                type: .transfer
            )
        }
        
        refreshData()
    }
    
    // MARK: - Recurring Payments & Memberships
    private func ensureRecurringPaymentsSchema() {
        let cols = getTableColumns(tableName: "recurring_payments")
        if !cols.contains("type") {
            execute(sql: "ALTER TABLE recurring_payments ADD COLUMN type TEXT DEFAULT 'expense';")
        }
        // Backfill any recurring transactions from `transactions` table that are not yet in `recurring_payments`
        let selectSQL = """
            SELECT t.merchant, t.amount, t.category_id, c.name, t.account_id, COALESCE(t.recurring_frequency, 'Monthly'), t.date, t.notes, t.source
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.is_recurring = 1
              AND NOT EXISTS (
                  SELECT 1 FROM recurring_payments r
                  WHERE LOWER(TRIM(r.name)) = LOWER(TRIM(t.merchant))
              )
            ORDER BY t.date DESC;
        """
        var stmt: OpaquePointer? = nil
        var toInsert: [(name: String, amount: Double, catID: Int?, catName: String?, accID: String?, freq: RecurringFrequency, startStr: String, notes: String?, type: RecurringTransactionType)] = []
        var seenNames = Set<String>()
        if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let mC = sqlite3_column_text(stmt, 0),
                      let fC = sqlite3_column_text(stmt, 5),
                      let dC = sqlite3_column_text(stmt, 6),
                      let sC = sqlite3_column_text(stmt, 8) else { continue }
                let mName = String(cString: mC).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = mName.lowercased()
                guard !mName.isEmpty, !seenNames.contains(key) else { continue }
                seenNames.insert(key)
                
                let rawAmt = sqlite3_column_double(stmt, 1)
                let catID = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 2))
                let catName = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3))
                let accID = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4))
                let freq = RecurringFrequency(rawValue: String(cString: fC)) ?? .monthly
                let startStr = String(cString: dC)
                let notes: String? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 7))
                let src = String(cString: sC)
                
                // Skip inflow leg of paired internal transfers so we don't duplicate both legs
                if src == "transfer" && rawAmt < 0 && mName.lowercased().hasPrefix("transfer from ") {
                    continue
                }
                
                let rType: RecurringTransactionType = {
                    if src == "transfer" { return .transfer }
                    if rawAmt < 0 || CategoryStyle.style(for: catName ?? "").isIncome { return .income }
                    return .expense
                }()
                toInsert.append((mName, abs(rawAmt), catID, catName, accID, freq, startStr, notes, rType))
            }
        }
        sqlite3_finalize(stmt)
        
        if !toInsert.isEmpty {
            execute(sql: "BEGIN IMMEDIATE;")
            let insSQL = """
                INSERT INTO recurring_payments (id, name, amount, category_id, account_id, frequency, start_date, next_due_date, is_active, notes, type)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?);
            """
            var iStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, insSQL, -1, &iStmt, nil) == SQLITE_OK {
                for item in toInsert {
                    sqlite3_reset(iStmt)
                    sqlite3_clear_bindings(iStmt)
                    let startD = dateFormatter.date(from: item.startStr) ?? Date()
                    let nextStr = dateFormatter.string(from: calculateNextDueDate(from: startD, frequency: item.freq))
                    sqlite3_bind_text(iStmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(iStmt, 2, item.name, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(iStmt, 3, item.amount)
                    if let cID = item.catID { sqlite3_bind_int(iStmt, 4, Int32(cID)) } else { sqlite3_bind_null(iStmt, 4) }
                    if let aID = item.accID { sqlite3_bind_text(iStmt, 5, aID, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(iStmt, 5) }
                    sqlite3_bind_text(iStmt, 6, item.freq.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(iStmt, 7, item.startStr, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(iStmt, 8, nextStr, -1, SQLITE_TRANSIENT)
                    if let n = item.notes { sqlite3_bind_text(iStmt, 9, n, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(iStmt, 9) }
                    sqlite3_bind_text(iStmt, 10, item.type.dbValue, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(iStmt)
                }
            }
            sqlite3_finalize(iStmt)
            execute(sql: "COMMIT;")
        }
    }
    
    internal func loadRecurringPayments() -> [RecurringPayment] {
        let sql = """
            SELECT r.id, r.name, r.amount, r.category_id, c.name, r.account_id, r.frequency, r.start_date, r.next_due_date, r.is_active, r.notes, r.type
            FROM recurring_payments r
            LEFT JOIN categories c ON r.category_id = c.id
            ORDER BY r.is_active DESC, r.name ASC;
        """
        var statement: OpaquePointer? = nil
        var loaded: [RecurringPayment] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(statement, 0),
                      let nameC = sqlite3_column_text(statement, 1),
                      let freqC = sqlite3_column_text(statement, 6),
                      let startC = sqlite3_column_text(statement, 7),
                      let nextC = sqlite3_column_text(statement, 8) else { continue }
                
                let id = String(cString: idC)
                let name = String(cString: nameC)
                let amount = sqlite3_column_double(statement, 2)
                let categoryID = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 3))
                let categoryName = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4))
                let accountID = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 5))
                let freqStr = String(cString: freqC)
                let frequency = RecurringFrequency(rawValue: freqStr) ?? .monthly
                let startDate = String(cString: startC)
                let nextDueDate = String(cString: nextC)
                let isActive = sqlite3_column_int(statement, 9) == 1
                let notes: String? = {
                    if sqlite3_column_type(statement, 10) != SQLITE_NULL, let c = sqlite3_column_text(statement, 10) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }
                    return nil
                }()
                let rawType: String? = {
                    if sqlite3_column_count(statement) > 11 && sqlite3_column_type(statement, 11) != SQLITE_NULL, let c = sqlite3_column_text(statement, 11) {
                        return String(cString: c)
                    }
                    return nil
                }()
                let recType = RecurringTransactionType(fromRaw: rawType, categoryName: categoryName, name: name)
                
                loaded.append(RecurringPayment(
                    id: id,
                    name: name,
                    amount: amount,
                    categoryID: categoryID,
                    categoryName: categoryName,
                    accountID: accountID,
                    frequency: frequency,
                    startDate: startDate,
                    nextDueDate: nextDueDate,
                    isActive: isActive,
                    notes: notes,
                    type: recType
                ))
            }
        }
        sqlite3_finalize(statement)
        return loaded
    }
    
    public func fetchRecurringPayments() {
        let loaded = loadRecurringPayments()
        DispatchQueue.main.async {
            self.recurringPayments = loaded
        }
    }
    
    public func addRecurringPayment(
        name: String,
        amount: Double,
        categoryID: Int?,
        accountID: String?,
        frequency: RecurringFrequency,
        startDate: Date = Date(),
        notes: String? = nil,
        type: RecurringTransactionType = .expense
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, amount > 0 else { return }
        
        let startStr = dateFormatter.string(from: startDate)
        let nextDue = calculateNextDueDate(from: startDate, frequency: frequency)
        let nextDueStr = dateFormatter.string(from: nextDue)
        
        let sql = """
            INSERT INTO recurring_payments (id, name, amount, category_id, account_id, frequency, start_date, next_due_date, is_active, notes, type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?);
        """
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, cleanName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, amount)
            if let catID = categoryID { sqlite3_bind_int(stmt, 4, Int32(catID)) } else { sqlite3_bind_null(stmt, 4) }
            if let accID = accountID { sqlite3_bind_text(stmt, 5, accID, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_text(stmt, 6, frequency.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, startStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, nextDueStr, -1, SQLITE_TRANSIENT)
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(stmt, 9, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            sqlite3_bind_text(stmt, 10, type.dbValue, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        fetchRecurringPayments()
    }
    
    public func updateRecurringPayment(
        id: String,
        name: String,
        amount: Double,
        categoryID: Int?,
        accountID: String?,
        frequency: RecurringFrequency,
        isActive: Bool,
        notes: String? = nil,
        type: RecurringTransactionType? = nil
    ) {
        let resolvedType = type ?? recurringPayments.first(where: { $0.id == id })?.type ?? .expense
        let sql = """
            UPDATE recurring_payments
            SET name = ?, amount = ?, category_id = ?, account_id = ?, frequency = ?, is_active = ?, notes = ?, type = ?
            WHERE id = ?;
        """
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name.trimmingCharacters(in: .whitespacesAndNewlines), -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, amount)
            if let catID = categoryID { sqlite3_bind_int(stmt, 3, Int32(catID)) } else { sqlite3_bind_null(stmt, 3) }
            if let accID = accountID { sqlite3_bind_text(stmt, 4, accID, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, frequency.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 6, isActive ? 1 : 0)
            if let n = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                sqlite3_bind_text(stmt, 7, n, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_text(stmt, 8, resolvedType.dbValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 9, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        fetchRecurringPayments()
    }
    
    public func toggleRecurringPaymentActive(id: String) {
        let sql = "UPDATE recurring_payments SET is_active = CASE WHEN is_active = 1 THEN 0 ELSE 1 END WHERE id = ?;"
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        fetchRecurringPayments()
    }
    
    public func deleteRecurringPayment(id: String) {
        let existingName = recurringPayments.first(where: { $0.id == id })?.name
        execute(sql: "BEGIN IMMEDIATE;")
        if let name = existingName {
            var uStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE transactions SET is_recurring = 0, recurring_frequency = NULL WHERE LOWER(TRIM(merchant)) = LOWER(TRIM(?));", -1, &uStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(uStmt, 1, name, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(uStmt)
            }
            sqlite3_finalize(uStmt)
        }
        let sql = "DELETE FROM recurring_payments WHERE id = ?;"
        var stmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        execute(sql: "COMMIT;")
        refreshData()
    }
    
    public func calculateNextDueDate(from date: Date, frequency: RecurringFrequency) -> Date {
        let calendar = Calendar.current
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .biWeekly:
            return calendar.date(byAdding: .weekOfYear, value: 2, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
    
    private func addOrUpdateRecurringPaymentForTransaction(
        name: String,
        amount: Double,
        categoryID: Int?,
        categoryName: String?,
        accountID: String?,
        frequency: RecurringFrequency,
        startDate: String,
        notes: String?,
        type: RecurringTransactionType = .expense
    ) {
        if let existing = recurringPayments.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            updateRecurringPayment(
                id: existing.id,
                name: existing.name,
                amount: amount,
                categoryID: categoryID ?? existing.categoryID,
                accountID: accountID ?? existing.accountID,
                frequency: frequency,
                isActive: true,
                notes: notes ?? existing.notes,
                type: type
            )
        } else {
            let start = dateFormatter.date(from: startDate) ?? Date()
            addRecurringPayment(
                name: name,
                amount: amount,
                categoryID: categoryID,
                accountID: accountID,
                frequency: frequency,
                startDate: start,
                notes: notes,
                type: type
            )
        }
    }
    
    public func updateAccountType(id: String, type: AccountType) {
        let sql = "UPDATE accounts SET type = ?, icon_name = CASE WHEN icon_name = '' THEN ? ELSE icon_name END WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, type.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, type.defaultIcon, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        refreshData()
    }
    
    public func isLiability(_ accountID: String) -> Bool {
        var statement: OpaquePointer? = nil
        var result = false
        if sqlite3_prepare_v2(db, "SELECT type FROM accounts WHERE id = ?;", -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, accountID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_ROW, let c = sqlite3_column_text(statement, 0) {
                let typeStr = String(cString: c)
                result = (AccountType(fromRaw: typeStr) ?? AccountType(rawValue: typeStr))?.isLiability ?? false
            }
        }
        sqlite3_finalize(statement)
        return result
    }
    
    public func balanceDelta(accountID: String, amount: Double) -> Double {
        isLiability(accountID) ? amount : -amount
    }
    
    public func deleteAccount(id: String) {
        execute(sql: "BEGIN IMMEDIATE;")
        // Promote any direct child accounts to the deleted account's parent (or root)
        let currentParentID = accounts.first(where: { $0.id == id })?.parentID
        var promoteStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "UPDATE accounts SET parent_id = ? WHERE parent_id = ?;", -1, &promoteStmt, nil) == SQLITE_OK {
            if let pID = currentParentID {
                sqlite3_bind_text(promoteStmt, 1, pID, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(promoteStmt, 1)
            }
            sqlite3_bind_text(promoteStmt, 2, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(promoteStmt)
        }
        sqlite3_finalize(promoteStmt)
        
        let sql = "DELETE FROM accounts WHERE id = ?;"
        var statement: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        execute(sql: "COMMIT;")
        refreshData()
    }
    
    // MARK: - Category & Budget Management
    public func addCategory(name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty, lower != "transfer", lower != "transfers" else { return nil }
        
        let sql = "INSERT OR IGNORE INTO categories (name) VALUES (?);"
        var statement: OpaquePointer? = nil
        var categoryID: Int? = nil
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, trimmed, -1, SQLITE_TRANSIENT)
            if sqlite3_step(statement) == SQLITE_DONE {
                categoryID = getCategoryID(name: trimmed)
            }
        }
        sqlite3_finalize(statement)
        if categoryID == nil {
            categoryID = getCategoryID(name: trimmed)
        }
        refreshData()
        return categoryID
    }
    
    public func updateBudget(categoryID: Int, limit: Double) {
        let sql = """
            INSERT INTO budgets (category_id, monthly_limit)
            VALUES (?, ?)
            ON CONFLICT(category_id) DO UPDATE SET monthly_limit = excluded.monthly_limit;
        """
        var statement: OpaquePointer? = nil
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(categoryID))
            sqlite3_bind_double(statement, 2, limit)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
        refreshData()
    }
    
    public func updateBudgets(_ limits: [Int: Double]) {
        let sql = """
            INSERT INTO budgets (category_id, monthly_limit)
            VALUES (?, ?)
            ON CONFLICT(category_id) DO UPDATE SET monthly_limit = excluded.monthly_limit;
        """
        var statement: OpaquePointer? = nil
        execute(sql: "BEGIN IMMEDIATE;")
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            for (categoryID, limit) in limits {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int(statement, 1, Int32(categoryID))
                sqlite3_bind_double(statement, 2, limit)
                _ = sqlite3_step(statement)
            }
        }
        sqlite3_finalize(statement)
        execute(sql: "COMMIT;")
        refreshData()
    }
    
    public func generateCSVExport() -> String {
        var csv = "UUID,Date,Amount,Type,Category,SubCategory,Notes,Merchant,Account,Source\n"
        for tx in transactions {
            let typeStr = tx.isIncome ? "Income" : "Expense"
            let catStr = (tx.categoryName ?? "General").replacingOccurrences(of: ",", with: " ")
            let subStr = (tx.subCategory ?? "").replacingOccurrences(of: ",", with: " ")
            let notesStr = (tx.notes ?? "").replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "\n", with: " ")
            let merchStr = tx.merchant.replacingOccurrences(of: ",", with: " ")
            let accStr = (accountsByID[tx.accountID ?? ""]?.name ?? "Default").replacingOccurrences(of: ",", with: " ")
            csv += "\(tx.uuid),\(tx.dateString),\(abs(tx.amount)),\(typeStr),\(catStr),\(subStr),\(notesStr),\(merchStr),\(accStr),\(tx.source)\n"
        }
        return csv
    }
    
    // MARK: - Two-Tier Statement Import & Hash Reconciliation Engine
    
    /// Computes deterministic SHA-256 hex digest matching `scripts/process_statement.py`
    public static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Parses either a `.json` (`statement_bundle.json`) or `.csv` exported by `process_statement.py`
    public func parseStatementFile(from url: URL) throws -> ImportedStatementBundle {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }
        
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        
        if ext == "csv" {
            guard let csvText = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "StatementImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode CSV file as UTF-8 text."])
            }
            return try parseCSVBundle(csvText)
        }
        
        let decoder = JSONDecoder()
        if let bundle = try? decoder.decode(ImportedStatementBundle.self, from: data) {
            return bundle
        }
        throw NSError(domain: "StatementImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse statement bundle JSON. Make sure it was generated by process_statement.py."])
    }
    
    private func parseCSVBundle(_ csvText: String) throws -> ImportedStatementBundle {
        let lines = csvText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard lines.count > 1 else {
            throw NSError(domain: "StatementImporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "CSV file contains no transaction rows."])
        }
        
        let headerCols = splitCSVRow(lines[0]).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let dateIdx = headerCols.firstIndex(of: "date") ?? 0
        let merchIdx = headerCols.firstIndex(of: "merchant") ?? 1
        let rawMerchIdx = headerCols.firstIndex(of: "raw_merchant")
        let amountIdx = headerCols.firstIndex(of: "amount") ?? 2
        let catIdx = headerCols.firstIndex(of: "category")
        let accIdx = headerCols.firstIndex(of: "account")
        let instIdx = headerCols.firstIndex(of: "institution")
        let hintIdx = headerCols.firstIndex(of: "account_hint")
        let hashIdx = headerCols.firstIndex(of: "tx_hash")
        let transferIdx = headerCols.firstIndex(of: "is_transfer")
        
        var items: [ImportedTransactionItem] = []
        var occurrenceCounter: [String: Int] = [:]
        var totalDebits = 0.0
        var totalCredits = 0.0
        
        for line in lines.dropFirst() {
            let cols = splitCSVRow(line)
            guard cols.count > max(dateIdx, merchIdx, amountIdx) else { continue }
            let dateStr = cols[dateIdx].trimmingCharacters(in: .whitespaces)
            let merchant = cols[merchIdx].trimmingCharacters(in: .whitespaces)
            let rawMerch = rawMerchIdx != nil && cols.count > rawMerchIdx! ? cols[rawMerchIdx!] : merchant
            let amountStr = cols[amountIdx].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            guard let amount = Double(amountStr) else { continue }
            let category = (catIdx != nil && cols.count > catIdx! && !cols[catIdx!].isEmpty) ? cols[catIdx!] : "Miscellaneous"
            let accountVal: String? = (accIdx != nil && cols.count > accIdx! && !cols[accIdx!].trimmingCharacters(in: .whitespaces).isEmpty) ? cols[accIdx!].trimmingCharacters(in: .whitespaces) : nil
            let instVal: String? = (instIdx != nil && cols.count > instIdx! && !cols[instIdx!].trimmingCharacters(in: .whitespaces).isEmpty) ? cols[instIdx!].trimmingCharacters(in: .whitespaces) : nil
            let hintVal: String? = (hintIdx != nil && cols.count > hintIdx! && !cols[hintIdx!].trimmingCharacters(in: .whitespaces).isEmpty) ? cols[hintIdx!].trimmingCharacters(in: .whitespaces) : nil
            let isTransfer: Bool = {
                if let tIdx = transferIdx, cols.count > tIdx {
                    let v = cols[tIdx].lowercased()
                    return v == "true" || v == "1" || v == "yes"
                }
                return false
            }()
            
            let amountCents = Int(round(amount * 100))
            let occKey = "\(dateStr)|\(amountCents)|\(merchant.lowercased())"
            let seq = (occurrenceCounter[occKey] ?? 0) + 1
            occurrenceCounter[occKey] = seq
            
            let txHash: String = {
                if let hIdx = hashIdx, cols.count > hIdx, !cols[hIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                    return cols[hIdx].trimmingCharacters(in: .whitespaces)
                }
                return Self.sha256Hex("\(dateStr)|\(amountCents)|\(merchant.lowercased())|\(seq)")
            }()
            
            if amount > 0 { totalDebits += amount } else { totalCredits += abs(amount) }
            items.append(ImportedTransactionItem(
                date: dateStr,
                merchant: merchant,
                rawMerchant: rawMerch,
                amount: amount,
                category: category,
                txHash: txHash,
                isTransfer: isTransfer,
                account: accountVal,
                institution: instVal,
                accountHint: hintVal
            ))
        }
        
        let sortedHashes = items.map { $0.txHash }.sorted().joined(separator: "|")
        let stmtHash = Self.sha256Hex(sortedHashes)
        let dates = items.map { $0.date }.sorted()
        let firstAcc = items.compactMap { $0.account }.first
        let firstInst = items.compactMap { $0.institution }.first
        let firstHint = items.compactMap { $0.accountHint }.first
        
        return ImportedStatementBundle(
            statementHash: stmtHash,
            account: firstAcc,
            institution: firstInst,
            accountHint: firstHint,
            periodStart: dates.first,
            periodEnd: dates.last,
            openingBalance: nil,
            closingBalance: nil,
            totalDebits: totalDebits,
            totalCredits: totalCredits,
            checksumVerified: true,
            transactions: items
        )
    }
    
    /// Resolves the best-matching user `Account` from statement metadata (4-digit card ending, account label, or institution).
    public func resolveMatchingAccount(accountLabel: String?, institution: String?, accountHint: String?) -> Account? {
        // 1. Match by 4-digit card/account ending (highest precision)
        let candidateHint: String? = {
            if let h = accountHint?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
                return h
            }
            if let lbl = accountLabel, let range = lbl.range(of: #"\b\d{4}\b"#, options: .regularExpression) {
                return String(lbl[range])
            }
            return nil
        }()
        
        if let hint = candidateHint {
            if let matchByNumber = accounts.first(where: {
                ($0.accountNumber?.trimmingCharacters(in: .whitespacesAndNewlines) == hint) ||
                $0.name.contains(hint)
            }) {
                return matchByNumber
            }
        }
        
        // 2. Match by explicit account label
        if let lbl = accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !lbl.isEmpty, lbl.lowercased() != "unknown" {
            let lowLbl = lbl.lowercased()
            if let exactMatch = accounts.first(where: { $0.name.lowercased() == lowLbl }) {
                return exactMatch
            }
            if let partialMatch = accounts.first(where: {
                $0.name.lowercased().contains(lowLbl) || lowLbl.contains($0.name.lowercased())
            }) {
                return partialMatch
            }
        }
        
        // 3. Match by institution name
        if let inst = institution?.trimmingCharacters(in: .whitespacesAndNewlines), !inst.isEmpty, inst.lowercased() != "unknown" {
            let lowInst = inst.lowercased()
            if let instMatch = accounts.first(where: {
                $0.institution.lowercased().contains(lowInst) ||
                $0.name.lowercased().contains(lowInst) ||
                lowInst.contains($0.institution.lowercased())
            }) {
                return instMatch
            }
        }
        
        return nil
    }
    
    private func splitCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in row {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }
    
    /// Checks if `statementHash` is already recorded in `imported_statements`
    public func isStatementAlreadyImported(statementHash: String) -> Bool {
        var stmt: OpaquePointer? = nil
        var exists = false
        if sqlite3_prepare_v2(db, "SELECT 1 FROM imported_statements WHERE statement_hash = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, statementHash, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                exists = true
            }
        }
        sqlite3_finalize(stmt)
        return exists
    }
    
    /// Builds a `StatementReconciliationPlan` using Two-Tier Reconciliation:
    /// - Fast-path check if statement_hash or all tx_hashes are already present
    /// - Tier 1: Exact `tx_hash` lookup (`SELECT uuid FROM transactions WHERE tx_hash = ?`)
    /// - Tier 2: Fuzzy manual entry match (`tx_hash IS NULL`, `ABS(amount - ?) < 0.01`, `ABS(julianday(date) - julianday(?)) <= 3`, and compatible account)
    public func prepareReconciliationPlan(bundle: ImportedStatementBundle, targetAccountID: String? = nil) -> StatementReconciliationPlan {
        let stmtAlreadyRecorded = !bundle.statementHash.isEmpty && isStatementAlreadyImported(statementHash: bundle.statementHash)
        
        var existingHashes = Set<String>()
        var hashStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "SELECT tx_hash FROM transactions WHERE tx_hash IS NOT NULL;", -1, &hashStmt, nil) == SQLITE_OK {
            while sqlite3_step(hashStmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(hashStmt, 0) {
                    existingHashes.insert(String(cString: c))
                }
            }
        }
        sqlite3_finalize(hashStmt)
        
        // Pre-fetch all manual transactions (tx_hash IS NULL) once for O(1) in-memory fuzzy matching
        struct ManualTxCandidate {
            let uuid: String
            let merchant: String
            let dateStr: String
            let timestamp: TimeInterval
            let amount: Double
            let accountID: String?
        }
        
        var manualCandidates: [ManualTxCandidate] = []
        var manualStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, "SELECT uuid, merchant, date, amount, account_id FROM transactions WHERE tx_hash IS NULL;", -1, &manualStmt, nil) == SQLITE_OK {
            while sqlite3_step(manualStmt) == SQLITE_ROW {
                guard let uC = sqlite3_column_text(manualStmt, 0),
                      let mC = sqlite3_column_text(manualStmt, 1),
                      let dC = sqlite3_column_text(manualStmt, 2) else { continue }
                let uuid = String(cString: uC)
                let merchant = String(cString: mC)
                let dateStr = String(cString: dC)
                let amount = sqlite3_column_double(manualStmt, 3)
                let accID: String? = sqlite3_column_type(manualStmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(manualStmt, 4))
                let ts = dateFormatter.date(from: dateStr)?.timeIntervalSince1970 ?? 0
                manualCandidates.append(ManualTxCandidate(
                    uuid: uuid,
                    merchant: merchant,
                    dateStr: dateStr,
                    timestamp: ts,
                    amount: amount,
                    accountID: accID
                ))
            }
        }
        sqlite3_finalize(manualStmt)
        
        // Keep track of manual transaction UUIDs already claimed by an earlier row in this same statement
        var claimedManualUUIDs = Set<String>()
        var seenBundleHashes = Set<String>()
        var previews: [ReconciledTransactionPreview] = []
        previews.reserveCapacity(bundle.transactions.count)
        let threeDaysSeconds: TimeInterval = 3.0 * 86400.0
        
        for item in bundle.transactions {
            // Tier 1: Exact tx_hash match (against DB or duplicate within same bundle)
            if existingHashes.contains(item.txHash) || seenBundleHashes.contains(item.txHash) {
                previews.append(ReconciledTransactionPreview(
                    item: item,
                    matchType: .exactHashDuplicate,
                    matchedTransactionUUID: nil,
                    matchedMerchant: nil,
                    matchedDate: nil,
                    isSelected: false
                ))
                continue
            }
            seenBundleHashes.insert(item.txHash)
            
            // Tier 2: Fuzzy match against manually-logged entries (tx_hash IS NULL) within ±3 days and ±$0.01
            var matchedUUID: String? = nil
            var matchedMerchant: String? = nil
            var matchedDate: String? = nil
            
            if !manualCandidates.isEmpty, let itemTS = dateFormatter.date(from: item.date)?.timeIntervalSince1970 {
                var bestDiff: TimeInterval = .greatestFiniteMagnitude
                for cand in manualCandidates {
                    if claimedManualUUIDs.contains(cand.uuid) { continue }
                    if abs(cand.amount - item.amount) >= 0.01 { continue }
                    let timeDiff = abs(cand.timestamp - itemTS)
                    if timeDiff > threeDaysSeconds { continue }
                    if let targetAcc = targetAccountID, let candAcc = cand.accountID, candAcc != targetAcc {
                        continue
                    }
                    if timeDiff < bestDiff {
                        bestDiff = timeDiff
                        matchedUUID = cand.uuid
                        matchedMerchant = cand.merchant
                        matchedDate = cand.dateStr
                    }
                }
                if let uuid = matchedUUID {
                    claimedManualUUIDs.insert(uuid)
                }
            }
            
            if let uuid = matchedUUID {
                previews.append(ReconciledTransactionPreview(
                    item: item,
                    matchType: .fuzzyManualMerge,
                    matchedTransactionUUID: uuid,
                    matchedMerchant: matchedMerchant,
                    matchedDate: matchedDate,
                    isSelected: true
                ))
            } else {
                previews.append(ReconciledTransactionPreview(
                    item: item,
                    matchType: .newInsert,
                    matchedTransactionUUID: nil,
                    matchedMerchant: nil,
                    matchedDate: nil,
                    isSelected: true
                ))
            }
        }
        
        let allHashesExist = !bundle.transactions.isEmpty && previews.allSatisfy { $0.matchType == .exactHashDuplicate }
        
        // If the statement hash was recorded in imported_statements previously, but transactions
        // no longer exist in the database (e.g. user deleted transactions), purge the stale record
        // so the user can freely re-import.
        if stmtAlreadyRecorded && !allHashesExist {
            var delStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "DELETE FROM imported_statements WHERE statement_hash = ?;", -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, bundle.statementHash, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)
        }
        
        return StatementReconciliationPlan(
            bundle: bundle,
            isStatementAlreadyImported: allHashesExist,
            items: previews
        )
    }
    
    /// Executes the selected inserts & merges inside a single atomic SQLite transaction (`BEGIN IMMEDIATE ... COMMIT`).
    @discardableResult
    public func commitReconciliationPlan(
        _ plan: StatementReconciliationPlan,
        accountID: String? = nil,
        syncClosingBalance: Bool = false
    ) -> (inserted: Int, merged: Int, skipped: Int) {
        var insertedCount = 0
        var mergedCount = 0
        var skippedCount = 0
        let fallbackBundleAccID = resolveMatchingAccount(
            accountLabel: plan.bundle.account,
            institution: plan.bundle.institution,
            accountHint: plan.bundle.accountHint
        )?.id
        let defaultTargetAccID = accountID ?? fallbackBundleAccID
        
        // Cache category IDs & account liability status in memory so bulk imports of 2,500+ rows run in milliseconds
        var categoryIDCache: [String: Int] = [:]
        for cat in categories {
            categoryIDCache[cat.name.lowercased()] = cat.id
        }
        var accountLiabilityCache: [String: Bool] = [:]
        for acc in accounts {
            accountLiabilityCache[acc.id] = acc.isLiability
        }
        var resolvedAccountCache: [String: String?] = [:]
        var accountBalanceDeltas: [String: Double] = [:]
        
        execute(sql: "BEGIN IMMEDIATE;")
        
        let insertSQL = """
            INSERT OR IGNORE INTO transactions (uuid, date, amount, category_id, merchant, sub_category, notes, source, account_id, tx_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var iStmt: OpaquePointer? = nil
        sqlite3_prepare_v2(db, insertSQL, -1, &iStmt, nil)
        
        let mergeSQL = """
            UPDATE transactions
            SET date = ?, merchant = ?, tx_hash = ?, source = ?, account_id = COALESCE(account_id, ?)
            WHERE uuid = ?;
        """
        var uStmt: OpaquePointer? = nil
        sqlite3_prepare_v2(db, mergeSQL, -1, &uStmt, nil)
        
        for preview in plan.items {
            guard preview.isSelected else {
                skippedCount += 1
                continue
            }
            
            let rowAccID: String?
            if let explicitAcc = accountID {
                rowAccID = explicitAcc
            } else {
                let cacheKey = "\(preview.item.account ?? plan.bundle.account ?? "")|\(preview.item.institution ?? plan.bundle.institution ?? "")|\(preview.item.accountHint ?? plan.bundle.accountHint ?? "")"
                if let cached = resolvedAccountCache[cacheKey] {
                    rowAccID = cached ?? defaultTargetAccID
                } else {
                    let resolved = resolveMatchingAccount(
                        accountLabel: preview.item.account ?? plan.bundle.account,
                        institution: preview.item.institution ?? plan.bundle.institution,
                        accountHint: preview.item.accountHint ?? plan.bundle.accountHint
                    )?.id
                    resolvedAccountCache[cacheKey] = resolved
                    rowAccID = resolved ?? defaultTargetAccID
                }
            }
            let catKey = preview.item.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isTransferRow = preview.item.isTransfer || catKey == "transfer" || catKey == "transfers" || catKey == "credit card payment"
            let txSource = isTransferRow ? "transfer" : "csv"
            
            switch preview.matchType {
            case .exactHashDuplicate:
                skippedCount += 1
                
            case .fuzzyManualMerge:
                guard let existingUUID = preview.matchedTransactionUUID else {
                    skippedCount += 1
                    continue
                }
                var existingAccID: String? = nil
                var existingAmount: Double = preview.item.amount
                var checkStmt: OpaquePointer? = nil
                if sqlite3_prepare_v2(db, "SELECT account_id, amount FROM transactions WHERE uuid = ?;", -1, &checkStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(checkStmt, 1, existingUUID, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(checkStmt) == SQLITE_ROW {
                        if sqlite3_column_type(checkStmt, 0) != SQLITE_NULL, let c = sqlite3_column_text(checkStmt, 0) {
                            existingAccID = String(cString: c)
                        }
                        existingAmount = sqlite3_column_double(checkStmt, 1)
                    }
                }
                sqlite3_finalize(checkStmt)
                
                if let uStmt = uStmt {
                    sqlite3_reset(uStmt)
                    sqlite3_clear_bindings(uStmt)
                    sqlite3_bind_text(uStmt, 1, preview.item.date, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(uStmt, 2, preview.item.merchant, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(uStmt, 3, preview.item.txHash, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(uStmt, 4, txSource, -1, SQLITE_TRANSIENT)
                    if let accID = rowAccID {
                        sqlite3_bind_text(uStmt, 5, accID, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(uStmt, 5)
                    }
                    sqlite3_bind_text(uStmt, 6, existingUUID, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(uStmt) == SQLITE_DONE {
                        mergedCount += 1
                        if existingAccID == nil, let accID = rowAccID, !syncClosingBalance {
                            let isLiab = accountLiabilityCache[accID] ?? isLiability(accID)
                            accountLiabilityCache[accID] = isLiab
                            let delta = isLiab ? existingAmount : -existingAmount
                            accountBalanceDeltas[accID, default: 0.0] += delta
                        }
                    }
                }
                
            case .newInsert:
                let catID: Int?
                if isTransferRow {
                    catID = nil
                } else if let cachedID = categoryIDCache[catKey] {
                    catID = cachedID
                } else if let addedID = addCategoryRaw(name: preview.item.category.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    categoryIDCache[catKey] = addedID
                    catID = addedID
                } else {
                    catID = nil
                }
                
                if let iStmt = iStmt {
                    sqlite3_reset(iStmt)
                    sqlite3_clear_bindings(iStmt)
                    sqlite3_bind_text(iStmt, 1, UUID().uuidString, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(iStmt, 2, preview.item.date, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(iStmt, 3, preview.item.amount)
                    if let cID = catID {
                        sqlite3_bind_int(iStmt, 4, Int32(cID))
                    } else {
                        sqlite3_bind_null(iStmt, 4)
                    }
                    sqlite3_bind_text(iStmt, 5, preview.item.merchant, -1, SQLITE_TRANSIENT)
                    if let sub = preview.item.subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
                        sqlite3_bind_text(iStmt, 6, sub, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(iStmt, 6)
                    }
                    if let notes = preview.item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                        sqlite3_bind_text(iStmt, 7, notes, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(iStmt, 7)
                    }
                    sqlite3_bind_text(iStmt, 8, txSource, -1, SQLITE_TRANSIENT)
                    if let accID = rowAccID {
                        sqlite3_bind_text(iStmt, 9, accID, -1, SQLITE_TRANSIENT)
                    } else {
                        sqlite3_bind_null(iStmt, 9)
                    }
                    sqlite3_bind_text(iStmt, 10, preview.item.txHash, -1, SQLITE_TRANSIENT)
                    
                    if sqlite3_step(iStmt) == SQLITE_DONE && sqlite3_changes(db) > 0 {
                        insertedCount += 1
                        if let accID = rowAccID, !syncClosingBalance {
                            let isLiab = accountLiabilityCache[accID] ?? isLiability(accID)
                            accountLiabilityCache[accID] = isLiab
                            let delta = isLiab ? preview.item.amount : -preview.item.amount
                            accountBalanceDeltas[accID, default: 0.0] += delta
                        }
                    } else {
                        skippedCount += 1
                    }
                }
            }
        }
        
        sqlite3_finalize(iStmt)
        sqlite3_finalize(uStmt)
        
        // Apply accumulated balance deltas once per account
        for (accID, totalDelta) in accountBalanceDeltas where abs(totalDelta) > 0.0001 {
            adjustAccountBalance(id: accID, delta: totalDelta)
        }
        
        // Record statement in imported_statements
        let stmtSQL = """
            INSERT OR REPLACE INTO imported_statements
            (statement_hash, institution, period_start, period_end, total_debits, total_credits, tx_count)
            VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var recStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, stmtSQL, -1, &recStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(recStmt, 1, plan.bundle.statementHash, -1, SQLITE_TRANSIENT)
            if let inst = plan.bundle.institution {
                sqlite3_bind_text(recStmt, 2, inst, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(recStmt, 2)
            }
            if let ps = plan.bundle.periodStart {
                sqlite3_bind_text(recStmt, 3, ps, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(recStmt, 3)
            }
            if let pe = plan.bundle.periodEnd {
                sqlite3_bind_text(recStmt, 4, pe, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(recStmt, 4)
            }
            sqlite3_bind_double(recStmt, 5, plan.bundle.totalDebits)
            sqlite3_bind_double(recStmt, 6, plan.bundle.totalCredits)
            sqlite3_bind_int(recStmt, 7, Int32(plan.bundle.transactions.count))
            _ = sqlite3_step(recStmt)
        }
        sqlite3_finalize(recStmt)
        
        if syncClosingBalance, let accID = defaultTargetAccID, let closingBal = plan.bundle.closingBalance {
            var balStmt: OpaquePointer? = nil
            if sqlite3_prepare_v2(db, "UPDATE accounts SET balance = ? WHERE id = ?;", -1, &balStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(balStmt, 1, closingBal)
                sqlite3_bind_text(balStmt, 2, accID, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(balStmt)
            }
            sqlite3_finalize(balStmt)
        }
        
        execute(sql: "COMMIT;")
        refreshData()
        return (insertedCount, mergedCount, skippedCount)
    }
    
    // MARK: - AI Natural Language Parser
    @discardableResult
    public func parseAndLogWithAI(prompt: String, accountID: String? = nil) -> (success: Bool, merchant: String, amount: Double, category: String, isIncome: Bool) {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return (false, "", 0, "", false)
        }
        
        var parsedAmount = 0.0
        let regexPattern = #"\$?\s*([0-9]+(?:\.[0-9]{1,2})?)"#
        if let regex = try? NSRegularExpression(pattern: regexPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            if let range = Range(match.range(at: 1), in: cleaned) {
                parsedAmount = Double(cleaned[range]) ?? 0.0
            }
        }
        
        guard parsedAmount > 0 else {
            return (false, "", 0, "", false)
        }
        
        let lower = cleaned.lowercased()
        let isIncome = lower.contains("salary") || lower.contains("earned") || lower.contains("income") || lower.contains("gift") || lower.contains("received") || lower.contains("paycheck") || lower.contains("dividend")
        
        // Detect category
        var matchedCategory = isIncome ? "Salary" : "Food & Drink"
        for cat in categories {
            let catNameLower = cat.name.lowercased()
            if lower.contains(catNameLower) {
                matchedCategory = cat.name
                break
            }
        }
        // Match against user's local merchants per category
        for (catName, localMerchants) in subCategoriesByCategory {
            if localMerchants.contains(where: { !($0.isEmpty) && lower.contains($0.lowercased()) }) {
                matchedCategory = catName
                break
            }
        }
        if matchedCategory == "Food & Drink" {
            if lower.contains("grocery") || lower.contains("groceries") || lower.contains("supermarket") {
                matchedCategory = "Grocery"
            } else if lower.contains("transit") || lower.contains("gas") || lower.contains("taxi") || lower.contains("parking") {
                matchedCategory = "Transportation"
            } else if lower.contains("movie") || lower.contains("drinks") || lower.contains("game") {
                matchedCategory = "Social Life"
            } else if lower.contains("subscription") || lower.contains("membership") || lower.contains("gym") {
                matchedCategory = "Membership"
            }
        }
        
        // Detect account
        var targetAccountID = accountID
        if targetAccountID == nil {
            for acc in accounts {
                let accNameLower = acc.name.lowercased()
                let instLower = acc.institution.lowercased()
                if lower.contains(accNameLower) || lower.contains(instLower) {
                    targetAccountID = acc.id
                    break
                }
            }
            if targetAccountID == nil {
                if lower.contains("amex") {
                    targetAccountID = accounts.first(where: { $0.type == .credit || $0.name.lowercased().contains("amex") })?.id
                } else if lower.contains("cibc") {
                    targetAccountID = accounts.first(where: { $0.name.lowercased().contains("cibc") })?.id
                } else if lower.contains("scotia") {
                    targetAccountID = accounts.first(where: { $0.name.lowercased().contains("scotia") })?.id
                } else if lower.contains("bmo") {
                    targetAccountID = accounts.first(where: { $0.name.lowercased().contains("bmo") })?.id
                }
            }
            if targetAccountID == nil {
                targetAccountID = accounts.first?.id
            }
        }
        
        // Detect merchant
        var merchantName = "Quick Log"
        let merchantKeywords = ["at ", "from ", "for ", "on "]
        for kw in merchantKeywords {
            if let range = lower.range(of: kw) {
                let suffix = cleaned[range.upperBound...]
                let words = suffix.components(separatedBy: " ")
                if !words.isEmpty {
                    merchantName = words.prefix(3).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
                    break
                }
            }
        }
        
        if merchantName == "Quick Log" && !cleaned.isEmpty {
            let words = cleaned.components(separatedBy: " ")
            merchantName = words.prefix(2).joined(separator: " ")
        }
        
        // Extract hashtag if present for subCategory / tag
        var detectedSubCategory: String? = nil
        let promptTokens = cleaned.components(separatedBy: .whitespacesAndNewlines)
        for token in promptTokens where token.hasPrefix("#") && token.count > 1 {
            detectedSubCategory = String(token.dropFirst())
            break
        }
        
        let finalAmount = isIncome ? -parsedAmount : parsedAmount
        let catID = getCategoryID(name: matchedCategory)
        
        addTransaction(
            date: Date(),
            amount: finalAmount,
            categoryID: catID,
            merchant: merchantName.capitalized,
            subCategory: detectedSubCategory,
            notes: cleaned,
            source: "ai",
            accountID: targetAccountID
        )
        
        return (true, merchantName.capitalized, parsedAmount, matchedCategory, isIncome)
    }
}
