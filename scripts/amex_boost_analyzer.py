"""
amex_boost_analyzer.py

Analyzes American Express PDF statements to:
1. Extract all statement transactions and dollar amounts.
2. Dynamically extract all transactions and reward tiers from the statement's
   "Summary of Points on Accelerated Earn Rate Categories" section.
3. Identify merchants that did NOT receive a category boost (< 2x / 1x base points),
   automatically normalizing merchant brands and inferring spending categories via:
     - Existing SQLite transaction history (if a local database is present)
     - Semantic keyword & local rule inference (via process_statement)
     - Local Ollama LLM zero-shot classification (if Ollama is running locally)
4. Generate an executive-level summary and Markdown report.
"""

import logging
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pandas as pd
import pdfplumber

# Silence verbose pdfminer font/color warnings
logging.getLogger("pdfminer").setLevel(logging.ERROR)

# Import shared statement normalization/categorization and optional Ollama classifier
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
for extra_path in (SCRIPT_DIR, REPO_ROOT / "mac_tools"):
    if str(extra_path) not in sys.path:
        sys.path.insert(0, str(extra_path))

try:
    from process_statement import CANONICAL_CATEGORIES, categorize_merchant, normalize_merchant
except ImportError:
    CANONICAL_CATEGORIES = [
        "Grocery", "Food & Drink", "Social Life", "Transportation",
        "Housing & Utilities", "Personal Care", "Shopping", "Health Care",
        "Membership", "Giving", "Salary", "Investment", "Gifts/Grants", "Miscellaneous",
    ]

    def normalize_merchant(raw: str) -> str:
        clean = re.sub(r"#\d+|\b\d{3,}\b", "", raw, flags=re.I).strip()
        return clean.title() if clean else raw.strip()

    def categorize_merchant(merchant: str, raw_merchant: str, amount: float, is_transfer: bool) -> str:
        return "Miscellaneous"

try:
    from classifier import OllamaClassifier
except ImportError:
    OllamaClassifier = None


# ==============================================================================
# Part 1: Extract All Transactions from Statement
# ==============================================================================

TXN_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
TXN_MONTH_TO_NUM = {m: i + 1 for i, m in enumerate(TXN_MONTHS)}
TXN_MONTH_ALT = "|".join(TXN_MONTHS)
TXN_DATE_TOKEN = rf"(?:{TXN_MONTH_ALT})\d{{1,2}}\*?"

TXN_ROW_RE = re.compile(
    rf"^(?P<tdate>{TXN_DATE_TOKEN})\s+(?P<pdate>{TXN_DATE_TOKEN})\s+"
    rf"(?P<details>.+?)\s+(?P<amount>-?\$?[\d,]+\.\d{{2}})$"
)

TXN_DATE_WITH_YEAR = rf"(?:{TXN_MONTH_ALT})\s*\d{{1,2}},\s*\d{{4}}"
TXN_PERIOD_RE = re.compile(rf"({TXN_DATE_WITH_YEAR})\s+({TXN_DATE_WITH_YEAR})")


def txn_extract_lines(pdf_path: str) -> List[str]:
    lines = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text() or ""
            lines.extend(text.split("\n"))
    return lines


def txn_parse_date_with_year(token: str) -> date:
    m = re.match(rf"({TXN_MONTH_ALT})\s*(\d{{1,2}}),\s*(\d{{4}})", token)
    if not m:
        raise ValueError(f"Could not parse date token: {token}")
    mon, day, year = m.group(1), int(m.group(2)), int(m.group(3))
    return date(year, TXN_MONTH_TO_NUM[mon], day)


def txn_get_statement_period(lines: List[str]) -> Tuple[date, date]:
    full_text = "\n".join(lines)
    m = TXN_PERIOD_RE.search(full_text)
    if not m:
        raise ValueError("Could not find Opening Date / Closing Date on the statement.")
    return txn_parse_date_with_year(m.group(1)), txn_parse_date_with_year(m.group(2))


