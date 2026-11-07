import csv
import re
from datetime import datetime, timedelta
from difflib import SequenceMatcher
from typing import List, Dict, Tuple, Optional
from db import DatabaseManager
from classifier import OllamaClassifier

def clean_merchant_name(name: str) -> str:
    """
    Cleans up common noise in bank transaction description strings
    (e.g. numbers, transaction codes, locations, dates).
    """
    # Convert to lowercase
    name = name.lower()
    # Remove dates (e.g., 10/24, 10-24, 20261024)
    name = re.sub(r'\b\d{1,2}[/\-]\d{1,2}\b', '', name)
    name = re.sub(r'\b\d{4}\d{2}\d{2}\b', '', name)
    # Remove common merchant postfixes like "Inc", "Corp", "Llc", "Store", "Shop", etc.
    name = re.sub(r'\b(inc|corp|llc|co|store|shop|ltd)\b', '', name)
    # Remove random-looking string of numbers or hex codes (e.g., SOH 10293, #4392)
    name = re.sub(r'\b(?=\w*\d)\w{5,}\b', '', name)
    name = re.sub(r'\b\d{3,}\b', '', name)
    name = re.sub(r'#\d+', '', name)
    # Remove extra whitespace and punctuation
    name = re.sub(r'[^\w\s]', ' ', name)
    name = ' '.join(name.split())
    return name

def calculate_similarity(s1: str, s2: str) -> float:
    """
    Calculates sequence matcher similarity score between two cleaned merchant names.
    """
    c1 = clean_merchant_name(s1)
    c2 = clean_merchant_name(s2)
    if not c1 or not c2:
        return 0.0
    # Direct substring matches
    if c1 in c2 or c2 in c1:
        return 0.9
    return SequenceMatcher(None, c1, c2).ratio()

class CSVIngestor:
    def __init__(self, db_manager: DatabaseManager, classifier: OllamaClassifier):
        self.db = db_manager
        self.classifier = classifier

    def parse_csv(self, filepath: str) -> List[Dict]:
        """
        Parses CSV file and tries to auto-detect Date, Amount, and Merchant columns.
        Returns a list of dicts: [{'date': 'YYYY-MM-DD', 'amount': 12.34, 'merchant': 'name'}]
        """
        transactions = []
        with open(filepath, mode='r', encoding='utf-8-sig') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            if not header:
                return []
            
            # Helper to match header column indices
            col_map = self._detect_columns(header)
            
            # If date, amount, or merchant columns not found, raise error or prompt user
            if col_map['date'] is None or col_map['amount'] is None or col_map['merchant'] is None:
                print("\nCould not automatically map all columns. Available headers:")
                for idx, col in enumerate(header):
                    print(f"  {idx}: {col}")
                
                col_map['date'] = self._prompt_column_idx(header, "Date")
                col_map['merchant'] = self._prompt_column_idx(header, "Merchant/Description")
                col_map['amount'] = self._prompt_column_idx(header, "Amount")
                
                # Check for debit/credit column split
                is_split = input("Are debit and credit split into separate columns? (y/n): ").strip().lower() == 'y'
                if is_split:
                    col_map['credit'] = self._prompt_column_idx(header, "Credit (Income) Amount")
                    col_map['debit'] = col_map['amount']
                    col_map['amount'] = None
            
            for row_idx, row in enumerate(reader):
                if not row or len(row) <= max(filter(lambda x: x is not None, col_map.values())):
                    continue
                try:
                    # Parse Date
                    raw_date = row[col_map['date']].strip()
                    parsed_date = self._parse_date_string(raw_date)
                    
                    # Parse Amount
                    if col_map.get('credit') is not None and col_map.get('debit') is not None:
                        # Split debit/credit columns
                        credit_str = row[col_map['credit']].strip().replace('$', '').replace(',', '')
                        debit_str = row[col_map['debit']].strip().replace('$', '').replace(',', '')
                        
                        credit = float(credit_str) if credit_str else 0.0
                        debit = float(debit_str) if debit_str else 0.0
                        
                        if credit > 0:
                            # Income (represented as negative in db)
                            amount = -credit
                        else:
                            # Expense (represented as positive in db)
                            amount = debit
                    else:
                        amount_str = row[col_map['amount']].strip().replace('$', '').replace(',', '')
                        # Standard representation: expenses are positive, credit/income negative.
                        # Some banks output expenses as negative. Let's see if we need to invert.
                        # We will parse float first.
                        amount = float(amount_str)
                    
                    merchant = row[col_map['merchant']].strip()
                    
                    if not merchant or not parsed_date:
                        continue
                        
                    transactions.append({
                        'date': parsed_date,
                        'amount': amount,
                        'merchant': merchant
                    })
                except Exception as e:
                    # Skip rows with parsing errors (e.g. headers, totals, format differences)
                    continue
        
        return transactions

    def _detect_columns(self, header: List[str]) -> Dict[str, Optional[int]]:
        col_map = {'date': None, 'amount': None, 'merchant': None}
        
        date_patterns = [r'\bdate\b', r'posted.*date', r'trans.*date', r'date.*trans']
        amount_patterns = [r'\bamount\b', r'\bvalue\b', r'\bsum\b', r'debit']
        merchant_patterns = [r'desc', r'merchant', r'payee', r'name', r'memo', r'details']
        
        for idx, col in enumerate(header):
            col_lower = col.lower()
            
            # Check Date
            if col_map['date'] is None:
                if any(re.search(pat, col_lower) for pat in date_patterns):
                    col_map['date'] = idx
            
            # Check Amount
            if col_map['amount'] is None:
                if any(re.search(pat, col_lower) for pat in amount_patterns):
                    col_map['amount'] = idx
            
            # Check Merchant
            if col_map['merchant'] is None:
                if any(re.search(pat, col_lower) for pat in merchant_patterns):
                    col_map['merchant'] = idx
                    
        return col_map

    def _prompt_column_idx(self, header: List[str], label: str) -> int:
        while True:
            try:
                val = input(f"Enter the column number for {label}: ").strip()
                idx = int(val)
                if 0 <= idx < len(header):
                    return idx
                print(f"Please enter a number between 0 and {len(header) - 1}.")
            except ValueError:
                print("Invalid input. Please enter an integer.")

    def _parse_date_string(self, date_str: str) -> Optional[str]:
        date_formats = [
            '%Y-%m-%d', '%m/%d/%Y', '%m/%d/%y', '%d/%m/%Y', '%d/%m/%y',
            '%Y/%m/%d', '%b %d, %Y', '%d-%b-%Y', '%d-%b-%y'
        ]
        for fmt in date_formats:
            try:
                dt = datetime.strptime(date_str, fmt)
                return dt.strftime('%Y-%m-%d')
            except ValueError:
                continue
        return None

    def reconcile_transaction(self, tx: Dict) -> Tuple[str, Optional[Dict]]:
        """
        Reconciles a single CSV transaction against the database.
        Returns:
          - status: 'duplicate' (exact/fuzzy match found), 'manual_match' (needs classification/prompts)
          - match_info: transaction dict if exact/fuzzy duplicate, else None
        """
        # Search db for matching transactions within +/- 2 days and exact amount
        potential_matches = self.db.get_transactions_fuzzy_match(tx['amount'], tx['date'], date_margin_days=2)
        
        best_match = None
        best_score = 0.0
        
        for m in potential_matches:
            score = calculate_similarity(tx['merchant'], m['merchant'])
            if score > best_score:
                best_score = score
                best_match = m
                
        # If similarity score is high, we mark it as duplicate
        if best_match and best_score >= 0.75:
            return 'duplicate', best_match
            
        return 'new', None
