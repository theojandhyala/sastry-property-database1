#!/usr/bin/env python3
"""Reconcile the built database against the source workbook.

    python3 scripts/verify.py

Checks that every sheet's populated rows made it into the matching table, that
the key money totals agree cell-for-cell, and that referential integrity holds.
Exits non-zero if anything fails, so it can gate a rebuild.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

import openpyxl

REPO_ROOT = Path(__file__).resolve().parent.parent
XLSX = REPO_ROOT / "data" / "source" / "landlord_10_property_database.xlsx"
DB = REPO_ROOT / "data" / "property.db"

# sheet name -> table name
SHEET_TABLE = {
    "Landlords": "landlord",
    "Properties": "property",
    "Tenants": "tenant",
    "Tenancies": "tenancy",
    "Rent Payments": "rent_payment",
    "Maintenance": "maintenance",
    "Certificates": "certificate",
    "Mortgages": "mortgage",
    "Contractors": "contractor",
}

failures: list[str] = []


def check(label: str, expected, actual) -> None:
    ok = expected == actual
    print(f"  {'PASS' if ok else 'FAIL'}  {label:<44} expected={expected} actual={actual}")
    if not ok:
        failures.append(label)


def sheet_rows(sheet) -> int:
    return sum(1 for r in sheet.iter_rows(min_row=2, values_only=True)
               if r and r[0] is not None and str(r[0]).strip())


def sheet_sum(sheet, col_index: int) -> float:
    total = 0.0
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if r and r[0] is not None and isinstance(r[col_index], (int, float)):
            total += float(r[col_index])
    return round(total, 2)


def main() -> int:
    if not DB.exists():
        sys.exit(f"{DB} not found - run scripts/import_xlsx.py first")

    wb = openpyxl.load_workbook(XLSX, data_only=True)
    conn = sqlite3.connect(DB)

    print("Row counts")
    for sheet_name, table in SHEET_TABLE.items():
        check(f"{sheet_name} -> {table}",
              sheet_rows(wb[sheet_name]),
              conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])

    print("\nTotals")
    props = wb["Properties"]
    check("sum(property.monthly_rent)", sheet_sum(props, 8),
          round(conn.execute("SELECT SUM(monthly_rent) FROM property").fetchone()[0], 2))
    check("sum(property annual rent) = monthly * 12", sheet_sum(props, 10),
          round(conn.execute("SELECT SUM(monthly_rent * 12) FROM property").fetchone()[0], 2))

    pay = wb["Rent Payments"]
    check("sum(rent_payment.amount_due)", sheet_sum(pay, 5),
          round(conn.execute("SELECT SUM(amount_due) FROM rent_payment").fetchone()[0], 2))
    check("sum(rent_payment.amount_paid)", sheet_sum(pay, 6),
          round(conn.execute("SELECT SUM(amount_paid) FROM rent_payment").fetchone()[0], 2))
    check("arrears", sheet_sum(pay, 8),
          round(conn.execute("SELECT SUM(amount_due - amount_paid) FROM rent_payment"
                             " WHERE amount_due > amount_paid").fetchone()[0], 2))

    mort = wb["Mortgages"]
    check("sum(mortgage.balance)", sheet_sum(mort, 3),
          round(conn.execute("SELECT SUM(balance) FROM mortgage").fetchone()[0], 2))
    check("sum(mortgage.monthly_payment)", sheet_sum(mort, 4),
          round(conn.execute("SELECT SUM(monthly_payment) FROM mortgage").fetchone()[0], 2))

    print("\nIntegrity")
    check("foreign key violations", [], conn.execute("PRAGMA foreign_key_check").fetchall())
    check("tenancies with resolved rent", 0,
          conn.execute("SELECT COUNT(*) FROM tenancy WHERE monthly_rent IS NULL").fetchone()[0])
    check("every property has a mortgage row", 0,
          conn.execute("SELECT COUNT(*) FROM property p WHERE NOT EXISTS"
                       " (SELECT 1 FROM mortgage m WHERE m.property_id = p.property_id)"
                       ).fetchone()[0])

    issues = conn.execute("SELECT COUNT(*) FROM v_data_quality_issues").fetchone()[0]
    conn.close()

    print(f"\n{len(failures)} failure(s); {issues} data quality issue(s) reported by "
          "v_data_quality_issues (informational, inherited from the workbook)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