def txn_resolve_year(month_abbr: str, day: int, opening_date: date, closing_date: date) -> Optional[date]:
    month_num = TXN_MONTH_TO_NUM[month_abbr]
    candidate_years = {opening_date.year, closing_date.year}

    best_candidate = None
    best_distance = None
    for year in candidate_years:
        try:
            candidate = date(year, month_num, day)
        except ValueError:
            continue
        if candidate < opening_date:
            dist = (opening_date - candidate).days
        elif candidate > closing_date:
            dist = (candidate - closing_date).days
        else:
            dist = 0
        if best_distance is None or dist < best_distance:
            best_distance = dist
            best_candidate = candidate

    return best_candidate


def txn_parse_transactions(lines: List[str], opening_date: date, closing_date: date) -> List[Dict]:
    transactions = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        m = TXN_ROW_RE.match(line)
        if not m:
            continue

        tdate_raw = m.group("tdate").rstrip("*")
        pdate_raw = m.group("pdate").rstrip("*")
        t_mon, t_day = tdate_raw[:3], int(tdate_raw[3:])
        p_mon, p_day = pdate_raw[:3], int(pdate_raw[3:])

        t_date = txn_resolve_year(t_mon, t_day, opening_date, closing_date)
        p_date = txn_resolve_year(p_mon, p_day, opening_date, closing_date)

        amount = float(m.group("amount").replace("$", "").replace(",", ""))

        transactions.append({
            "Transaction Date": t_date,
            "Posting Date": p_date,
            "Details": m.group("details").strip(),
            "Amount": amount,
        })
    return transactions


def extract_amex_transactions(pdf_path: str) -> pd.DataFrame:
    lines = txn_extract_lines(pdf_path)
    opening_date, closing_date = txn_get_statement_period(lines)
    transactions = txn_parse_transactions(lines, opening_date, closing_date)
    return pd.DataFrame(transactions, columns=["Transaction Date", "Posting Date", "Details", "Amount"])


# ==============================================================================
# Part 2: Dynamically Extract Accelerated Earn Rate (Boosted) Categories
# ==============================================================================

SECTION_START = "Summary of Points on Accelerated Earn Rate Categories"
SECTION_END_TOTAL_PREFIX = "Points Earned on Accelerated Categories"
SECTION_HARD_STOP = "Points Redeemed"

CATEGORY_HEADER_RE = re.compile(
    r"^(?P<rate>\d+\s*pts/\$1\s+.+?)\s+\$(?P<sub_purchases>[\d,]+\.\d{2})\s+(?P<sub_points>[\d,]+)$"
)
TXN_LINE_RE = re.compile(
    r"^(?P<date>\d{2}/\d{2}/\d{4})\s+(?P<description>.+?)\s+\$(?P<purchases>[\d,]+\.\d{2})\s+(?P<points>[\d,]+)$"
)
GRAND_TOTAL_RE = re.compile(rf"^{re.escape(SECTION_END_TOTAL_PREFIX)}\s+([\d,]+)$")


def parse_accelerated_categories(lines: List[str]) -> Tuple[List[Dict], Optional[int]]:
    try:
        start_idx = next(i for i, l in enumerate(lines) if l.strip() == SECTION_START)
    except StopIteration:
        return [], None

    section_lines = []
    grand_total_points = None
    for line in lines[start_idx + 1:]:
        stripped = line.strip()
        m = GRAND_TOTAL_RE.match(stripped)
        if m:
            grand_total_points = int(m.group(1).replace(",", ""))
            break
        if stripped.startswith(SECTION_HARD_STOP):
            break
        section_lines.append(stripped)

    blocks = []
    current_block = None
    last_txn = None

    for line in section_lines:
        if not line:
            continue

        m = CATEGORY_HEADER_RE.match(line)
        if m:
            current_block = {
                "category": m.group("rate").strip(),
                "sub_purchases": float(m.group("sub_purchases").replace(",", "")),
                "sub_points": int(m.group("sub_points").replace(",", "")),
                "transactions": [],
            }
            blocks.append(current_block)
            last_txn = None
            continue

        m = TXN_LINE_RE.match(line)
        if m:
            txn = {
                "Date": datetime.strptime(m.group("date"), "%m/%d/%Y").date(),
                "Description": m.group("description").strip(),
                "Qualifying Purchases": float(m.group("purchases").replace(",", "")),
                "No. of Points": int(m.group("points").replace(",", "")),
            }
            if current_block is not None:
                current_block["transactions"].append(txn)
            last_txn = txn
            continue

        if line == "Date Description Qualifying Purchases No. of Points":
            continue
        if last_txn is not None:
            last_txn["Description"] = (last_txn["Description"] + " " + line).strip()

    return blocks, grand_total_points


