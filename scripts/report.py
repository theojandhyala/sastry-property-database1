#!/usr/bin/env python3
"""Run sql/queries.sql against the database without needing the sqlite3 CLI.

    python3 scripts/report.py                 # all reports
    python3 scripts/report.py --sql "SELECT * FROM v_property_overview"

The .print / .headers / .mode dot-commands in queries.sql are sqlite3 CLI
directives; they are honoured (.print) or ignored here, so the same file works
either way.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "data" / "property.db"
DEFAULT_SQL = REPO_ROOT / "sql" / "queries.sql"


def render(cursor) -> str:
    """Format a result set as a fixed-width table."""
    rows = cursor.fetchall()
    if cursor.description is None:
        return ""
    headers = [d[0] for d in cursor.description]
    if not rows:
        return "  (no rows)"

    def cell(value):
        if value is None:
            return ""
        if isinstance(value, float):
            return f"{value:,.2f}".rstrip("0").rstrip(".") if value % 1 else f"{value:,.0f}"
        if isinstance(value, int):
            return f"{value:,}"
        return str(value)

    table = [headers] + [[cell(v) for v in row] for row in rows]
    widths = [max(len(r[i]) for r in table) for i in range(len(headers))]
    rule = "  " + "-+-".join("-" * w for w in widths)
    out = ["  " + " | ".join(h.ljust(w) for h, w in zip(headers, widths)), rule]
    out += ["  " + " | ".join(c.ljust(w) for c, w in zip(row, widths)) for row in table[1:]]
    out.append(f"  ({len(rows)} row{'s' if len(rows) != 1 else ''})")
    return "\n".join(out)


def statements(sql_text: str):
    """Yield ('print', text) or ('sql', statement) in file order."""
    buffer: list[str] = []
    for line in sql_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        if stripped.startswith("."):
            if buffer and "".join(buffer).strip():
                yield "sql", "\n".join(buffer)
                buffer = []
            if stripped.startswith(".print"):
                yield "print", stripped[len(".print"):].strip()
            continue
        buffer.append(line)
        if stripped.endswith(";"):
            yield "sql", "\n".join(buffer)
            buffer = []
    if "".join(buffer).strip():
        yield "sql", "\n".join(buffer)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--file", type=Path, default=DEFAULT_SQL,
                        help="SQL file to run (default: %(default)s)")
    parser.add_argument("--sql", help="run this single statement instead of --file")
    args = parser.parse_args()

    if not args.db.exists():
        sys.exit(f"{args.db} not found - run scripts/import_xlsx.py first")

    conn = sqlite3.connect(args.db)
    try:
        if args.sql:
            print(render(conn.execute(args.sql)))
            return 0
        for kind, payload in statements(args.file.read_text()):
            if kind == "print":
                print(f"\n{payload}" if payload else "")
            else:
                print(render(conn.execute(payload)))
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
