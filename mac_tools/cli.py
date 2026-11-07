import os
import sys
import argparse
from db import DatabaseManager
from classifier import OllamaClassifier
from ingest import CSVIngestor, clean_merchant_name
from sync import SQLiteSyncHelper

# Color constants for terminal formatting
GREEN = "\033[92m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
RED = "\033[91m"
BOLD = "\033[1m"
RESET = "\033[0m"

def print_banner():
    print(f"""
{CYAN}{BOLD}====================================================
      LOCAL-FIRST PERSONAL FINANCE CLI
===================================================={RESET}""")

def handle_ingest(args):
    if not os.path.exists(args.csv_file):
        print(f"{RED}Error: CSV file not found at '{args.csv_file}'{RESET}")
        return

    db = DatabaseManager()
    classifier = OllamaClassifier(model_name=args.model)
    ingestor = CSVIngestor(db, classifier)

    print(f"\n{CYAN}Parsing CSV: {args.csv_file}...{RESET}")
    csv_txs = ingestor.parse_csv(args.csv_file)
    print(f"Found {len(csv_txs)} transactions in CSV.")

    categories = db.get_categories()
    category_names = [c["name"] for c in categories]
    category_id_map = {c["name"]: c["id"] for c in categories}

    imported_count = 0
    duplicate_count = 0
    skipped_count = 0

    print(f"\n{CYAN}Starting reconciliation...{RESET}")
    for idx, tx in enumerate(csv_txs):
        print(f"\n----------------------------------------------------")
        print(f"Transaction {idx + 1}/{len(csv_txs)}")
        print(f"Date:     {tx['date']}")
        print(f"Merchant: {BOLD}{tx['merchant']}{RESET}")
        
        # Display amount: positive represents expense, negative represents income
        amount_val = tx['amount']
        if amount_val > 0:
            amount_str = f"{RED}${amount_val:,.2f} (Expense){RESET}"
        else:
            amount_str = f"{GREEN}${abs(amount_val):,.2f} (Income){RESET}"
        print(f"Amount:   {amount_str}")

        # Check reconciliation/duplicates
        status, match = ingestor.reconcile_transaction(tx)
        if status == 'duplicate':
            print(f"{YELLOW}Duplicate detected!{RESET} Matches db record:")
            print(f"  DB Merchant: {match['merchant']} | Date: {match['date']} | Category: {match['category_name']}")
            print("Skipping automatically.")
            duplicate_count += 1
            continue

        # Classify with Ollama
        suggestion = None
        print(f"Running LLM classification ({args.model})...")
        suggestion = classifier.classify_merchant(tx['merchant'], category_names)
        
        if suggestion:
            print(f"Suggested category: {GREEN}{suggestion}{RESET}")
            choice = input(f"Accept suggestion? [Y/n/skip/manual]: ").strip().lower()
        else:
            print(f"{YELLOW}Ollama classification unavailable or returned no match.{RESET}")
            choice = 'm'

        chosen_category_id = None

        if choice in ('', 'y', 'yes'):
            chosen_category_id = category_id_map[suggestion]
        elif choice == 'skip':
            print("Skipping transaction.")
            skipped_count += 1
            continue
        else:
            # Manual category selection
            print("\nSelect Category:")
            for i, cat_name in enumerate(category_names):
                print(f"  {i+1}: {cat_name}")
            print(f"  0: Create a new category")
            print(f"  s: Skip this transaction")
            
            while True:
                sel = input("Enter selection index: ").strip()
                if sel == 's':
                    chosen_category_id = None
                    break
                elif sel == '0':
                    new_cat_name = input("Enter name for new category: ").strip()
                    if new_cat_name:
                        new_cat_id = db.add_category(new_cat_name)
                        # Refresh categories
                        categories = db.get_categories()
                        category_names = [c["name"] for c in categories]
                        category_id_map = {c["name"]: c["id"] for c in categories}
                        chosen_category_id = new_cat_id
                        print(f"Created category '{new_cat_name}'")
                        break
                    else:
                        print("Category name cannot be empty.")
                else:
                    try:
                        sel_idx = int(sel)
                        if 1 <= sel_idx <= len(category_names):
                            cat_name = category_names[sel_idx - 1]
                            chosen_category_id = category_id_map[cat_name]
                            break
                        else:
                            print(f"Please enter a number between 0 and {len(category_names)}.")
                    except ValueError:
                        print("Invalid selection.")
            
            if sel == 's':
                print("Skipping transaction.")
                skipped_count += 1
                continue

        # Save to database
        db.add_transaction(
            date=tx['date'],
            amount=tx['amount'],
            category_id=chosen_category_id,
            merchant=tx['merchant'],
            source='csv'
        )
        print(f"{GREEN}✓ Transaction imported!{RESET}")
        imported_count += 1

    db.close()
    
    print(f"\n{BOLD}===================================================={RESET}")
    print(f"Inflow/Outflow parsing done.")
    print(f"  Imported:  {GREEN}{imported_count}{RESET}")
    print(f"  Duplicates: {YELLOW}{duplicate_count}{RESET}")
    print(f"  Skipped:    {skipped_count}")
    print(f"{BOLD}===================================================={RESET}")

