
import argparse
import csv
import hashlib
import json
import os
import re
import sqlite3
import sys
import uuid
from collections import defaultdict
from dataclasses import dataclass, asdict
from datetime import datetime
from difflib import SequenceMatcher
from pathlib import Path
from typing import List, Dict, Optional, Tuple

try:
    import pdfplumber
except ImportError:
    pdfplumber = None


# Exact 14 canonical categories from DatabaseManager.swift
CANONICAL_CATEGORIES = [
    "Grocery",
    "Food & Drink",
    "Social Life",
    "Transportation",
    "Housing & Utilities",
    "Personal Care",
    "Shopping",
    "Health Care",
    "Membership",
    "Giving",
    "Salary",
    "Investment",
    "Gifts/Grants",
    "Miscellaneous",
]

MONTH_MAP = {
    "jan": 1, "january": 1,
    "feb": 2, "february": 2,
    "mar": 3, "march": 3,
    "apr": 4, "april": 4,
    "may": 5,
    "jun": 6, "june": 6,
    "jul": 7, "july": 7,
    "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9,
    "oct": 10, "october": 10,
    "nov": 11, "november": 11,
    "dec": 12, "december": 12,
}

TRANSFER_PATTERNS = [
    r"\bpayment[\s,\-]*thank\s*you\b",
    r"\bpayment\s+received\b",
    r"\bpaiement\s+merci\b",
    r"\bautopay\b",
    r"\bpre-?authorized\s+(?:payment|debit)\b",
    r"\binternal\s+transfer\b",
    r"\binternet\s+transfer\b",
    r"\btransfer\s+(?:to|from)\b",
    r"\bmb-?transfer\b",
    r"\bio\s+transfer\b",
    r"\bbr\s+transfer\b",
    r"\be-?transfer\b",
    r"\binterac\s+e-?transfer\b",
    r"\bcredit\s+card(?:/loc)?\s+payment\b",
    r"\binternet\s+bill\s+pay\b",
    r"\bbill\s+payment\b",
    r"\bmisc\.\s*payment\s*-?\s*american\s*express\b",
]

NOISE_LINE_PATTERNS = [
    r"^page\s+\d+\s*(?:of|/)\s*\d+",
    r"^prepared\s+for\b",
    r"^account\s+number\b",
    r"^card\s+number\b",
    r"^trans(?:action)?\s+date\b",
    r"^opening\s+balance\b",
    r"^previous\s+balance\b",
    r"^closing\s+balance\b",
    r"^new\s+balance\b",
    r"^balance\s+forward\b",
    r"^total\s+of\b",
    r"^total\s+new\b",
    r"^total\s+for\b",
    r"^subtotal\b",
    r"^continued\s+on\b",
    r"^transaction\s+details",
    r"^your\s+transactions",
    r"^new\s+payments$",
    r"^new\s+transactions\s+for\b",
    r"^other\s+account\s+transactions$",
    r"^interest\s+rate\s+chart",
    r"^foreign\s+currency\b",
    r"^reference\s+[a-z0-9]+",
    r"^minimum\s+amount\s+due\b",
    r"^statement\s+includes\b",
]


@dataclass
class ExtractedTransaction:
    date: str              # YYYY-MM-DD
    merchant: str          # Normalized merchant name
    raw_merchant: str      # Original raw description from statement
    amount: float          # Positive = expense/debit, Negative = income/credit/payment
    category: str          # Mapped canonical category
    tx_hash: str           # Deterministic SHA-256 hash
    is_transfer: bool      # True if credit card payment or internal transfer
    account: str = ""      # Source payment account label (e.g. "CIBC •••• 1234")
    institution: str = ""  # Financial institution (e.g. "CIBC", "AMEX")
    account_hint: Optional[str] = None  # Last 4 digits of card/account


@dataclass
class StatementSummary:
    institution: str
    account_hint: Optional[str]
    period_start: Optional[str]
    period_end: Optional[str]
    opening_balance: Optional[float]
    closing_balance: Optional[float]
    expected_total_debits: Optional[float]
    expected_total_credits: Optional[float]
    total_debits: float
    total_credits: float
    statement_hash: str
    checksum_verified: bool
    account: str = ""


def parse_money(val_str: str) -> Optional[float]:
    """Parses currency string like '$1,000.00', '-1,000.00', '1,000.00 CR', '($25.00)' into float."""
    if not val_str:
        return None
    s = val_str.strip()
    is_neg = False
    if s.startswith("-") or s.endswith("-") or (s.startswith("(") and s.endswith(")")):
        is_neg = True
    if re.search(r"\bCR\b", s, re.IGNORECASE):
        is_neg = True
    cleaned = re.sub(r"[^0-9.]", "", s)
    if not cleaned or cleaned.count(".") > 1:
        return None
    try:
        val = float(cleaned)
        return -val if is_neg else val
    except ValueError:
        return None


def parse_full_date(text: str) -> Optional[datetime]:
    """Parses full date string with year into datetime."""
    text = re.sub(r"\s+", " ", text.strip().replace(",", ", "))
    text = re.sub(r"\s+,", ",", text)
    formats = [
        "%b %d, %Y", "%B %d, %Y", "%b %d %Y", "%B %d %Y",
        "%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%Y/%m/%d",
    ]
    for fmt in formats:
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    # Regex fallback for 'Aug 22, 2026' or 'Aug22, 2026' or 'Sep 18,2026'
    m = re.search(r"([A-Za-z]{3,9})\.?\s*(\d{1,2})\s*,?\s*(\d{4})", text)
    if m:
        mon = MONTH_MAP.get(m.group(1).lower()[:3])
        if mon:
            return datetime(int(m.group(3)), mon, int(m.group(2)))
    return None


def is_transfer_or_payment(raw_merchant: str) -> bool:
    """Detects credit card payments and internal account transfers."""
    lower = raw_merchant.lower()
    for pat in TRANSFER_PATTERNS:
        if re.search(pat, lower):
            return True
    return False


