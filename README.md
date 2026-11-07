# Local-First Personal Finance & Budget Tracker

A **100% local-first, zero-cloud** personal finance ecosystem built for **iOS (SwiftUI + WidgetKit)** and **macOS (Python CLI & Statement Parsing Engine)**.

Track spending across multiple bank accounts and credit cards, optimize credit card reward multipliers, parse PDF/CSV bank statements completely offline, and automatically categorize transactions using a local LLM via [Ollama](https://ollama.com).

---

## Key Features

- **100% Local-First Privacy**: All accounts, transactions, and category budgets live inside a local SQLite database (`WAL` mode enabled). Zero cloud servers, zero Plaid/bank credential linking, and zero telemetry.
- **Native iOS App & Interactive Widgets**:
  - **Dashboard & Analytics**: Real-time monthly net cash flow, spending pace vs. budget, category donut charts, and historical trend comparisons.
  - **Apple Wallet–Style Accounts & Credit Card Optimizer**: Manage Chequing, Savings, Credit Card, and Investment accounts with custom base and bonus reward tiers (e.g., `5x`, `3x`, `2x` categories) and instant "Best Card to Use" recommendations.
  - **Home Screen Widgets (`WidgetKit`)**: Glanceable small and medium iOS widgets displaying budget remaining, category progress, and top spending categories.
  - **Apple Shortcuts & Siri (`AppIntents`)**: Log expenses hands-free from iOS Wallet tap automations or Siri voice commands.
- **Offline Bank & Credit Card Statement Parser (`scripts/process_statement.py`)**:
  - Extracts, normalizes, and deduplicates transactions from multi-page PDF and CSV statements using `pdfplumber` and deterministic `SHA-256` transaction & statement hashes.
  - Automatically detects internal transfers and credit card payments so they don't artificially inflate your spending totals.
- **Automated AMEX Reward Boost Analyzer (`scripts/amex_boost_analyzer.py`)**:
  - Audits American Express PDF statements by comparing all purchases against the statement's *"Summary of Points on Accelerated Earn Rate Categories"* section.
  - Automatically normalizes merchant brands and infers spending categories (via local SQLite history, semantic patterns, and local Ollama zero-shot classification) to flag `< 2x` (1x base) purchases that should be routed to a higher-earning card.
- **macOS CLI & Two-Way Simulator Sync (`mac_tools/cli.py`)**:
  - Interactive CSV ingestion with fuzzy duplicate reconciliation (`±2 days`, exact amount matching), local Ollama AI classification, budget management, and 2-way SQLite merge with a booted Xcode iOS Simulator.

---

## Tech Stack

| Layer | Technology |
| :--- | :--- |
| **iOS Application** | Swift 5, SwiftUI, Swift Charts, AppIntents (Shortcuts) |
| **iOS Extensions** | WidgetKit (`BudgetTrackerWidget`) |
| **Database** | SQLite3 (`sqlite3` C API on iOS / `sqlite3` standard library on Python, `WAL` mode) |
| **macOS CLI & Statement Engine** | Python 3.10+, `pdfplumber`, `pandas` |
| **Local AI Categorization** | [Ollama](https://ollama.com) REST API (`llama3` default, strictly localhost) |

---

## Repository Structure

```text
Budget_app/
├── ios_app/
│   ├── BudgetTracker.xcodeproj/     # Xcode project (iOS App + Widget Extension)
│   ├── BudgetTracker/               # SwiftUI views, SQLite manager, statement importer, AppIntents
│   └── BudgetTrackerWidget/         # Home screen WidgetKit extension
├── mac_tools/
│   ├── cli.py                       # Interactive macOS CLI for ingestion, budgets, and iOS sync
│   ├── db.py                        # Shared SQLite schema & database manager
│   ├── ingest.py                    # CSV parser, merchant cleaner, and fuzzy deduplicator
│   ├── classifier.py                # Local Ollama LLM zero-shot merchant classifier
│   ├── sync.py                      # Two-way SQLite sync with booted iOS Simulator
│   ├── mock_bank.csv                # Synthetic sample transactions for immediate testing
│   └── test_tools.py                # Unit test suite for DB, ingestion, and sync
├── scripts/
│   ├── process_statement.py         # Multi-bank PDF/CSV statement parser & SHA-256 deduplicator
│   ├── amex_boost_analyzer.py       # Automated AMEX accelerated points (<2x vs 2x–5x) auditor
│   └── requirements.txt             # Python dependencies (pdfplumber, pandas)
├── .env.example                     # Safe template for optional local environment overrides
├── .gitignore                       # Security-first ignore rules blocking PDFs, CSVs, and SQLite DBs
└── LICENSE                          # MIT License
```

---

## Getting Started

### Prerequisites

- **macOS** with **Xcode 15+** (for building and running the iOS app / Simulator)
- **Python 3.10+**
- **[Ollama](https://ollama.com)** *(Optional — used for automatic offline AI merchant categorization)*

### 1. Clone & Set Up Python Environment

```bash
git clone https://github.com/Arinn-27/budget-tracker.git
cd budget-tracker

python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
```

### 2. Configure Environment Variables (Optional)

Copy the example environment file if you want to customize the local SQLite database path, Ollama model, or iOS bundle ID:

```bash
cp .env.example .env
```

If you want local AI merchant classification during CSV ingestion or reward analysis, start Ollama in the background:

```bash
ollama pull llama3
ollama serve
```

### 3. Test with Synthetic Sample Data (`mac_tools`)

A synthetic dataset (`mac_tools/mock_bank.csv`) with fictional transactions (e.g., *"Acme Coffee Shop - $4.50"*) is included so you can test ingestion, budget tracking, and database creation immediately:

```bash
# Run the unit test suite
python3 mac_tools/test_tools.py

# Ingest the synthetic sample CSV interactively
python3 mac_tools/cli.py ingest mac_tools/mock_bank.csv

# View imported transactions and category budgets
python3 mac_tools/cli.py list-tx --limit 20
python3 mac_tools/cli.py list-budgets
```

### 4. Parse Statements & Run the AMEX Reward Boost Analyzer

Place your PDF or CSV statements inside a local git-ignored folder (such as `statements/`):

```bash
# Parse PDF/CSV statements into a deduplicated JSON/CSV bundle or SQLite DB
python3 scripts/process_statement.py statements/ --json-out statement_bundle.json --csv-out statement_bundle.csv

# Audit AMEX PDF statements for non-boosted (<2x) merchants with automatic category inference
python3 scripts/amex_boost_analyzer.py statements/
```

### 5. Run the iOS App in Xcode

1. Open `ios_app/BudgetTracker.xcodeproj` in **Xcode**.
2. In **Signing & Capabilities**, select your personal Apple Developer Team (or *"Sign to Run Locally"* for the iOS Simulator).
3. Select an iPhone Simulator and press **Cmd + R** to build and run.
4. *(Optional)* With the Simulator booted, sync your macOS SQLite database directly into the iOS app sandbox:
   ```bash
   python3 mac_tools/cli.py sync
   ```

---

## Privacy & Security Architecture

- **Strictly Offline Storage**: Financial data is stored exclusively in local `.sqlite` files on your device and Mac. No external API calls are ever made with your financial data (Ollama queries run strictly against `http://localhost:11434`).
- **Git-Ignored Financial Artifacts**: `.gitignore` blocks all `.sqlite`, `.db`, `.pdf`, `.csv` (except `mac_tools/mock_bank.csv`), `.xlsx`, `.ofx`, `.qfx`, and statement bundle files from ever being staged or committed.
- **Private Merchant Rules**: Custom personal merchant normalizations or local business mappings can be placed in `scripts/local_merchant_rules.json` or `ios_app/BudgetTracker/local_merchants.json`—both are automatically loaded at runtime if present and strictly ignored by Git.

---

## License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for full details.