def handle_sync(args):
    db_path = args.db_path or os.environ.get("BUDGET_DB_PATH", "budget_tracker.sqlite")
    bundle_id = args.bundle_id or os.environ.get("IOS_BUNDLE_ID", "com.localfirst.BudgetTracker")
    
    sync_helper = SQLiteSyncHelper(mac_db_path=db_path, bundle_id=bundle_id)
    ios_path = sync_helper.locate_ios_simulator_db()
    
    if not ios_path:
        print(f"{RED}Error: Could not locate booted iOS simulator with app '{bundle_id}' installed.{RESET}")
        print("Please ensure the simulator is running and the app is installed.")
        sys.exit(1)
        
    print(f"{GREEN}Found iOS App Database sandbox at:{RESET}")
    print(f"  {ios_path}\n")
    
    confirm = input("Proceed with two-way sync merge? [Y/n]: ").strip().lower()
    if confirm in ('', 'y', 'yes'):
        sync_helper.merge_databases(ios_path)
    else:
        print("Sync cancelled.")

def handle_list_tx(args):
    db = DatabaseManager()
    txs = db.get_transactions(limit=args.limit)
    db.close()

    print(f"\n{CYAN}{BOLD}Recent Transactions (Last {args.limit}):{RESET}")
    print(f"{'Date':<12} | {'Merchant':<25} | {'Amount':<10} | {'Category':<15} | {'Source':<8}")
    print("-" * 80)
    for tx in txs:
        cat = tx["category_name"] or "None"
        src = tx["source"]
        amt = tx["amount"]
        if amt > 0:
            amt_str = f"{RED}${amt:,.2f}{RESET}"
        else:
            amt_str = f"{GREEN}${abs(amt):,.2f}{RESET}"
        print(f"{tx['date']:<12} | {tx['merchant'][:25]:<25} | {amt_str:<19} | {cat:<15} | {src:<8}")

def handle_list_budgets(args):
    db = DatabaseManager()
    budgets = db.get_budgets()
    db.close()

    print(f"\n{CYAN}{BOLD}Category Budgets & Limits:{RESET}")
    print(f"{'Category ID':<12} | {'Category Name':<20} | {'Monthly Limit':<15}")
    print("-" * 55)
    for b in budgets:
        print(f"{b['category_id']:<12} | {b['category_name']:<20} | ${b['monthly_limit']:,.2f}")

def handle_set_budget(args):
    db = DatabaseManager()
    cat = db.get_category_by_name(args.category)
    if not cat:
        # Create category if it doesn't exist
        cat_id = db.add_category(args.category)
        print(f"Created new category: {args.category}")
    else:
        cat_id = cat["id"]
        
    db.set_budget(cat_id, args.limit)
    print(f"{GREEN}Budget for '{args.category}' updated to ${args.limit:,.2f}{RESET}")
    db.close()

def handle_amex_boost(args):
    scripts_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts"))
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    try:
        from amex_boost_analyzer import analyze_amex_boost, format_report_markdown
    except ImportError as e:
        print(f"{RED}Error loading Amex Boost Analyzer: {e}{RESET}")
        return

    print(f"\n{CYAN}Running Amex Boost Analysis on: {args.path}...{RESET}\n")
    results = analyze_amex_boost(args.path)
    report_md = format_report_markdown(results)
    print(report_md)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(report_md)
        print(f"\n{GREEN}[+] Saved audit report to: {args.output}{RESET}")

def main():
    print_banner()
    parser = argparse.ArgumentParser(description="Budget Tracker & Reconciliation CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Ingest command
    ingest_parser = subparsers.add_parser("ingest", help="Ingest transactions from CSV file")
    ingest_parser.add_argument("csv_file", help="Path to CSV file")
    ingest_parser.add_argument("--model", default="llama3", help="Ollama LLM model name (default: llama3)")

    # Sync command
    sync_parser = subparsers.add_parser("sync", help="Two-way sync with booted iOS Simulator database")
    sync_parser.add_argument("--db-path", default="budget_tracker.sqlite", help="Local SQLite file path")
    sync_parser.add_argument("--bundle-id", default="com.localfirst.BudgetTracker", help="iOS App Bundle identifier")

    # Amex Boost Analyzer
    boost_parser = subparsers.add_parser("amex-boost", help="Audit Amex statement PDFs for non-accelerated (<2x) merchants")
    boost_parser.add_argument("path", help="Path to Amex statement PDF or folder of PDFs")
    boost_parser.add_argument("--output", "-o", default="amex_boost_report.md", help="Markdown report output path")

    # List transactions
    list_tx_parser = subparsers.add_parser("list-tx", help="List recent transactions")
    list_tx_parser.add_argument("--limit", type=int, default=20, help="Number of records to show")

    # List budgets
    subparsers.add_parser("list-budgets", help="List budget limits for all categories")

    # Set budget
    set_budget_parser = subparsers.add_parser("set-budget", help="Set monthly budget limit for a category")
    set_budget_parser.add_argument("category", help="Name of the category")
    set_budget_parser.add_argument("limit", type=float, help="Monthly limit in dollars")

    args = parser.parse_args()

    if args.command == "ingest":
        handle_ingest(args)
    elif args.command == "sync":
        handle_sync(args)
    elif args.command == "amex-boost":
        handle_amex_boost(args)
    elif args.command == "list-tx":
        handle_list_tx(args)
    elif args.command == "list-budgets":
        handle_list_budgets(args)
    elif args.command == "set-budget":
        handle_set_budget(args)

if __name__ == "__main__":
    main()