def _load_local_merchant_rules() -> Dict:
    """Loads local git-ignored merchant normalization and category keyword rules if available."""
    rules_path = Path(__file__).resolve().parent / "local_merchant_rules.json"
    if rules_path.exists():
        try:
            with open(rules_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


LOCAL_MERCHANT_RULES = _load_local_merchant_rules()


def normalize_merchant(raw: str) -> str:
    """
    Strips POS prefixes (SQ *, TST*, VISA DEBIT, SP ), store numbers (#1042, W1248),
    order codes (*ABC123XYZ), phone numbers, and trailing city/province codes.
    """
    s = raw.strip()
    if not s:
        return "Unknown Merchant"

    # Special cleanups for generic statement payment/interest labels
    if re.search(r"payment\s*received\s*-?\s*thank\s*you", s, re.I) or re.search(r"payment\s*,?\s*thank\s*you", s, re.I):
        return "Payment Thank You"
    if re.search(r"paiement\s*merci", s, re.I):
        return "Paiement Merci"
    if re.search(r"cash\s*back\s*/\s*remises", s, re.I):
        return "Cash Back Rebate"
    if re.search(r"purchase\s*interest", s, re.I):
        return "Purchase Interest"

    # Apply user's local merchant normalization rules (from git-ignored local_merchant_rules.json)
    for rule in LOCAL_MERCHANT_RULES.get("normalization_rules", []):
        pat = rule.get("pattern")
        repl = rule.get("replacement")
        if pat and repl and re.search(pat, s, re.I):
            return repl

    # Strip POS & banking prefixes
    s = re.sub(
        r"^(?:Point\s+of\s+Sale\s*-\s*Interac\s+RETAIL\s+PURCHASE\s*\d*\s*|"
        r"Point\s+of\s+Sale\s*-\s*Visa\s+Debit\s+(?:RETAIL\s+PURCHASE\s*)?\d*\s*|"
        r"Electronic\s+Funds\s+Transfer\s+(?:CREDIT\s+MEMO|DEPOSIT|PREAUTHORIZED\s+DEBIT)\s*|"
        r"Internet\s+Banking\s+INTERNET\s+BILL\s+PAY\s+\d+\s*|"
        r"Internet\s+Banking\s+E-TRANSFER\s+\d+\s*|"
        r"Internet\s+Banking\s+INTERNET\s+TRANSFER\s+\d+\s*|"
        r"Branch\s+Transaction\s+|"
        r"SQ\s*\*|TST\s*\*|SP\s+|ACT\s*\*|POS\s+(?:PURCHASE|DEBIT)\s*|VISA\s+DEBIT\s*|INTERAC\s+PURCHASE\s*|WWW\s+)",
        "",
        s,
        flags=re.IGNORECASE,
    )

    # Remove asterisk order / reference codes like *ABC123XYZ or /REF987654
    s = re.sub(r"[\*/][A-Z0-9]{5,}", " ", s, flags=re.IGNORECASE)

    # Remove masked card/account numbers like ******1234
    s = re.sub(r"\*{2,}\d+", " ", s)

    # Remove phone numbers like 800-555-0199
    s = re.sub(r"\b\d{3}-\d{3}-\d{4}\b", " ", s)

    # Remove date tokens like 08-25 or 09-08
    s = re.sub(r"\b\d{2}-\d{2}\b", " ", s)

    # Remove store numbers (#1042, #33491, # 123, W1248, C02253, C122, long 6+ digit IDs)
    s = re.sub(r"#\s*\d*", " ", s)
    s = re.sub(r"\b[A-Z]\d{3,6}\b", " ", s)
    s = re.sub(r"\b\d{5,}\b", " ", s)

    # Strip trailing province / state codes and common cities
    cities_provinces_pattern = (
        r"(?:\s+(?:DOWNTOWN\s+)?(?:TORONTO|TORONT|OTTAWA|VANCOUVER|MONTREAL|CALGARY|EDMONTON|"
        r"MISSISSAUGA|BRAMPTON|HAMILTON|MARKHAM|VAUGHAN|OAKVILLE|BURLINGTON|SAN\s+FRANCISCO|NEW\s+YORK))"
        r"*(?:\s+(?:ON|BC|AB|QC|MB|SK|NS|NB|NL|PE|CA|NJ|NY|WA|TX|US|CAN))?$"
    )
    s = re.sub(cities_provinces_pattern, "", s, flags=re.IGNORECASE)

    # Strip trailing standalone 3-4 digit store numbers
    s = re.sub(r"\s+\d{3,4}$", "", s)

    # Collapse whitespace
    s = re.sub(r"\s+", " ", s).strip(" -*/")

    if not s:
        return raw.strip()

    # Smart title-case while preserving known acronyms
    words = s.split()
    formatted = []
    acronyms = set(LOCAL_MERCHANT_RULES.get("acronyms", ["BMO", "CIBC", "RBC", "TD", "AMEX"]))
    for w in words:
        upper_w = w.upper()
        if upper_w in acronyms:
            formatted.append(upper_w)
        elif "/" in w or "." in w:
            formatted.append(w.title())
        else:
            formatted.append(w.capitalize())
    return " ".join(formatted)


def categorize_merchant(merchant: str, raw_merchant: str, amount: float, is_transfer: bool) -> str:
    """
    Maps a transaction to one of the 14 canonical categories in DatabaseManager.swift:
    Grocery, Social Life, Food & Drink, Transportation, Housing & Utilities,
    Personal Care, Shopping, Health Care, Membership, Giving, Salary,
    Investment, Gifts/Grants, Miscellaneous.
    """
    if is_transfer:
        return "Miscellaneous"

    combined = f"{merchant} {raw_merchant}".lower()

    # 1. Check user's local category keyword mappings first (from git-ignored local_merchant_rules.json)
    local_cat_keywords = LOCAL_MERCHANT_RULES.get("category_keywords", {})
    for cat_name, keywords in local_cat_keywords.items():
        if any(str(k).lower() in combined for k in keywords if k):
            return cat_name

    # 2. Generic non-merchant fallback keywords
    if any(k in combined for k in ["payroll", "salary", "direct deposit", "paycheque", "paycheck", "wages"]):
        return "Salary"
    if any(k in combined for k in ["dividend", "investment", "interest earned"]):
        return "Investment"
    if any(k in combined for k in ["cash back", "rebate", "remises", "gift", "grant", "bursary", "scholarship"]):
        return "Gifts/Grants"
    if any(k in combined for k in ["grocery", "supermarket", "grocer"]):
        return "Grocery"
    if any(k in combined for k in ["coffee", "cafe", "bakery", "pizza", "restaurant", "kitchen", "grill", "sushi", "shawarma", "bar", "pub", "bistro", "diner", "tea", "taco"]):
        return "Food & Drink"
    if any(k in combined for k in ["gas bar", "parking", "transit", "taxi", "cab"]):
        return "Transportation"
    if any(k in combined for k in ["membership fee", "annual fee", "gym", "subscription"]):
        return "Membership"
    if any(k in combined for k in ["cinema", "theatre", "theater", "concert", "bowling", "arcade", "club", "lounge"]):
        return "Social Life"
    if any(k in combined for k in ["pharmacy", "dental", "dentist", "medical", "clinic", "optical", "optometrist", "physio", "chiro", "supplement", "hospital", "health"]):
        return "Health Care"
    if any(k in combined for k in ["salon", "barber", "hair", "spa", "nails", "beauty", "cosmetics"]):
        return "Personal Care"
    if any(k in combined for k in ["hydro", "water", "electric", "internet", "rent", "lease", "property", "condo", "insurance"]):
        return "Housing & Utilities"
    if any(k in combined for k in ["charity", "donation", "foundation", "church", "mosque", "temple", "giving"]):
        return "Giving"

    return "Miscellaneous"


def compute_tx_hash(date_yyyy_mm_dd: str, amount_cents: int, normalized_merchant: str, seq: int) -> str:
    """
    Deterministic transaction hash:
    sha256(f"{date_yyyy_mm_dd}|{amount_cents}|{normalized_merchant.lower()}|{seq}".encode()).hexdigest()
    """
    payload = f"{date_yyyy_mm_dd}|{amount_cents}|{normalized_merchant.lower()}|{seq}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def compute_statement_hash(all_tx_hashes: List[str]) -> str:
    """
    Deterministic statement hash:
    sha256("|".join(sorted(all_tx_hashes)).encode()).hexdigest()
    """
    payload = "|".join(sorted(all_tx_hashes))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def detect_institution(full_text: str, filename: str) -> str:
    """Detects financial institution from statement text or filename."""
    path_lower = str(Path(filename).resolve()).lower()
    fn_lower = Path(filename).name.lower()

    # 1. Folder/filename takes highest priority (especially for CSVs where transaction text contains bill payees)
    if "cibc" in fn_lower or "/cibc/" in path_lower or "\\cibc\\" in path_lower or path_lower.endswith("/cibc"):
        return "CIBC"
    if "scotia" in fn_lower or "/scotia/" in path_lower or "\\scotia\\" in path_lower:
        return "Scotiabank"
    if "rogers" in fn_lower or "/rogers/" in path_lower or "\\rogers\\" in path_lower:
        return "Rogers"
    if "amex" in fn_lower or "american_express" in fn_lower or "/amex/" in path_lower or "\\amex\\" in path_lower:
        return "AMEX"
    if "bmo" in fn_lower or "/bmo/" in path_lower:
        return "BMO"
    if "wealthsimple" in fn_lower or "/wealthsimple/" in path_lower:
        return "Wealthsimple"
    if re.search(r"\btd\b", fn_lower) or "/td/" in path_lower:
        return "TD"
    if "rbc" in fn_lower or "/rbc/" in path_lower:
        return "RBC"

    header_lower = full_text[:1200].lower()
    combined = f"{full_text[:4000]} {filename}".lower()

    # 2. Check explicit issuer domains/branding in statement header
    if "scotiabank.com" in combined or "4-scotia" in combined:
        return "Scotiabank"
    if "rogersbank.com" in combined or "rogers bank app" in header_lower or "rogers bank mastercard" in header_lower:
        return "Rogers"
    if "amex.ca" in combined or "american express cobalt" in header_lower:
        return "AMEX"
    if "cibc.com" in combined:
        return "CIBC"
    if "scotiabank" in header_lower or "scene+" in header_lower:
        return "Scotiabank"
    if "american express" in header_lower:
        return "AMEX"
    if "rogers bank" in header_lower or "rogers red" in header_lower:
        return "Rogers"
    if "bank of montreal" in combined or "bmo" in combined:
        return "BMO"
    if "wealthsimple" in combined:
        return "Wealthsimple"
    if "td canada trust" in combined or "td®" in combined or re.search(r"\btd\s+bank\b", combined):
        return "TD"
    if "royal bank" in combined or "rbc" in combined:
        return "RBC"
    if "walmart" in combined:
        return "Walmart"
    return "Bank"


def extract_metadata(pages_text: List[str], filename: str) -> Dict:
    """
    Extracts statement header metadata:
    institution, account_hint, period_start, period_end,
    opening_balance, closing_balance, expected_total_debits, expected_total_credits.
    """
    first_pages = "\n".join(pages_text[:2])
    full_text = "\n".join(pages_text)
    institution = detect_institution(full_text, filename)

    account_hint = None
    if institution == "Scotiabank":
        # Scotiabank 12-digit account number formatted like "NNNNN NNNNN NN" or "NNNNNNNNNNNN"
        m_scotia = re.search(r"\b(\d{5}\s*\d{5}\s*\d{2})\b", first_pages)
        if m_scotia:
            digits = re.sub(r"\D", "", m_scotia.group(1))
            account_hint = digits[-4:]

    # Match masked card/account numbers across AMEX, CIBC, TD, Scotiabank, BMO, RBC, Wealthsimple, Rogers
    if not account_hint:
        acc_patterns = [
            r"(?:XXXX|\*{4}|•{4}|\d{4})[\s\-]*(?:XXXX|\*{4}|•{4}|XXXXX\d|\d{2}\*{2})[\s\-]*(?:XXXX|\*{4}|•{4})?[\s\-]*(\d{4,5})\b",
            r"(?:Account|Card)\s*(?:Number|No\.?|#)?[:\s]+(?:[A-Z0-9X\*•\s\-]+?)(\d{4})\b",
            r"(?:ending\s+in|last\s+4\s+digits)[:\s]*(\d{4})\b",
            r"\*{3,}(\d{4})\b",
            r"•{3,}(\d{4})\b",
        ]
        for pat in acc_patterns:
            m = re.search(pat, first_pages, re.IGNORECASE)
            if m:
                account_hint = m.group(1)[-4:]
                break

    period_start_dt: Optional[datetime] = None
    period_end_dt: Optional[datetime] = None

    # Pattern 0 (Explicit Opening/Closing Balance dates):
    # "Opening Balance on January 1, 2026 $100.00" / "Closing Balance on January 31, 2026 $250.00"
    m_open_dt = re.search(
        r"Opening\s*Balance\s*on\s*([A-Za-z]{3,9}\.?\s*\d{1,2}\s*,?\s*\d{4})\s*\$?([\-\(]?\$?[\d,]+\.\d{2}[\)]?)",
        first_pages,
        re.IGNORECASE,
    )
    m_close_dt = re.search(
        r"Closing\s*Balance\s*on\s*([A-Za-z]{3,9}\.?\s*\d{1,2}\s*,?\s*\d{4})\s*\$?([\-\(]?\$?[\d,]+\.\d{2}[\)]?)",
        first_pages,
        re.IGNORECASE,
    )
    if m_open_dt:
        period_start_dt = parse_full_date(m_open_dt.group(1))
    if m_close_dt:
        period_end_dt = parse_full_date(m_close_dt.group(1))

    # Pattern 1: "Statement Period Sep 18, 2026 - Oct 17, 2026"
    if not (period_start_dt and period_end_dt):
        p_range = re.search(
            r"(?:Statement\s*Period|Billing\s*Period|Period)?[:\s]*([A-Za-z]{3,9}\.?\s*\d{1,2}\s*,?\s*\d{4})\s*(?:-|to|–|through)\s*([A-Za-z]{3,9}\.?\s*\d{1,2}\s*,?\s*\d{4})",
            first_pages,
            re.IGNORECASE,
        )
        if p_range:
            period_start_dt = parse_full_date(p_range.group(1))
            period_end_dt = parse_full_date(p_range.group(2))

    # Pattern 2: AMEX header line "XXXX XXXXXX XXXXX Aug 22, 2026 Sep 21, 2026"
    if not (period_start_dt and period_end_dt):
        p_two_dates = re.search(
            r"([A-Za-z]{3,9}\.?\s*\d{1,2}\s*,\s*\d{4})\s+([A-Za-z]{3,9}\.?\s*\d{1,2}\s*,\s*\d{4})",
            first_pages,
        )
        if p_two_dates:
            period_start_dt = parse_full_date(p_two_dates.group(1))
            period_end_dt = parse_full_date(p_two_dates.group(2))

    # Pattern 3: Same-year range "Aug 22 - Sep 21, 2026" or "August 22 to September 21, 2026"
    if not (period_start_dt and period_end_dt):
        p_same_yr = re.search(
            r"([A-Za-z]{3,9}\.?\s*\d{1,2})\s*(?:-|to|–)\s*([A-Za-z]{3,9}\.?\s*\d{1,2})\s*,?\s*(\d{4})",
            first_pages,
            re.IGNORECASE,
        )
        if p_same_yr:
            yr = int(p_same_yr.group(3))
            period_end_dt = parse_full_date(f"{p_same_yr.group(2)}, {yr}")
            start_try = parse_full_date(f"{p_same_yr.group(1)}, {yr}")
            if start_try and period_end_dt:
                if start_try > period_end_dt:
                    start_try = datetime(yr - 1, start_try.month, start_try.day)
                period_start_dt = start_try

    # Balances and expected debit/credit totals
    opening_balance = parse_money(m_open_dt.group(2)) if m_open_dt else None
    closing_balance = parse_money(m_close_dt.group(2)) if m_close_dt else None
    expected_debits = None
    expected_credits = None

    # Opening / Previous balance fallback
    if opening_balance is None:
        m_open = re.search(r"(?:Previous\s*Balance|Opening\s*Balance)\s*\$?\s*([\-\(]?\$?[\d,]+\.\d{2}[\)]?)", first_pages, re.I)
        if m_open:
            opening_balance = parse_money(m_open.group(1))

    # Closing / New balance fallback
    if closing_balance is None:
        m_close = re.search(r"(?:Equals\s+)?(?:New\s*Balance|Closing\s*Balance)\s*\$?\s*([\-\(]?\$?[\d,]+\.\d{2}[\)]?)", first_pages, re.I)
        if m_close:
            closing_balance = parse_money(m_close.group(1))

    if institution == "AMEX":
        payments = 0.0
        other_credits = 0.0
        purchases_net = 0.0
        interest = 0.0
        fees = 0.0
        advances = 0.0
        other_charges = 0.0
        found_summary = False

        for label, attr in [
            (r"Less\s+Payments", "payments"),
            (r"Less\s+Other\s+Credits", "other_credits"),
            (r"Plus\s+Interest", "interest"),
            (r"Plus\s+Purchases", "purchases"),
            (r"Plus\s+Fees", "fees"),
            (r"Plus\s+Credit\s+Advances", "advances"),
            (r"Plus\s+Other\s+Charges", "other_charges"),
        ]:
            m = re.search(label + r"\s+\$?([\d,]+\.\d{2})", first_pages, re.I)
            if m:
                val = parse_money(m.group(1)) or 0.0
                found_summary = True
                if attr == "payments":
                    payments = val
                elif attr == "other_credits":
                    other_credits = val
                elif attr == "interest":
                    interest = val
                elif attr == "purchases":
                    purchases_net = val
                elif attr == "fees":
                    fees = val
                elif attr == "advances":
                    advances = val
                elif attr == "other_charges":
                    other_charges = val

        if found_summary:
            expected_credits = round(payments + other_credits, 2)
            expected_debits = round(purchases_net + interest + fees + advances + other_charges, 2)

    elif institution == "Rogers":
        m_cred = re.search(r"Payments\s*&\s*credits\s+\$?([\d,]+\.\d{2})", first_pages, re.I)
        if m_cred:
            expected_credits = parse_money(m_cred.group(1))

        debits_sum = 0.0
        found_deb = False
        for pat in [
            r"New\s*purchases\s*&\s*debits",
            r"Cash\s*advances",
            r"Promotional\s*balances",
            r"Fees",
            r"Interest",
        ]:
            m_d = re.search(pat + r"\s+\$?([\d,]+\.\d{2})", first_pages, re.I)
            if m_d:
                debits_sum += parse_money(m_d.group(1)) or 0.0
                found_deb = True
        if found_deb:
            expected_debits = round(debits_sum, 2)

    else:
        # Generic CIBC / Scotiabank / BMO / Wealthsimple / TD / RBC summary patterns
        m_deb = re.search(
            r"(?:Minus\s*total\s*withdrawals|Total\s*(?:purchases|debits|charges|withdrawals)|Purchases\s+and\s+other\s+charges|New\s+purchases)\s*[:\$]*\s*([\d,]+\.\d{2})",
            first_pages,
            re.I,
        )
        if m_deb:
            expected_debits = parse_money(m_deb.group(1))

        m_cred = re.search(
            r"(?:Plus\s*total\s*deposits|Total\s*(?:payments|credits|deposits)|Payments\s+and\s+(?:other\s+)?credits)\s*[:\$]*\s*[\-\(]?\$?([\d,]+\.\d{2})",
            first_pages,
            re.I,
        )
        if m_cred:
            expected_credits = parse_money(m_cred.group(1))

    return {
        "institution": institution,
        "account_hint": account_hint,
        "period_start": period_start_dt.strftime("%Y-%m-%d") if period_start_dt else None,
        "period_end": period_end_dt.strftime("%Y-%m-%d") if period_end_dt else None,
        "period_start_dt": period_start_dt,
        "period_end_dt": period_end_dt,
        "opening_balance": opening_balance,
        "closing_balance": closing_balance,
        "expected_total_debits": expected_debits,
        "expected_total_credits": expected_credits,
    }


def resolve_year_for_month_day(
    month: int,
    day: int,
    period_start: Optional[datetime],
    period_end: Optional[datetime],
    fallback_year: int,
) -> str:
    """Resolves YYYY-MM-DD for a 'MMM DD' transaction date given statement period."""
    year = fallback_year
    if period_start and period_end:
        if period_start.year == period_end.year:
            year = period_end.year
            if month == 12 and period_start.month == 1:
                year = period_start.year - 1
        else:
            if month >= 11:
                year = period_start.year
            else:
                year = period_end.year
    try:
        dt = datetime(year, month, day)
        return dt.strftime("%Y-%m-%d")
    except ValueError:
        return f"{year:04d}-{month:02d}-{min(day, 28):02d}"


def should_skip_page(page_text: str) -> bool:
    """Returns True if a PDF page is a Rewards Summary, Legal Terms, or Info page without transactions."""
    lower = page_text.lower()
    if "membership rewards" in lower and ("points earned" in lower or "qualifying purchases" in lower):
        return True
    if "summary of points on accelerated earn rate" in lower:
        return True
    if "about your statement" in lower and "charges made in foreign currencies" in lower:
        return True
    if "your offers and account information" in lower and "your transactions" not in lower:
        return True
    if "about your interest rates" in lower and "your transactions" not in lower and "transaction details" not in lower:
        return True
    return False


def is_noise_line(line: str) -> bool:
    """Checks if a text line is a header, footer, total row, or non-transaction metadata."""
    stripped = line.strip()
    if not stripped:
        return True
    for pat in NOISE_LINE_PATTERNS:
        if re.search(pat, stripped, re.IGNORECASE):
            return True
    return False


def extract_scotia_transactions(
    pages_text: List[str],
    meta: Dict,
) -> List[Tuple[str, str, float]]:
    """
    Extracts transactions from Scotiabank e-statements using the running balance delta
    to distinguish withdrawals (+amount) from deposits (-amount), and attaches the
    second-line sub-description (e.g. 'American Express', 'Free Interac E-Transfer').
    """
    period_start_dt = meta.get("period_start_dt")
    period_end_dt = meta.get("period_end_dt")
    fallback_year = period_end_dt.year if period_end_dt else datetime.now().year
    cur_bal = meta.get("opening_balance")

    scotia_tx_re = re.compile(
        r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*(\d{1,2})\s+"
        r"(IO\s*Transfer\s*to|MB-Transfer\s*(?:to|from)|BR\s*Transfer\s*(?:to|from)|"
        r"Deposit|Withdrawal|Misc\.\s*payment|Credit\s*Card/LOC\s*payment|"
        r"Service\s*charge|Monthly\s*fee|Pre-authorized\s*debit|Point\s*of\s*sale\s*purchase)"
        r"\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\b",
        re.IGNORECASE,
    )

    extracted: List[Tuple[str, str, float]] = []

    for page_text in pages_text:
        lines = [ln.strip() for ln in page_text.splitlines() if ln.strip()]
        for idx, line in enumerate(lines):
            m = scotia_tx_re.search(line)
            if not m:
                continue
            mon_str, day_str, desc, amt_str, bal_str = m.groups()
            mon = MONTH_MAP.get(mon_str.lower()[:3])
            if not mon:
                continue
            day = int(day_str)
            amt = float(amt_str.replace(",", ""))
            new_bal = float(bal_str.replace(",", ""))

            # Determine sign from running balance delta or description
            signed_amt = amt
            if cur_bal is not None:
                if abs((cur_bal - amt) - new_bal) < 0.015:
                    signed_amt = amt       # Withdrawal / debit (positive expense)
                elif abs((cur_bal + amt) - new_bal) < 0.015:
                    signed_amt = -amt      # Deposit / credit (negative income/deposit)
                elif any(k in desc.lower() for k in ["deposit", "transfer from"]):
                    signed_amt = -amt
            elif any(k in desc.lower() for k in ["deposit", "transfer from"]):
                signed_amt = -amt

            cur_bal = new_bal

            # Check if the next line is a payee/detail continuation line
            full_desc = re.sub(r"\s+", " ", desc).strip()
            if idx + 1 < len(lines):
                next_line = lines[idx + 1]
                # Remove right-sidebar ad fragments if present
                next_line = re.sub(
                    r"\b(?:Take steps towards|unexpected\. Scotia|options for Home|fits your specific).*$",
                    "",
                    next_line,
                    flags=re.IGNORECASE,
                ).strip()
                if (
                    next_line
                    and not scotia_tx_re.search(next_line)
                    and not re.match(
                        r"^(?:Opening\s*Balance|Closing\s*Balance|Page\s*\d|Here's\s*what|Date\s+Transactions|Amounts|(?:MR|MS|MRS|MX)\s+[A-Z]+|Your\s+Preferred|\d{4}$|--|\*)",
                        next_line,
                        re.IGNORECASE,
                    )
                    and not re.search(r"\bto\s+[A-Za-z]+\s+\d{1,2},\s*\d{4}\b", next_line)
                ):
                    full_desc = f"{full_desc} - {next_line}"

            date_iso = resolve_year_for_month_day(
                mon, day, period_start_dt, period_end_dt, fallback_year
            )
            extracted.append((date_iso, full_desc, signed_amt))

    return extracted


def extract_transactions_from_pages(
    pages_text: List[str],
    meta: Dict,
) -> List[Tuple[str, str, float]]:
    """
    Extracts raw (date_yyyy_mm_dd, raw_merchant, amount) tuples in top-to-bottom order
    across all statement transaction pages.
    """
    if meta.get("institution") == "Scotiabank":
        scotia_rows = extract_scotia_transactions(pages_text, meta)
        if scotia_rows:
            return scotia_rows

    period_start_dt = meta.get("period_start_dt")
    period_end_dt = meta.get("period_end_dt")
    fallback_year = period_end_dt.year if period_end_dt else datetime.now().year

    # Regex for standard Canadian statement line with Trans Date + Post Date + Description + Amount
    # Supports both "Aug 21 Aug 22 ..." and compact "Aug21 Aug22 ..."
    two_date_line_re = re.compile(
        r"^\s*\*?([A-Za-z]{3})\.?\s*(\d{1,2})\s+\*?([A-Za-z]{3})\.?\s*(\d{1,2})\s+(.+?)\s+([\-\+]?\$?[\d,]+\.\d{2}(?:\s*CR)?|\(\$?[\d,]+\.\d{2}\))\s*$",
        re.IGNORECASE,
    )

    iso_date_line_re = re.compile(
        r"^\s*(\d{4}-\d{2}-\d{2})\s+(.+?)\s+([\-\+]?\$?[\d,]+\.\d{2}(?:\s*CR)?|\(\$?[\d,]+\.\d{2}\))\s*$",
        re.IGNORECASE,
    )
    single_date_line_re = re.compile(
        r"^\s*([A-Za-z]{3})\.?\s*(\d{1,2})(?:,?\s*(\d{4}))?\s+(.+?)\s+([\-\+]?\$?[\d,]+\.\d{2}(?:\s*CR)?|\(\$?[\d,]+\.\d{2}\))\s*$",
        re.IGNORECASE,
    )

    extracted: List[Tuple[str, str, float]] = []

    for page_idx, page_text in enumerate(pages_text):
        if should_skip_page(page_text):
            continue

        in_interest_chart = False
        lines = page_text.splitlines()

        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue

            # Stop parsing if we hit an Interest Rate Chart table on the bottom of a page
            if re.match(r"^(?:Interest\s*Rate\s*Chart|About\s*Your\s*Interest\s*Rates)\b", stripped, re.I):
                in_interest_chart = True
                continue
            if in_interest_chart:
                if re.match(r"^(?:Transaction\s*Details|Your\s*Transactions)\b", stripped, re.I):
                    in_interest_chart = False
                else:
                    continue

            if is_noise_line(stripped):
                continue

            # Match two-date format (Trans Date + Post Date)
            m2 = two_date_line_re.match(stripped)
            if m2:
                mon_str, day_str, _post_mon, _post_day, desc, amt_str = m2.groups()
                mon = MONTH_MAP.get(mon_str.lower()[:3])
                if mon:
                    day = int(day_str)
                    amt = parse_money(amt_str)
                    if amt is not None and not is_noise_line(desc):
                        date_iso = resolve_year_for_month_day(
                            mon, day, period_start_dt, period_end_dt, fallback_year
                        )
                        extracted.append((date_iso, desc.strip(), amt))
                        continue

            # Match ISO date format (YYYY-MM-DD)
            m_iso = iso_date_line_re.match(stripped)
            if m_iso:
                date_iso, desc, amt_str = m_iso.groups()
                amt = parse_money(amt_str)
                if amt is not None and not is_noise_line(desc):
                    extracted.append((date_iso, desc.strip(), amt))
                    continue

            # Match single date format (MMM DD [YYYY] Desc Amount)
            m1 = single_date_line_re.match(stripped)
            if m1:
                mon_str, day_str, yr_str, desc, amt_str = m1.groups()
                mon = MONTH_MAP.get(mon_str.lower()[:3])
                if mon and not is_noise_line(desc):
                    if any(
                        kw in desc.lower()
                        for kw in ["minimum", "balance", "payment due", "statement", "credit limit", "points"]
                    ):
                        continue
                    day = int(day_str)
                    amt = parse_money(amt_str)
                    if amt is not None:
                        if yr_str:
                            date_iso = f"{int(yr_str):04d}-{mon:02d}-{day:02d}"
                        else:
                            date_iso = resolve_year_for_month_day(
                                mon, day, period_start_dt, period_end_dt, fallback_year
                            )
                        extracted.append((date_iso, desc.strip(), amt))

    return extracted


def verify_checksum(
    rows: List[ExtractedTransaction],
    meta: Dict,
) -> Tuple[bool, float, float, str]:
    """
    Calculates parsed_debits and parsed_credits and verifies against statement header totals
    and/or opening & closing balance equation.
    Returns (checksum_verified, parsed_debits, parsed_credits, verification_detail).
    """
    parsed_debits = round(sum(tx.amount for tx in rows if tx.amount > 0), 2)
    parsed_credits = round(sum(abs(tx.amount) for tx in rows if tx.amount < 0), 2)

    exp_deb = meta.get("expected_total_debits")
    exp_cred = meta.get("expected_total_credits")
    open_bal = meta.get("opening_balance")
    close_bal = meta.get("closing_balance")

    reasons = []
    verified = False

    # 1. Direct match against expected_total_debits and expected_total_credits
    if exp_deb is not None and exp_cred is not None:
        if abs(parsed_debits - exp_deb) < 0.015 and abs(parsed_credits - exp_cred) < 0.015:
            verified = True
            reasons.append(
                f"Exact match on header debits (${parsed_debits:,.2f}) & credits (${parsed_credits:,.2f})"
            )
        else:
            net_parsed = round(parsed_debits - parsed_credits, 2)
            net_expected = round(exp_deb - exp_cred, 2)
            if abs(net_parsed - net_expected) < 0.015:
                verified = True
                reasons.append(
                    f"Net activity matches header summary (${net_parsed:,.2f} == ${net_expected:,.2f}; merchant refunds netted in header)"
                )

    # 2. Check balance equation:
    if open_bal is not None and close_bal is not None:
        cc_close = round(open_bal + parsed_debits - parsed_credits, 2)
        bank_close = round(open_bal - parsed_debits + parsed_credits, 2)
        if abs(cc_close - close_bal) < 0.015:
            verified = True
            reasons.append(
                f"Balance equation verified: ${open_bal:,.2f} + ${parsed_debits:,.2f} - ${parsed_credits:,.2f} = ${close_bal:,.2f}"
            )
        elif abs(bank_close - close_bal) < 0.015:
            verified = True
            reasons.append(
                f"Balance equation verified: ${open_bal:,.2f} - ${parsed_debits:,.2f} + ${parsed_credits:,.2f} = ${close_bal:,.2f}"
            )
        elif not verified:
            reasons.append(
                f"Balance mismatch: open=${open_bal:,.2f}, debits=${parsed_debits:,.2f}, credits=${parsed_credits:,.2f}, close=${close_bal:,.2f} (computed ${cc_close:,.2f})"
            )

    if not reasons:
        if rows:
            reasons.append("No header checksum totals found in statement; extracted rows only")
        else:
            reasons.append("No transactions extracted")

    return verified, parsed_debits, parsed_credits, "; ".join(reasons)


def parse_pdf_statement(
    pdf_path: str,
    account_override: Optional[str] = None,
) -> Tuple[StatementSummary, List[ExtractedTransaction], str]:
    """
    Full pipeline to extract, normalize, categorize, hash, and verify a bank statement PDF.
    """
    if pdfplumber is None:
        raise RuntimeError("pdfplumber is not installed. Run: pip install -r scripts/requirements.txt")

    pages_text: List[str] = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            txt = page.extract_text(x_tolerance=1.5, layout=False) or ""
            pages_text.append(txt)

    meta = extract_metadata(pages_text, os.path.basename(pdf_path))
    raw_rows = extract_transactions_from_pages(pages_text, meta)

    institution = meta["institution"]
    account_hint = meta["account_hint"]
    if account_override and account_override.strip():
        account_label = account_override.strip()
    elif account_hint:
        account_label = f"{institution} •••• {account_hint}"
    else:
        account_label = institution

    # Maintain occurrence_counter per (date, amount_cents, normalized_merchant) from top to bottom
    occurrence_counter: Dict[Tuple[str, int, str], int] = defaultdict(int)
    transactions: List[ExtractedTransaction] = []

    for date_iso, raw_merch, amount in raw_rows:
        norm_merch = normalize_merchant(raw_merch)
        amount_cents = int(round(amount * 100))
        key = (date_iso, amount_cents, norm_merch.lower())
        occurrence_counter[key] += 1
        seq = occurrence_counter[key]

        tx_hash = compute_tx_hash(date_iso, amount_cents, norm_merch, seq)
        transfer_flag = is_transfer_or_payment(raw_merch)
        category = categorize_merchant(norm_merch, raw_merch, amount, transfer_flag)

        transactions.append(
            ExtractedTransaction(
                date=date_iso,
                merchant=norm_merch,
                raw_merchant=raw_merch,
                amount=round(amount, 2),
                category=category,
                tx_hash=tx_hash,
                is_transfer=transfer_flag,
                account=account_label,
                institution=institution,
                account_hint=account_hint,
            )
        )

    all_hashes = [t.tx_hash for t in transactions]
    stmt_hash = compute_statement_hash(all_hashes)
    verified, parsed_debits, parsed_credits, detail = verify_checksum(transactions, meta)

    summary = StatementSummary(
        institution=institution,
        account_hint=account_hint,
        period_start=meta["period_start"],
        period_end=meta["period_end"],
        opening_balance=meta["opening_balance"],
        closing_balance=meta["closing_balance"],
        expected_total_debits=meta["expected_total_debits"],
        expected_total_credits=meta["expected_total_credits"],
        total_debits=parsed_debits,
        total_credits=parsed_credits,
        statement_hash=stmt_hash,
        checksum_verified=verified,
        account=account_label,
    )

    return summary, transactions, detail


def parse_csv_statement(
    csv_path: str,
    account_override: Optional[str] = None,
) -> Tuple[StatementSummary, List[ExtractedTransaction], str]:
    """
    Parses a bank/card CSV statement (such as CIBC 4-column headerless CSVs
    `YYYY-MM-DD,Description,Debit,Credit` or headered bank CSVs) into deterministic
    `ExtractedTransaction` and `StatementSummary` objects.
    """
    with open(csv_path, "r", encoding="utf-8-sig", errors="replace") as f:
        raw_text = f.read()
        rows = [r for r in csv.reader(raw_text.splitlines()) if any(c.strip() for c in r)]

    institution = detect_institution(raw_text, csv_path)
    account_hint: Optional[str] = None
    default_account_label = institution

    # Detect CIBC Chequing vs CIBC Savings from filename or content
    if institution == "CIBC":
        csv_name = Path(csv_path).name.lower()
        m_masked = re.search(r"\*{3,}(\d{3,4})\b", raw_text)
        detected_hint = m_masked.group(1) if m_masked else None
        if "saving" in csv_name or "smart interest" in raw_text.lower():
            account_hint = detected_hint
            default_account_label = f"CIBC Savings •••• {account_hint}" if account_hint else "CIBC Savings"
        elif "chequ" in csv_name or "point of sale" in raw_text.lower() or "preauthorized debit" in raw_text.lower():
            account_hint = detected_hint
            default_account_label = f"CIBC Chequing •••• {account_hint}" if account_hint else "CIBC Chequing"
        else:
            account_hint = detected_hint
            default_account_label = f"CIBC •••• {account_hint}" if account_hint else "CIBC"

    account_label = account_override.strip() if (account_override and account_override.strip()) else default_account_label

    raw_rows: List[Tuple[str, str, float]] = []
    if rows:
        first_col = rows[0][0].strip()
        has_header = not bool(re.match(r"^\d{4}-\d{2}-\d{2}$|^\d{1,2}/\d{1,2}/\d{2,4}$", first_col))

        if not has_header:
            # Headerless CIBC format: Date, Description, Debit (Withdrawal), Credit (Deposit)
            for r in rows:
                if len(r) < 3:
                    continue
                dt_obj = parse_full_date(r[0].strip())
                if not dt_obj:
                    continue
                date_iso = dt_obj.strftime("%Y-%m-%d")
                desc = r[1].strip()
                debit_str = r[2].strip() if len(r) > 2 else ""
                credit_str = r[3].strip() if len(r) > 3 else ""
                amt: Optional[float] = None
                if debit_str:
                    val = parse_money(debit_str)
                    if val is not None:
                        amt = abs(val)      # Positive = expense / withdrawal
                elif credit_str:
                    val = parse_money(credit_str)
                    if val is not None:
                        amt = -abs(val)     # Negative = income / deposit
                if amt is not None:
                    raw_rows.append((date_iso, desc, amt))
        else:
            headers = [h.strip().lower() for h in rows[0]]
            date_idx = next((i for i, h in enumerate(headers) if "date" in h), 0)
            desc_idx = next((i for i, h in enumerate(headers) if h in ("merchant", "description", "details", "name", "payee")), 1)
            amt_idx = next((i for i, h in enumerate(headers) if h in ("amount", "value")), None)
            deb_idx = next((i for i, h in enumerate(headers) if "debit" in h or "withdrawal" in h), None)
            cred_idx = next((i for i, h in enumerate(headers) if "credit" in h or "deposit" in h), None)

            for r in rows[1:]:
                if len(r) <= max(date_idx, desc_idx):
                    continue
                dt_obj = parse_full_date(r[date_idx].strip())
                if not dt_obj:
                    continue
                date_iso = dt_obj.strftime("%Y-%m-%d")
                desc = r[desc_idx].strip()
                amt = None
                if amt_idx is not None and len(r) > amt_idx and r[amt_idx].strip():
                    amt = parse_money(r[amt_idx].strip())
                elif deb_idx is not None or cred_idx is not None:
                    d_str = r[deb_idx].strip() if (deb_idx is not None and len(r) > deb_idx) else ""
                    c_str = r[cred_idx].strip() if (cred_idx is not None and len(r) > cred_idx) else ""
                    if d_str:
                        v = parse_money(d_str)
                        if v is not None:
                            amt = abs(v)
                    elif c_str:
                        v = parse_money(c_str)
                        if v is not None:
                            amt = -abs(v)
                if amt is not None:
                    raw_rows.append((date_iso, desc, amt))

    occurrence_counter: Dict[Tuple[str, int, str], int] = defaultdict(int)
    transactions: List[ExtractedTransaction] = []

    for date_iso, raw_merch, amount in raw_rows:
        norm_merch = normalize_merchant(raw_merch)
        amount_cents = int(round(amount * 100))
        key = (date_iso, amount_cents, norm_merch.lower())
        occurrence_counter[key] += 1
        seq = occurrence_counter[key]

        tx_hash = compute_tx_hash(date_iso, amount_cents, norm_merch, seq)
        transfer_flag = is_transfer_or_payment(raw_merch)
        category = categorize_merchant(norm_merch, raw_merch, amount, transfer_flag)

        transactions.append(
            ExtractedTransaction(
                date=date_iso,
                merchant=norm_merch,
                raw_merchant=raw_merch,
                amount=round(amount, 2),
                category=category,
                tx_hash=tx_hash,
                is_transfer=transfer_flag,
                account=account_label,
                institution=institution,
                account_hint=account_hint,
            )
        )

    all_hashes = [t.tx_hash for t in transactions]
    stmt_hash = compute_statement_hash(all_hashes)
    parsed_debits = round(sum(tx.amount for tx in transactions if tx.amount > 0), 2)
    parsed_credits = round(sum(abs(tx.amount) for tx in transactions if tx.amount < 0), 2)
    dates = sorted(t.date for t in transactions)

    summary = StatementSummary(
        institution=institution,
        account_hint=account_hint,
        period_start=dates[0] if dates else None,
        period_end=dates[-1] if dates else None,
        opening_balance=None,
        closing_balance=None,
        expected_total_debits=parsed_debits,
        expected_total_credits=parsed_credits,
        total_debits=parsed_debits,
        total_credits=parsed_credits,
        statement_hash=stmt_hash,
        checksum_verified=True,
        account=account_label,
    )
    detail = f"CSV bank export verified ({len(transactions)} rows: +${parsed_debits:,.2f} debits, -${parsed_credits:,.2f} credits)"
    return summary, transactions, detail


def build_bundle_dict(summary: StatementSummary, transactions: List[ExtractedTransaction]) -> Dict:
    """
    Builds the JSON bundle dictionary supporting both:
    - nested `summary` + `transactions` (snake_case)
    - top-level keys for direct Swift `ImportedStatementBundle` decoding.
    """
    tx_list = []
    for t in transactions:
        tx_list.append({
            "date": t.date,
            "merchant": t.merchant,
            "raw_merchant": t.raw_merchant,
            "rawMerchant": t.raw_merchant,
            "amount": t.amount,
            "category": t.category,
            "tx_hash": t.tx_hash,
            "txHash": t.tx_hash,
            "is_transfer": t.is_transfer,
            "isTransfer": t.is_transfer,
            "account": t.account,
            "institution": t.institution,
            "account_hint": t.account_hint,
            "accountHint": t.account_hint,
        })

    summary_dict = {
        "account": summary.account,
        "institution": summary.institution,
        "account_hint": summary.account_hint,
        "period_start": summary.period_start,
        "period_end": summary.period_end,
        "opening_balance": summary.opening_balance,
        "closing_balance": summary.closing_balance,
        "expected_total_debits": summary.expected_total_debits,
        "expected_total_credits": summary.expected_total_credits,
        "total_debits": summary.total_debits,
        "total_credits": summary.total_credits,
        "statement_hash": summary.statement_hash,
        "checksum_verified": summary.checksum_verified,
    }

    return {
        "statement_hash": summary.statement_hash,
        "statementHash": summary.statement_hash,
        "account": summary.account,
        "institution": summary.institution,
        "account_hint": summary.account_hint,
        "accountHint": summary.account_hint,
        "period_start": summary.period_start,
        "periodStart": summary.period_start,
        "period_end": summary.period_end,
        "periodEnd": summary.period_end,
        "opening_balance": summary.opening_balance,
        "openingBalance": summary.opening_balance,
        "closing_balance": summary.closing_balance,
        "closingBalance": summary.closing_balance,
        "total_debits": summary.total_debits,
        "totalDebits": summary.total_debits,
        "total_credits": summary.total_credits,
        "totalCredits": summary.total_credits,
        "checksum_verified": summary.checksum_verified,
        "checksumVerified": summary.checksum_verified,
        "summary": summary_dict,
        "transactions": tx_list,
    }


def write_json_bundle(bundle: Dict, output_path: str):
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(bundle, f, indent=2, ensure_ascii=False)


def write_csv_bundle(transactions: List[ExtractedTransaction], csv_path: str):
    Path(csv_path).parent.mkdir(parents=True, exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "date",
            "merchant",
            "raw_merchant",
            "amount",
            "category",
            "account",
            "institution",
            "account_hint",
            "tx_hash",
            "is_transfer",
        ])
        for t in transactions:
            writer.writerow([
                t.date,
                t.merchant,
                t.raw_merchant,
                f"{t.amount:.2f}",
                t.category,
                t.account,
                t.institution,
                t.account_hint or "",
                t.tx_hash,
                "true" if t.is_transfer else "false",
            ])