def extract_amex_points_categories(pdf_path: str) -> pd.DataFrame:
    lines = txn_extract_lines(pdf_path)
    blocks, _ = parse_accelerated_categories(lines)

    rows = []
    for b in blocks:
        for t in b["transactions"]:
            purchases = t["Qualifying Purchases"]
            points = t["No. of Points"]
            multiplier = round(points / purchases, 2) if purchases > 0 else 0.0
            rows.append({
                "Date": t["Date"],
                "Category Block": b["category"],
                "Description": t["Description"],
                "Qualifying Purchases": purchases,
                "No. of Points": points,
                "Multiplier": multiplier,
            })

    return pd.DataFrame(rows, columns=[
        "Date", "Category Block", "Description", "Qualifying Purchases", "No. of Points", "Multiplier"
    ])


# ==============================================================================
# Part 3: Automatic Merchant Brand Normalization & Category Inference
# ==============================================================================

class AutoCategoryResolver:
    """
    Automatically resolves merchant brands and spending categories without
    hardcoded merchant lists by combining:
      1. Existing SQLite transaction history (if a local DB exists)
      2. Statement pattern & keyword inference (process_statement.categorize_merchant)
      3. Local Ollama LLM zero-shot classification (if Ollama is reachable)
    """

    def __init__(self, db_path: Optional[str] = None):
        self.brand_category_cache: Dict[str, str] = {}
        self.db_merchant_categories: Dict[str, str] = {}
        self._load_db_history(db_path)
        self.classifier = OllamaClassifier() if OllamaClassifier is not None else None
        self._ollama_available: Optional[bool] = None

    def _load_db_history(self, db_path: Optional[str]) -> None:
        candidate_paths = []
        if db_path:
            candidate_paths.append(Path(db_path))
        env_db = os.environ.get("BUDGET_DB_PATH")
        if env_db:
            candidate_paths.append(Path(env_db))
        candidate_paths.extend([
            REPO_ROOT / "budget_tracker.sqlite",
            REPO_ROOT / "mac_tools" / "budget_tracker.sqlite",
        ])

        for path in candidate_paths:
            if path.exists() and path.is_file():
                try:
                    conn = sqlite3.connect(str(path))
                    cur = conn.cursor()
                    cur.execute(
                        """
                        SELECT LOWER(TRIM(t.merchant)), c.name, COUNT(*) as cnt
                        FROM transactions t
                        JOIN categories c ON t.category_id = c.id
                        WHERE c.name IS NOT NULL AND c.name != 'Miscellaneous'
                        GROUP BY LOWER(TRIM(t.merchant)), c.name
                        ORDER BY cnt DESC
                        """
                    )
                    for merch_lower, cat_name, _ in cur.fetchall():
                        if merch_lower and merch_lower not in self.db_merchant_categories:
                            self.db_merchant_categories[merch_lower] = cat_name
                    conn.close()
                    break
                except Exception:
                    pass

    @staticmethod
    def extract_brand_name(raw_description: str) -> str:
        """Normalizes raw statement text into a clean merchant brand name."""
        cleaned = normalize_merchant(raw_description)
        # Strip trailing domain extensions or generic corporate suffixes for cleaner grouping
        cleaned = re.sub(r"\b(?:Inc|Ltd|Llc|Corp|Co|Ca|Com)\b\.?", "", cleaned, flags=re.I)
        cleaned = re.sub(r"\s+", " ", cleaned).strip(" -.,*/")
        return cleaned if cleaned else raw_description.strip().title()

    def infer_category(self, brand: str, raw_description: str, amount: float) -> str:
        """Automatically determines the category for a merchant."""
        cache_key = brand.lower()
        if cache_key in self.brand_category_cache:
            return self.brand_category_cache[cache_key]

        # 1. Check historical SQLite database categorizations
        if cache_key in self.db_merchant_categories:
            cat = self.db_merchant_categories[cache_key]
            self.brand_category_cache[cache_key] = cat
            return cat

        for db_merch, db_cat in self.db_merchant_categories.items():
            if len(db_merch) >= 4 and (db_merch in cache_key or cache_key in db_merch):
                self.brand_category_cache[cache_key] = db_cat
                return db_cat

        # 2. Run semantic & local-rule categorization from process_statement
        inferred = categorize_merchant(brand, raw_description, amount, is_transfer=False)
        if inferred and inferred != "Miscellaneous":
            self.brand_category_cache[cache_key] = inferred
            return inferred

        # 3. Try local Ollama LLM zero-shot classification if available
        if self.classifier is not None and self._ollama_available is not False:
            llm_cat = self.classifier.classify_merchant(brand, CANONICAL_CATEGORIES)
            if llm_cat is None:
                # Avoid repeated timeouts if local Ollama server is not running
                self._ollama_available = False
            else:
                self._ollama_available = True
                if llm_cat in CANONICAL_CATEGORIES:
                    self.brand_category_cache[cache_key] = llm_cat
                    return llm_cat

        # 4. Fallback to Miscellaneous
        self.brand_category_cache[cache_key] = "Miscellaneous"
        return "Miscellaneous"

    @staticmethod
    def recommend_alternative_card(category: str) -> str:
        """Recommends an optimal card strategy dynamically from the inferred category."""
        cat_lower = category.lower()
        if any(k in cat_lower for k in ["utility", "utilities", "housing", "membership"]):
            return "Recurring Bill Card (e.g., 4% Recurring Cashback)"
        if any(k in cat_lower for k in ["grocery", "food", "dining"]):
            return "No-FX / Grocery & Dining Visa or Mastercard (2%–4%)"
        if any(k in cat_lower for k in ["transport", "travel"]):
            return "Travel / Transit & Gas Rewards Card (2%–3%)"
        if any(k in cat_lower for k in ["health", "personal care"]):
            return "Pharmacy / Drugstore Bonus Card or Flat 2% Card"
        return "Flat 2% All-Purpose Cashback Card (Visa / Mastercard)"


