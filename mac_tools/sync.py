import os
import sqlite3
import subprocess
import shutil
from typing import Optional, Dict

class SQLiteSyncHelper:
    def __init__(self, mac_db_path: str = "budget_tracker.sqlite", bundle_id: str = "com.localfirst.BudgetTracker"):
        self.mac_db_path = mac_db_path
        self.bundle_id = bundle_id

    def locate_ios_simulator_db(self) -> Optional[str]:
        """
        Attempts to locate the SQLite database inside the booted iOS simulator's sandbox.
        """
        try:
            # Query xcrun simctl for the booted device's app container data directory
            cmd = ["xcrun", "simctl", "get_app_container", "booted", self.bundle_id, "data"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            container_path = result.stdout.strip()
            
            # The database is expected in the Documents folder
            db_path = os.path.join(container_path, "Documents", "budget_tracker.sqlite")
            return db_path
        except subprocess.CalledProcessError:
            # Simulator is not booted or app is not installed
            return None
        except Exception:
            return None

    def merge_databases(self, ios_db_path: str):
        """
        Performs a two-way sync/merge between the Mac database and the iOS database.
        """
        print(f"Syncing:\n  Mac DB: {os.path.abspath(self.mac_db_path)}\n  iOS DB: {ios_db_path}")
        
        if not os.path.exists(self.mac_db_path):
            # If Mac DB doesn't exist, copy from iOS
            print("Mac database does not exist. Copying from iOS sandbox...")
            shutil.copy2(ios_db_path, self.mac_db_path)
            return

        # Connect to both databases
        conn_mac = sqlite3.connect(self.mac_db_path)
        conn_mac.execute("PRAGMA foreign_keys = ON;")
        conn_mac.row_factory = sqlite3.Row
        
        conn_ios = sqlite3.connect(ios_db_path)
        conn_ios.execute("PRAGMA foreign_keys = ON;")
        conn_ios.row_factory = sqlite3.Row

        try:
            # Step 1: Merge Categories
            # Get categories from both
            cursor_mac = conn_mac.cursor()
            cursor_ios = conn_ios.cursor()
            
            cursor_mac.execute("SELECT id, name FROM categories;")
            categories_mac = {row["name"]: row["id"] for row in cursor_mac.fetchall()}
            
            cursor_ios.execute("SELECT id, name FROM categories;")
            categories_ios = {row["name"]: row["id"] for row in cursor_ios.fetchall()}

            # Insert missing categories in Mac
            for name in categories_ios:
                if name not in categories_mac:
                    cursor_mac.execute("INSERT INTO categories (name) VALUES (?);", (name,))
                    categories_mac[name] = cursor_mac.lastrowid
            conn_mac.commit()

            # Insert missing categories in iOS
            for name in categories_mac:
                if name not in categories_ios:
                    cursor_ios.execute("INSERT INTO categories (name) VALUES (?);", (name,))
                    categories_ios[name] = cursor_ios.lastrowid
            conn_ios.commit()

            # Re-read category mappings to ensure complete alignment
            cursor_mac.execute("SELECT id, name FROM categories;")
            categories_mac = {row["name"]: row["id"] for row in cursor_mac.fetchall()}
            categories_mac_rev = {row["id"]: row["name"] for row in cursor_mac.fetchall()} # wait, refetching
            
            # Let's rebuild name-to-id maps and id-to-name maps
            cursor_mac.execute("SELECT id, name FROM categories;")
            mac_rows = cursor_mac.fetchall()
            cat_name_to_mac_id = {r["name"]: r["id"] for r in mac_rows}
            mac_id_to_name = {r["id"]: r["name"] for r in mac_rows}

            cursor_ios.execute("SELECT id, name FROM categories;")
            ios_rows = cursor_ios.fetchall()
            cat_name_to_ios_id = {r["name"]: r["id"] for r in ios_rows}
            ios_id_to_name = {r["id"]: r["name"] for r in ios_rows}

            # Step 2: Merge Transactions
            # Get transactions from both
            cursor_mac.execute("SELECT uuid, date, amount, category_id, merchant, source, account_id FROM transactions;")
            txs_mac = {row["uuid"]: dict(row) for row in cursor_mac.fetchall()}
            
            cursor_ios.execute("SELECT uuid, date, amount, category_id, merchant, source, account_id FROM transactions;")
            txs_ios = {row["uuid"]: dict(row) for row in cursor_ios.fetchall()}

            # Insert missing iOS transactions into Mac
            for tx_uuid, tx in txs_ios.items():
                if tx_uuid not in txs_mac:
                    # Map category ID from iOS to Mac
                    cat_name = ios_id_to_name.get(tx["category_id"]) if tx["category_id"] is not None else None
                    mac_cat_id = cat_name_to_mac_id.get(cat_name) if cat_name else None
                    
                    cursor_mac.execute("""
                        INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id)
                        VALUES (?, ?, ?, ?, ?, ?, ?);
                    """, (tx_uuid, tx["date"], tx["amount"], mac_cat_id, tx["merchant"], tx["source"], tx.get("account_id")))
            conn_mac.commit()

            # Insert missing Mac transactions into iOS
            for tx_uuid, tx in txs_mac.items():
                if tx_uuid not in txs_ios:
                    # Map category ID from Mac to iOS
                    cat_name = mac_id_to_name.get(tx["category_id"]) if tx["category_id"] is not None else None
                    ios_cat_id = cat_name_to_ios_id.get(cat_name) if cat_name else None
                    
                    cursor_ios.execute("""
                        INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id)
                        VALUES (?, ?, ?, ?, ?, ?, ?);
                    """, (tx_uuid, tx["date"], tx["amount"], ios_cat_id, tx["merchant"], tx["source"], tx.get("account_id")))
            conn_ios.commit()

            # Step 3: Merge Budgets
            # Fetch budgets from both
            cursor_mac.execute("SELECT category_id, monthly_limit FROM budgets;")
            budgets_mac = {mac_id_to_name[row["category_id"]]: row["monthly_limit"] for row in cursor_mac.fetchall() if row["category_id"] in mac_id_to_name}
            
            cursor_ios.execute("SELECT category_id, monthly_limit FROM budgets;")
            budgets_ios = {ios_id_to_name[row["category_id"]]: row["monthly_limit"] for row in cursor_ios.fetchall() if row["category_id"] in ios_id_to_name}

            # Update budgets in both databases.
            # We take the union of category limits. If a limit exists in both, we let the iOS limit take precedence
            # as it represents the on-the-go modifications.
            merged_budgets = {}
            all_cat_names = set(budgets_mac.keys()).union(set(budgets_ios.keys()))
            for name in all_cat_names:
                limit_mac = budgets_mac.get(name)
                limit_ios = budgets_ios.get(name)
                
                if limit_ios is not None:
                    merged_budgets[name] = limit_ios
                elif limit_mac is not None:
                    merged_budgets[name] = limit_mac

            # Write merged budgets to Mac
            for name, limit in merged_budgets.items():
                cat_id = cat_name_to_mac_id[name]
                cursor_mac.execute("""
                    INSERT INTO budgets (category_id, monthly_limit)
                    VALUES (?, ?)
                    ON CONFLICT(category_id) DO UPDATE SET monthly_limit = excluded.monthly_limit;
                """, (cat_id, limit))
            conn_mac.commit()

            # Write merged budgets to iOS
            for name, limit in merged_budgets.items():
                cat_id = cat_name_to_ios_id[name]
                cursor_ios.execute("""
                    INSERT INTO budgets (category_id, monthly_limit)
                    VALUES (?, ?)
                    ON CONFLICT(category_id) DO UPDATE SET monthly_limit = excluded.monthly_limit;
                """, (cat_id, limit))
            conn_ios.commit()

            print("Database merge completed successfully.")
            
        except Exception as e:
            conn_mac.rollback()
            conn_ios.rollback()
            print(f"Error merging databases: {e}")
            raise e
        finally:
            conn_mac.close()
            conn_ios.close()