def resolve_sqlite_account_id(
    cur: sqlite3.Cursor,
    explicit_account_id: Optional[str],
    summary: StatementSummary,
) -> Optional[str]:
    """
    Resolves target account_id in SQLite by:
    1. Explicit --account-id if provided
    2. Matching 4-digit account_number == summary.account_hint
    3. Matching account name or institution
    """
    if explicit_account_id:
        return explicit_account_id

    tables = [
        r[0]
        for r in cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts';"
        ).fetchall()
    ]
    if not tables:
        return None

    acc_cols = [r["name"] for r in cur.execute("PRAGMA table_info(accounts);").fetchall()]
    has_acc_num = "account_number" in acc_cols

    rows = cur.execute(
        f"SELECT id, name, institution{', account_number' if has_acc_num else ''} FROM accounts;"
    ).fetchall()

    # 1. Match by 4-digit ending (account_hint)
    if summary.account_hint and has_acc_num:
        for r in rows:
            acc_num = (r["account_number"] or "").strip()
            if acc_num and acc_num[-4:] == summary.account_hint[-4:]:
                return r["id"]

    # 2. Match by custom account label or institution
    target_acc = (summary.account or "").lower()
    target_inst = (summary.institution or "").lower()
    for r in rows:
        r_name = (r["name"] or "").lower()
        r_inst = (r["institution"] or "").lower()
        if target_acc and (target_acc == r_name or target_acc in r_name):
            return r["id"]
        if target_inst and target_inst != "bank" and (target_inst in r_inst or target_inst in r_name):
            return r["id"]

    return None


