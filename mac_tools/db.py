import sqlite3
import os
import uuid
from typing import List, Dict, Tuple, Optional

DEFAULT_CATEGORIES = [
    "Housing",
    "Groceries",
    "Dining",
    "Transport",
    "Utilities",
    "Entertainment",
    "Shopping",
    "Income",
    "Miscellaneous"
]

class DatabaseManager:
    def __init__(self, db_path: Optional[str] = None):
        resolved_path = db_path or os.environ.get("BUDGET_DB_PATH", "budget_tracker.sqlite")
        self.db_path = resolved_path
        self.conn = sqlite3.connect(resolved_path)
        # Enable foreign key support
        self.conn.execute("PRAGMA foreign_keys = ON;")
        self.conn.execute("PRAGMA journal_mode = WAL;")
        self.conn.row_factory = sqlite3.Row
        self.create_tables()
        self.seed_categories()

    def create_tables(self):
        cursor = self.conn.cursor()
        
        # Categories Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT UNIQUE NOT NULL
            );
        """)

        # Budgets Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS budgets (
                category_id INTEGER PRIMARY KEY,
                monthly_limit REAL NOT NULL,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
            );
        """)

        # Accounts Table (shared schema with the iOS app)
        cursor.execute("""
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
                bonus_tiers_json TEXT
            );
        """)

        # Transactions Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS transactions (
                uuid TEXT PRIMARY KEY,
                date TEXT NOT NULL, -- Format: YYYY-MM-DD
                amount REAL NOT NULL, -- Negative for income/credits, Positive for expenses/debits
                category_id INTEGER,
                merchant TEXT NOT NULL,
                source TEXT CHECK(source IN ('manual', 'csv', 'ai', 'transfer')) NOT NULL,
                account_id TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
            );
        """)

        # Migrate databases created before account_id existed or without 'transfer' allowed
        table_sql_row = cursor.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='transactions';").fetchone()
        table_sql = table_sql_row[0] if table_sql_row else ""
        if "account_id" not in table_sql or "'transfer'" not in table_sql:
            cursor.execute("ALTER TABLE transactions RENAME TO transactions_legacy;")
            cursor.execute("""
                CREATE TABLE transactions (
                    uuid TEXT PRIMARY KEY,
                    date TEXT NOT NULL,
                    amount REAL NOT NULL,
                    category_id INTEGER,
                    merchant TEXT NOT NULL,
                    source TEXT CHECK(source IN ('manual', 'csv', 'ai', 'transfer')) NOT NULL,
                    account_id TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
                    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
                );
            """)
            has_acc = "account_id" in table_sql
            acc_col = "account_id" if has_acc else "NULL"
            cursor.execute(f"""
                INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id, created_at)
                SELECT uuid, date, amount, category_id, merchant, source, {acc_col}, created_at FROM transactions_legacy;
            """)
            cursor.execute("DROP TABLE transactions_legacy;")

        cursor.execute("CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);")
        
        self.conn.commit()

    def seed_categories(self):
        cursor = self.conn.cursor()
        for cat in DEFAULT_CATEGORIES:
            cursor.execute("INSERT OR IGNORE INTO categories (name) VALUES (?);", (cat,))
        self.conn.commit()

    def get_categories(self) -> List[Dict]:
        cursor = self.conn.cursor()
        cursor.execute("SELECT id, name FROM categories ORDER BY name;")
        return [dict(row) for row in cursor.fetchall()]

    def get_category_by_name(self, name: str) -> Optional[Dict]:
        cursor = self.conn.cursor()
        cursor.execute("SELECT id, name FROM categories WHERE name = ?;", (name,))
        row = cursor.fetchone()
        return dict(row) if row else None

    def add_category(self, name: str) -> int:
        cursor = self.conn.cursor()
        try:
            cursor.execute("INSERT INTO categories (name) VALUES (?);", (name,))
            self.conn.commit()
            return cursor.lastrowid
        except sqlite3.IntegrityError:
            row = self.get_category_by_name(name)
            return row["id"] if row else -1

    def get_budgets(self) -> List[Dict]:
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT c.id as category_id, c.name as category_name, COALESCE(b.monthly_limit, 0.0) as monthly_limit
            FROM categories c
            LEFT JOIN budgets b ON c.id = b.category_id
            ORDER BY c.name;
        """)
        return [dict(row) for row in cursor.fetchall()]

    def set_budget(self, category_id: int, limit: float):
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO budgets (category_id, monthly_limit)
            VALUES (?, ?)
            ON CONFLICT(category_id) DO UPDATE SET monthly_limit = excluded.monthly_limit;
        """, (category_id, limit))
        self.conn.commit()

    def add_transaction(self, 
                        date: str, 
                        amount: float, 
                        category_id: Optional[int], 
                        merchant: str, 
                        source: str = 'csv',
                        account_id: Optional[str] = None,
                        tx_uuid: Optional[str] = None) -> str:
        if not tx_uuid:
            tx_uuid = str(uuid.uuid4())
        
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(uuid) DO UPDATE SET
                date = excluded.date,
                amount = excluded.amount,
                category_id = excluded.category_id,
                merchant = excluded.merchant,
                source = excluded.source,
                account_id = excluded.account_id;
        """, (tx_uuid, date, amount, category_id, merchant, source, account_id))
        self.conn.commit()
        return tx_uuid

    def transfer_funds(self, from_account_id: str, to_account_id: str, amount: float, date: Optional[str] = None) -> Tuple[str, str]:
        import datetime
        if not date:
            date = datetime.date.today().strftime("%Y-%m-%d")
        
        cursor = self.conn.cursor()
        cursor.execute("SELECT id, name FROM accounts WHERE id = ?;", (from_account_id,))
        row_from = cursor.fetchone()
        from_name = row_from["name"] if row_from else "Account"

        cursor.execute("SELECT id, name FROM accounts WHERE id = ?;", (to_account_id,))
        row_to = cursor.fetchone()
        to_name = row_to["name"] if row_to else "Account"

        misc_cat = self.get_category_by_name("Miscellaneous")
        cat_id = misc_cat["id"] if misc_cat else None

        outflow_uuid = str(uuid.uuid4())
        inflow_uuid = str(uuid.uuid4())

        cursor.execute("""
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id)
            VALUES (?, ?, ?, ?, ?, 'transfer', ?);
        """, (outflow_uuid, date, amount, cat_id, f"Transfer to {to_name}", from_account_id))

        cursor.execute("""
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id)
            VALUES (?, ?, ?, ?, ?, 'transfer', ?);
        """, (inflow_uuid, date, -amount, cat_id, f"Transfer from {from_name}", to_account_id))

        cursor.execute("UPDATE accounts SET balance = balance - ? WHERE id = ?;", (amount, from_account_id))
        cursor.execute("UPDATE accounts SET balance = balance + ? WHERE id = ?;", (amount, to_account_id))

        self.conn.commit()
        return outflow_uuid, inflow_uuid

    def get_transactions(self, limit: int = 100) -> List[Dict]:
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT t.uuid, t.date, t.amount, t.category_id, c.name as category_name, t.merchant, t.source, t.account_id, t.created_at
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            ORDER BY t.date DESC, t.created_at DESC
            LIMIT ?;
        """, (limit,))
        return [dict(row) for row in cursor.fetchall()]

    def get_transactions_by_date_range(self, start_date: str, end_date: str) -> List[Dict]:
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT t.uuid, t.date, t.amount, t.category_id, c.name as category_name, t.merchant, t.source, t.account_id
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE t.date BETWEEN ? AND ?
            ORDER BY t.date DESC;
        """, (start_date, end_date))
        return [dict(row) for row in cursor.fetchall()]

    def get_transactions_fuzzy_match(self, amount: float, date: str, date_margin_days: int = 2) -> List[Dict]:
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT t.uuid, t.date, t.amount, t.category_id, c.name as category_name, t.merchant, t.source
            FROM transactions t
            LEFT JOIN categories c ON t.category_id = c.id
            WHERE abs(julianday(t.date) - julianday(?)) <= ?
              AND abs(t.amount - ?) < 0.01;
        """, (date, date_margin_days, amount))
        return [dict(row) for row in cursor.fetchall()]

    def close(self):
        self.conn.close()