def analyze_amex_boost(pdf_folder_or_file: str, db_path: Optional[str] = None) -> Dict:
    """Comprehensive Amex statement boost analysis with automatic categorization."""
    target = Path(pdf_folder_or_file)
    if target.is_file():
        files = [target]
    elif target.is_dir():
        files = sorted(target.glob("*.pdf"))
    else:
        raise FileNotFoundError(f"Path not found: {pdf_folder_or_file}")

    all_tx_dfs = []
    all_pts_dfs = []

    for f in files:
        try:
            df_tx = extract_amex_transactions(str(f))
            df_tx["Statement"] = f.stem
            all_tx_dfs.append(df_tx)
        except Exception:
            pass

        try:
            df_pts = extract_amex_points_categories(str(f))
            df_pts["Statement"] = f.stem
            all_pts_dfs.append(df_pts)
        except Exception:
            pass

    merged_tx = pd.concat(all_tx_dfs, ignore_index=True) if all_tx_dfs else pd.DataFrame(
        columns=["Transaction Date", "Posting Date", "Details", "Amount", "Statement"]
    )
    merged_pts = pd.concat(all_pts_dfs, ignore_index=True) if all_pts_dfs else pd.DataFrame(
        columns=["Date", "Category Block", "Description", "Qualifying Purchases", "No. of Points", "Multiplier", "Statement"]
    )

    # Filter out internal payments, fee refunds, and credits (only real purchases)
    if not merged_tx.empty:
        purchases_df = merged_tx[
            (merged_tx["Amount"] > 0)
            & (~merged_tx["Details"].str.contains(
                r"PAYMENT RECEIVED|MEMBERSHIP FEE|POINTS REDEMPTION", case=False, na=False
            ))
        ].copy()
    else:
        purchases_df = merged_tx.copy()

    # Match boosted transactions (multiplier >= 2x)
    boosted_pts_set = (
        set(merged_pts["Description"].dropna().str.strip().str.upper().unique())
        if not merged_pts.empty
        else set()
    )

    non_boosted_rows = []
    boosted_rows = []

    for _, row in purchases_df.iterrows():
        raw_detail = str(row["Details"]).strip()
        upper_detail = raw_detail.upper()

        is_boosted = (upper_detail in boosted_pts_set) or any(
            p and p in upper_detail for p in boosted_pts_set
        )
        if is_boosted:
            boosted_rows.append(row)
        else:
            non_boosted_rows.append(row)

    non_boosted_df = pd.DataFrame(non_boosted_rows) if non_boosted_rows else pd.DataFrame(columns=purchases_df.columns)
    boosted_df = pd.DataFrame(boosted_rows) if boosted_rows else pd.DataFrame(columns=purchases_df.columns)

    # Automatically normalize brands and infer categories for non-boosted merchants
    resolver = AutoCategoryResolver(db_path=db_path)
    grouped_merchants = defaultdict(lambda: {"count": 0, "total_spend": 0.0, "categories": Counter(), "examples": set()})

    for _, row in non_boosted_df.iterrows():
        raw_name = str(row["Details"])
        amt = float(row["Amount"])
        brand = resolver.extract_brand_name(raw_name)
        category = resolver.infer_category(brand, raw_name, amt)

        grouped_merchants[brand]["count"] += 1
        grouped_merchants[brand]["total_spend"] += amt
        grouped_merchants[brand]["categories"][category] += 1
        if len(grouped_merchants[brand]["examples"]) < 3:
            grouped_merchants[brand]["examples"].add(raw_name)

    final_grouped_merchants = {}
    for brand, info in grouped_merchants.items():
        top_cat = info["categories"].most_common(1)[0][0] if info["categories"] else "Miscellaneous"
        final_grouped_merchants[brand] = {
            "count": info["count"],
            "total_spend": info["total_spend"],
            "category": top_cat,
            "recommended_card": resolver.recommend_alternative_card(top_cat),
            "examples": info["examples"],
        }

    # Dynamically aggregate accelerated category tiers directly from the statement blocks
    tier_breakdown = []
    if not merged_pts.empty:
        grouped_tiers = (
            merged_pts.groupby("Category Block", as_index=False)
            .agg(
                qualifying_spend=("Qualifying Purchases", "sum"),
                total_points=("No. of Points", "sum"),
                tx_count=("Qualifying Purchases", "count"),
            )
            .sort_values(by="qualifying_spend", ascending=False)
        )
        for _, trow in grouped_tiers.iterrows():
            q_spend = float(trow["qualifying_spend"])
            t_pts = int(trow["total_points"])
            eff_mult = round(t_pts / q_spend, 1) if q_spend > 0 else 0.0
            tier_breakdown.append({
                "label": str(trow["Category Block"]),
                "tx_count": int(trow["tx_count"]),
                "spend": q_spend,
                "points": t_pts,
                "multiplier": eff_mult,
            })

    total_spend = float(purchases_df["Amount"].sum()) if not purchases_df.empty else 0.0
    boosted_spend = float(boosted_df["Amount"].sum()) if not boosted_df.empty else 0.0
    non_boosted_spend = float(non_boosted_df["Amount"].sum()) if not non_boosted_df.empty else 0.0

    return {
        "statement_count": len(files),
        "total_transactions": len(purchases_df),
        "total_spend": total_spend,
        "boosted_count": len(boosted_df),
        "boosted_spend": boosted_spend,
        "non_boosted_count": len(non_boosted_df),
        "non_boosted_spend": non_boosted_spend,
        "tier_breakdown": tier_breakdown,
        "grouped_merchants": final_grouped_merchants,
        "non_boosted_df": non_boosted_df,
        "merged_pts": merged_pts,
    }