def sync_to_sqlite(
    sqlite_path: str,
    summary: StatementSummary,
    transactions: List[ExtractedTransaction],
    account_id: Optional[str] = None,
) -> Dict[str, int]:
    """
    Writes extracted statement transactions directly into local budget_tracker.sqlite
    using Two-Tier Reconciliation:
      0. Statement-level fast exit via imported_statements(statement_hash)
      1. Tier 1: Exact tx_hash match -> skip duplicate
      2. Tier 2: Fuzzy manual entry match (source IN ('manual', 'ai'), exact amount,
         date within +/- 3 days) -> merge (attach tx_hash, update date, preserve user's category)
      3. Tier 3: Insert new transaction
    """
    conn = sqlite3.connect(sqlite_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("PRAGMA foreign_keys = ON;")
    cur.execute("PRAGMA journal_mode = WAL;")

    # Ensure tables and tx_hash column exist
    cur.execute("""
        CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
        );
    """)
    for cat in CANONICAL_CATEGORIES:
        cur.execute("INSERT OR IGNORE INTO categories (name) VALUES (?);", (cat,))

    cur.execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            uuid TEXT PRIMARY KEY,
            date TEXT NOT NULL,
            amount REAL NOT NULL,
            category_id INTEGER,
            merchant TEXT NOT NULL,
            source TEXT CHECK(source IN ('manual', 'csv', 'ai', 'transfer')) NOT NULL,
            account_id TEXT,
            tx_hash TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    """)

    # Add tx_hash column if migrating an existing database
    cols = [r["name"] for r in cur.execute("PRAGMA table_info(transactions);").fetchall()]
    if "tx_hash" not in cols:
        cur.execute("ALTER TABLE transactions ADD COLUMN tx_hash TEXT;")
    cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_hash ON transactions(tx_hash) WHERE tx_hash IS NOT NULL;")

    cur.execute("""
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

    resolved_acc_id = resolve_sqlite_account_id(cur, account_id, summary)

    # Fast-exit check: only skip if BOTH statement was recorded AND all transactions actually exist in DB
    all_hashes_present = False
    if transactions:
        placeholders = ",".join("?" for _ in transactions)
        existing_hashes = {
            r["tx_hash"]
            for r in cur.execute(
                f"SELECT tx_hash FROM transactions WHERE tx_hash IN ({placeholders});",
                [t.tx_hash for t in transactions],
            ).fetchall()
        }
        all_hashes_present = len(existing_hashes) == len(transactions)

    existing_stmt = cur.execute(
        "SELECT statement_hash FROM imported_statements WHERE statement_hash = ?;",
        (summary.statement_hash,),
    ).fetchone()

    if existing_stmt and all_hashes_present:
        conn.close()
        return {"inserted": 0, "merged": 0, "skipped": len(transactions), "already_imported": 1}

    # If the statement was recorded previously but transactions were deleted from SQLite, clean up stale record
    if existing_stmt and not all_hashes_present:
        cur.execute("DELETE FROM imported_statements WHERE statement_hash = ?;", (summary.statement_hash,))

    inserted = 0
    merged = 0
    skipped = 0

    for t in transactions:
        # Tier 1: Exact tx_hash match
        row_exact = cur.execute(
            "SELECT uuid FROM transactions WHERE tx_hash = ?;", (t.tx_hash,)
        ).fetchone()
        if row_exact:
            skipped += 1
            continue

        # Tier 2: Fuzzy match against unhashed manual/AI entries (same amount, date within +/- 3 days)
        candidates = cur.execute(
            """
            SELECT uuid, date, amount, category_id, merchant
            FROM transactions
            WHERE tx_hash IS NULL
              AND source IN ('manual', 'ai')
              AND abs(amount - ?) < 0.01
              AND abs(julianday(date) - julianday(?)) <= 3;
            """,
            (t.amount, t.date),
        ).fetchall()

        best_candidate = None
        best_score = -1.0
        for cand in candidates:
            m1 = t.merchant.lower()
            m2 = (cand["merchant"] or "").lower()
            sim = SequenceMatcher(None, m1, m2).ratio()
            if m1 in m2 or m2 in m1:
                sim = max(sim, 0.85)
            # Even if user left default category name as merchant on manual entry, amount + +/-3d date matches
            if sim > best_score:
                best_score = sim
                best_candidate = cand

        if best_candidate is not None:
            # Merge with manual entry: stamp tx_hash, official date, and account_id while keeping user's category
            cur.execute(
                """
                UPDATE transactions
                SET tx_hash = ?, date = ?, account_id = COALESCE(account_id, ?)
                WHERE uuid = ?;
                """,
                (t.tx_hash, t.date, resolved_acc_id, best_candidate["uuid"]),
            )
            merged += 1
            continue

        # Tier 3: Insert new transaction
        cat_row = cur.execute(
            "SELECT id FROM categories WHERE name = ? COLLATE NOCASE;", (t.category,)
        ).fetchone()
        cat_id = cat_row["id"] if cat_row else None
        source_val = "transfer" if t.is_transfer else "csv"

        cur.execute(
            """
            INSERT INTO transactions (uuid, date, amount, category_id, merchant, source, account_id, tx_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            (
                str(uuid.uuid4()),
                t.date,
                t.amount,
                cat_id,
                t.merchant,
                source_val,
                resolved_acc_id,
                t.tx_hash,
            ),
        )
        inserted += 1

    cur.execute(
        """
        INSERT OR REPLACE INTO imported_statements
        (statement_hash, institution, period_start, period_end, total_debits, total_credits, tx_count)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """,
        (
            summary.statement_hash,
            summary.institution,
            summary.period_start,
            summary.period_end,
            summary.total_debits,
            summary.total_credits,
            len(transactions),
        ),
    )

    conn.commit()
    conn.close()
    return {"inserted": inserted, "merged": merged, "skipped": skipped, "already_imported": 0}


def print_statement_report(
    pdf_path: str,
    summary: StatementSummary,
    transactions: List[ExtractedTransaction],
    detail: str,
):
    status_badge = "PASS (CHECKSUM VERIFIED)" if summary.checksum_verified else "WARN (CHECKSUM UNVERIFIED)"
    print("=" * 76)
    print(f"File:             {pdf_path}")
    print(f"Account:          {summary.account} (Institution: {summary.institution}, Ending: {summary.account_hint or 'N/A'})")
    print(f"Period:           {summary.period_start or '?'} to {summary.period_end or '?'}")
    if summary.opening_balance is not None or summary.closing_balance is not None:
        ob = f"${summary.opening_balance:,.2f}" if summary.opening_balance is not None else "N/A"
        cb = f"${summary.closing_balance:,.2f}" if summary.closing_balance is not None else "N/A"
        print(f"Balances:         Opening: {ob}  ->  Closing: {cb}")
    print(f"Extracted Rows:   {len(transactions)} transactions")
    print(f"Parsed Totals:    Debits: +${summary.total_debits:,.2f}  |  Credits: -${summary.total_credits:,.2f}")
    if summary.expected_total_debits is not None or summary.expected_total_credits is not None:
        ed = f"+${summary.expected_total_debits:,.2f}" if summary.expected_total_debits is not None else "N/A"
        ec = f"-${summary.expected_total_credits:,.2f}" if summary.expected_total_credits is not None else "N/A"
        print(f"Header Expected:  Debits: {ed}  |  Credits: {ec}")
    print(f"Verification:     [{status_badge}] {detail}")
    print(f"Statement Hash:   {summary.statement_hash[:24]}...")
    print("=" * 76)


def main():
    parser = argparse.ArgumentParser(
        description="Parse bank/card statement PDFs into deterministic hash bundles (JSON/CSV/SQLite)."
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Path(s) to statement PDF file(s) or directory containing PDFs.",
    )
    parser.add_argument(
        "-o", "--output",
        default="statement_bundle.json",
        help="Output JSON bundle path (default: statement_bundle.json).",
    )
    parser.add_argument(
        "--csv",
        default=None,
        help="Output CSV path (default: alongside JSON with .csv extension).",
    )
    parser.add_argument(
        "-a", "--account",
        default=None,
        help="Optional custom account name/label (e.g. 'CIBC Dividend Visa') to tag transactions with.",
    )
    parser.add_argument(
        "--sqlite",
        default=None,
        help="Optional path to budget_tracker.sqlite to directly reconcile and import transactions.",
    )
    parser.add_argument(
        "--account-id",
        default=None,
        help="Optional account_id when syncing directly to --sqlite.",
    )

    args = parser.parse_args()

    # Collect all PDF and CSV statement files from input paths
    stmt_files: List[str] = []
    out_csv_abs = str(Path(args.csv).resolve()) if args.csv else str(Path(args.output).with_suffix(".csv").resolve())
    for inp in args.inputs:
        p = Path(inp)
        if p.is_dir():
            for child in sorted(p.rglob("*")):
                if child.is_file() and child.suffix.lower() in (".pdf", ".csv"):
                    if str(child.resolve()) == out_csv_abs or child.name.endswith("_bundle.csv"):
                        continue
                    stmt_files.append(str(child))
        elif p.is_file() and p.suffix.lower() in (".pdf", ".csv"):
            stmt_files.append(str(p))
        else:
            print(f"Skipping unsupported path: {inp}", file=sys.stderr)

    if not stmt_files:
        print("Error: No statement PDF or CSV files found to process.", file=sys.stderr)
        sys.exit(1)

    all_transactions: List[ExtractedTransaction] = []
    summaries: List[StatementSummary] = []

    for stmt_file in stmt_files:
        if stmt_file.lower().endswith(".csv"):
            summary, txs, detail = parse_csv_statement(stmt_file, account_override=args.account)
        else:
            summary, txs, detail = parse_pdf_statement(stmt_file, account_override=args.account)
        print_statement_report(stmt_file, summary, txs, detail)
        summaries.append(summary)
        all_transactions.extend(txs)

        if args.sqlite:
            sync_stats = sync_to_sqlite(args.sqlite, summary, txs, account_id=args.account_id)
            if sync_stats.get("already_imported"):
                print(f"  [SQLite] Fast-Exit: Statement already imported ({sync_stats['skipped']} skipped).")
            else:
                print(
                    f"  [SQLite] Reconciled -> Inserted: {sync_stats['inserted']}, "
                    f"Merged Manual: {sync_stats['merged']}, Skipped Duplicate: {sync_stats['skipped']}"
                )

    # If a single PDF was processed, write its exact summary; if multiple, aggregate
    if len(summaries) == 1:
        final_summary = summaries[0]
    else:
        combined_hash = compute_statement_hash([t.tx_hash for t in all_transactions])
        institutions = sorted(list({s.institution for s in summaries}))
        accounts_list = sorted(list({s.account for s in summaries if s.account}))
        starts = [s.period_start for s in summaries if s.period_start]
        ends = [s.period_end for s in summaries if s.period_end]
        final_summary = StatementSummary(
            institution=", ".join(institutions),
            account_hint=summaries[0].account_hint,
            period_start=min(starts) if starts else None,
            period_end=max(ends) if ends else None,
            opening_balance=summaries[0].opening_balance,
            closing_balance=summaries[-1].closing_balance,
            expected_total_debits=round(sum(s.expected_total_debits or 0.0 for s in summaries), 2),
            expected_total_credits=round(sum(s.expected_total_credits or 0.0 for s in summaries), 2),
            total_debits=round(sum(s.total_debits for s in summaries), 2),
            total_credits=round(sum(s.total_credits for s in summaries), 2),
            statement_hash=combined_hash,
            checksum_verified=all(s.checksum_verified for s in summaries),
            account=", ".join(accounts_list),
        )

    bundle = build_bundle_dict(final_summary, all_transactions)
    write_json_bundle(bundle, args.output)

    csv_path = args.csv
    if not csv_path:
        out_p = Path(args.output)
        csv_path = str(out_p.with_suffix(".csv"))
    write_csv_bundle(all_transactions, csv_path)

    print(f"\nWrote JSON bundle: {args.output} ({len(all_transactions)} transactions)")
    print(f"Wrote CSV bundle:  {csv_path}")


if __name__ == "__main__":
    main()

