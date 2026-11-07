import unittest
import os
import tempfile
from db import DatabaseManager
from ingest import clean_merchant_name, calculate_similarity, CSVIngestor

class TestMacTools(unittest.TestCase):
    def setUp(self):
        # Create a temp database
        self.db_fd, self.db_path = tempfile.mkstemp(suffix=".sqlite")
        # Close file descriptor so sqlite can open it
        os.close(self.db_fd)
        self.db = DatabaseManager(self.db_path)

    def tearDown(self):
        self.db.close()
        os.unlink(self.db_path)

    def test_database_initialization(self):
        categories = self.db.get_categories()
        # Seeded default categories size
        self.assertTrue(len(categories) > 0)
        category_names = [c["name"] for c in categories]
        self.assertIn("Groceries", category_names)
        self.assertIn("Dining", category_names)
        self.assertIn("Income", category_names)

    def test_add_transaction_and_fuzzy_match(self):
        # Find category ID for Groceries
        g_cat = self.db.get_category_by_name("Groceries")
        self.assertIsNotNone(g_cat)
        cat_id = g_cat["id"]

        # Insert transaction
        tx_uuid = self.db.add_transaction(
            date="2026-08-15",
            amount=45.50,
            category_id=cat_id,
            merchant="Trader Joes NYC",
            source="manual"
        )
        self.assertIsNotNone(tx_uuid)

        # Fuzzy match exact date, exact amount
        matches = self.db.get_transactions_fuzzy_match(45.50, "2026-08-15")
        self.assertEqual(len(matches), 1)
        self.assertEqual(matches[0]["uuid"], tx_uuid)

        # Fuzzy match +/- 2 days, exact amount
        matches_minus_2 = self.db.get_transactions_fuzzy_match(45.50, "2026-08-13")
        self.assertEqual(len(matches_minus_2), 1)

        matches_plus_2 = self.db.get_transactions_fuzzy_match(45.50, "2026-08-17")
        self.assertEqual(len(matches_plus_2), 1)

        # Fuzzy match outside margin (+ 3 days)
        matches_plus_3 = self.db.get_transactions_fuzzy_match(45.50, "2026-08-18")
        self.assertEqual(len(matches_plus_3), 0)

        # Fuzzy match wrong amount
        matches_wrong_amt = self.db.get_transactions_fuzzy_match(45.00, "2026-08-15")
        self.assertEqual(len(matches_wrong_amt), 0)

    def test_clean_merchant_name(self):
        self.assertEqual(clean_merchant_name("WHOLEFDS SOH 10293"), "wholefds soh")
        self.assertEqual(clean_merchant_name("Trader Joe's #4928 Inc."), "trader joe s")
        self.assertEqual(clean_merchant_name("Netflix.com Corp 20260817"), "netflix com")
        self.assertEqual(clean_merchant_name("UBER TRIP 10-24 HELP.UBER"), "uber trip help uber")

    def test_calculate_similarity(self):
        # High similarity
        score1 = calculate_similarity("Trader Joe's NYC", "TRADER JOES #4928")
        self.assertTrue(score1 >= 0.75)

        # Substring similarity
        score2 = calculate_similarity("Whole Foods Market", "Whole Foods")
        self.assertTrue(score2 >= 0.75)

        # Low similarity
        score3 = calculate_similarity("Whole Foods", "Netflix")
        self.assertTrue(score3 < 0.3)

    def test_csv_ingestion_and_auto_detect(self):
        # Create a mock CSV file
        csv_fd, csv_path = tempfile.mkstemp(suffix=".csv")
        os.close(csv_fd)
        
        try:
            with open(csv_path, 'w', encoding='utf-8') as f:
                f.write("Transaction Date,Description,Amount\n")
                f.write("2026-08-10,Whole Foods Market,$105.42\n")
                f.write("2026-08-11,Netflix Inc,$15.99\n")
                f.write("2026-08-12,Employer Paycheck,-$2500.00\n") # negative for credit
            
            ingestor = CSVIngestor(self.db, classifier=None)
            txs = ingestor.parse_csv(csv_path)
            
            self.assertEqual(len(txs), 3)
            self.assertEqual(txs[0]['date'], '2026-08-10')
            self.assertEqual(txs[0]['merchant'], 'Whole Foods Market')
            self.assertEqual(txs[0]['amount'], 105.42)
            
            self.assertEqual(txs[2]['merchant'], 'Employer Paycheck')
            self.assertEqual(txs[2]['amount'], -2500.0)
            
        finally:
            os.unlink(csv_path)

if __name__ == "__main__":
    unittest.main()
