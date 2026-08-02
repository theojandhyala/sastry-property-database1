#!/usr/bin/env python3
"""Generate the static GitHub Pages site from the database.

    python3 scripts/build_site.py

Reads data/property.db and writes docs/index.html - a single self-contained
page (no external requests) that GitHub Pages can serve straight from the
docs/ folder. The database is queried at build time and the results are
embedded as JSON, so the published page always matches the last import.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "data" / "property.db"
DEFAULT_OUT = REPO_ROOT / "docs"
TEMPLATE = REPO_ROOT / "site" / "template.html"

# Every dataset the page renders. Kept here so the page stays a dumb renderer.
QUERIES: dict[str, str] = {
    "dashboard": """
        SELECT metric, value FROM v_portfolio_dashboard ORDER BY sort_order
    """,
    "rent_by_month": """
        SELECT due_month,
               SUM(amount_due)  AS due,
               SUM(amount_paid) AS collected,
               SUM(arrears)     AS outstanding
        FROM v_rent_payments
        GROUP BY due_month
        ORDER BY due_month
    """,
    "properties": """
        SELECT property_id, address, property_type, bedrooms, status, monthly_rent,
               mortgage_monthly_payment, monthly_gross_margin, current_tenant_name,
               tenancy_end_date
        FROM v_property_overview
        ORDER BY property_id
    """,
    "tenancies": """
        SELECT tenancy_id, property_id, tenant_name, tenant_phone, start_date,
               end_date, monthly_rent, deposit, days_to_end, renewal_flag
        FROM v_current_tenancies
        ORDER BY end_date
    """,
    "arrears": """
        SELECT property_id, address, tenant_name, total_arrears,
               payments_in_arrears, oldest_unpaid_due_date
        FROM v_arrears_by_property
        ORDER BY total_arrears DESC
    """,
    "certificates": """
        SELECT property_id, certificate_type, issue_date, expiry_date,
               days_to_expiry, current_status
        FROM v_certificate_status
        ORDER BY expiry_date, property_id
    """,
    "maintenance": """
        SELECT m.maintenance_id, m.property_id, m.description, m.priority, m.status,
               m.reported_date, m.cost_estimate, m.actual_cost, c.name AS contractor
        FROM maintenance m
        LEFT JOIN contractor c ON c.contractor_id = m.contractor_id
        ORDER BY m.reported_date DESC
    """,
    "issues": """
        SELECT entity, record_id, issue FROM v_data_quality_issues
        ORDER BY entity, record_id
    """,
    "tables": """
        SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name
    """,
}


def fetch(conn: sqlite3.Connection, sql: str) -> list[dict]:
    cursor = conn.execute(sql)
    columns = [d[0] for d in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def collect(db_path: Path) -> dict:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        payload = {key: fetch(conn, sql) for key, sql in QUERIES.items()}
        payload["counts"] = {
            row["name"]: conn.execute(f"SELECT COUNT(*) FROM {row['name']}").fetchone()[0]
            for row in payload.pop("tables")
        }
        payload["generated"] = dt.datetime.now(dt.timezone.utc).strftime("%d %B %Y")
    finally:
        conn.close()
    return payload


def build(db_path: Path, out_dir: Path) -> None:
    if not db_path.exists():
        sys.exit(f"{db_path} not found - run scripts/import_xlsx.py first")

    data = collect(db_path)
    html = TEMPLATE.read_text().replace(
        "/*__DATA__*/null",
        json.dumps(data, separators=(",", ":"), default=str),
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "index.html").write_text(html)
    (out_dir / ".nojekyll").write_text("")  # serve the files as-is

    # Ship the artefacts so the site can offer them as downloads.
    shutil.copy(db_path, out_dir / "property.db")
    shutil.copy(REPO_ROOT / "data" / "source" / "landlord_10_property_database.xlsx",
                out_dir / "landlord_10_property_database.xlsx")

    size_kb = (out_dir / "index.html").stat().st_size / 1024
    print(f"Built {out_dir / 'index.html'} ({size_kb:.0f} KB)")
    for key, rows in data.items():
        if isinstance(rows, list):
            print(f"  {key:<14} {len(rows):>3} rows")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    build(args.db, args.out)


if __name__ == "__main__":
    main()