def format_report_markdown(results: Dict) -> str:
    """Renders a structured, clean markdown executive report."""
    total_tx = results["total_transactions"]
    total_spend = results["total_spend"]
    boosted_spend = results["boosted_spend"]
    non_boosted_spend = results["non_boosted_spend"]
    boosted_pct = (boosted_spend / total_spend * 100) if total_spend > 0 else 0.0
    non_boosted_pct = (non_boosted_spend / total_spend * 100) if total_spend > 0 else 0.0

    lines = [
        "# American Express Reward Boost Audit",
        f"**Statements Analyzed**: {results['statement_count']} monthly statements\n",
        "## 1. Spend & Rewards Summary\n",
        "| Metric | Count | Total Spend | % of Total Spend | Effective Reward Tier |",
        "| :--- | :---: | :---: | :---: | :--- |",
        f"| **Boosted Category Purchases** | {results['boosted_count']} | ${boosted_spend:,.2f} | {boosted_pct:.1f}% | **Accelerated (2x – 5x)** |",
    ]

    tier_breakdown = results.get("tier_breakdown", [])
    for idx, tier in enumerate(tier_breakdown):
        branch = "└─" if idx == len(tier_breakdown) - 1 else "├─"
        pct = (tier["spend"] / total_spend * 100) if total_spend > 0 else 0.0
        lines.append(
            f"| {branch} {tier['label']} | {tier['tx_count']} | ${tier['spend']:,.2f} | {pct:.1f}% | ~{tier['multiplier']:.1f} pts / $1 |"
        )

    lines.extend([
        f"| **Non-Boosted Purchases** | {results['non_boosted_count']} | ${non_boosted_spend:,.2f} | {non_boosted_pct:.1f}% | **1x Base Only (< 2x)** |",
        f"| **Total Purchases** | **{total_tx}** | **${total_spend:,.2f}** | **100.0%** | — |\n",
        "## 2. Non-Boosted (<2x) Merchants Requiring Alternative Cards\n",
        "These merchants only earn the base **1 point per $1** rate. Categories and alternative card strategies below are inferred automatically.\n",
        "| Merchant / Brand | Inferred Category | Tx Count | Total Spend ($) | Recommended Card Strategy |",
        "| :--- | :--- | :---: | :---: | :--- |",
    ])

    sorted_groups = sorted(
        results["grouped_merchants"].items(),
        key=lambda x: x[1]["total_spend"],
        reverse=True,
    )
    for brand, info in sorted_groups:
        lines.append(
            f"| **{brand}** | {info['category']} | {info['count']} | ${info['total_spend']:,.2f} | {info['recommended_card']} |"
        )

    return "\n".join(lines)


if __name__ == "__main__":
    path_arg = sys.argv[1] if len(sys.argv) > 1 else "../statements"
    print("\n=======================================================")
    print("      AMEX REWARD BOOST ANALYZER")
    print("=======================================================\n")
    print(f"Scanning AMEX statements in: {path_arg} ...")

    res = analyze_amex_boost(path_arg)
    report_md = format_report_markdown(res)
    print("\n" + report_md)

    out_file = Path("amex_boost_report.md")
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(report_md)
    print(f"\n[+] Full report saved to: {out_file.resolve()}\n")
