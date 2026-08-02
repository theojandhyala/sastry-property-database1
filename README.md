# Landlord Property Database

The `landlord_10_property_database.xlsx` workbook converted into a normalised
SQLite database, with a repeatable importer, reporting views and a
reconciliation check.

## Quick start

```bash
pip install -r requirements.txt

python3 scripts/import_xlsx.py     # build data/property.db from the workbook
python3 scripts/verify.py          # reconcile the database against the workbook
python3 scripts/report.py          # run every report in sql/queries.sql
python3 scripts/build_site.py      # regenerate the published dashboard in docs/
```

The database is also queryable with any SQLite client:

```bash
sqlite3 -box data/property.db "SELECT * FROM v_portfolio_dashboard ORDER BY sort_order"
sqlite3 -box data/property.db < sql/queries.sql
```

`scripts/report.py` exists so the same `sql/queries.sql` runs on machines
without the `sqlite3` CLI installed. It also takes an ad-hoc query:

```bash
python3 scripts/report.py --sql "SELECT * FROM v_arrears_by_property"
```

## The website

The portfolio dashboard is published with GitHub Pages from the `docs/` folder:

**https://theojandhyala.github.io/sastry-property-database1/**

It is one self-contained HTML file — no frameworks, no external requests — with
stat tiles, two charts, and every table sortable and filterable. The `.db` and
the source `.xlsx` are downloadable from the page itself.

Regenerate it after any re-import:

```bash
python3 scripts/import_xlsx.py && python3 scripts/build_site.py
```

`scripts/build_site.py` queries the database and injects the results as JSON
into `site/template.html`, so the published page can never disagree with the
data — edit the template for looks, the SQL for numbers.

If Pages is not switched on yet: **Settings → Pages → Source: Deploy from a
branch**, then pick the branch holding this work and the **`/docs`** folder.

## Layout

| Path | What it is |
| --- | --- |
| `data/source/landlord_10_property_database.xlsx` | The original workbook, unmodified |
| `data/property.db` | The built SQLite database (regenerate any time) |
| `sql/schema.sql` | Tables, keys, constraints, indexes |
| `sql/views.sql` | Reporting views, incl. the rebuilt dashboard |
| `sql/queries.sql` | Example reports |
| `scripts/import_xlsx.py` | Workbook → database ETL |
| `scripts/verify.py` | Row counts and money totals reconciled to the workbook |
| `scripts/report.py` | Runs `sql/queries.sql` without the sqlite3 CLI |
| `scripts/build_site.py` | Database → `docs/index.html` |
| `site/template.html` | The page shell the site is built from |
| `docs/` | The published site (generated — do not hand-edit) |

## Schema

```
landlord ──< property ──1:1── mortgage
                │
                ├──< tenancy >── tenant
                ├──< rent_payment >── tenant
                ├──< maintenance >── contractor
                └──< certificate

enum_value   (the workbook's "Lists" sheet: dropdown values by category)
```

Ten tables, all loaded from a sheet of the same name:

| Table | Rows | From sheet |
| --- | ---: | --- |
| `landlord` | 1 | Landlords |
| `property` | 10 | Properties |
| `tenant` | 10 | Tenants |
| `contractor` | 4 | Contractors |
| `mortgage` | 10 | Mortgages |
| `tenancy` | 8 | Tenancies |
| `rent_payment` | 48 | Rent Payments |
| `maintenance` | 4 | Maintenance |
| `certificate` | 30 | Certificates |
| `enum_value` | 32 | Lists |

Conventions:

- Spreadsheet business keys (`P001`, `T001`, `TN001`) are kept as primary keys,
  so every row is traceable back to the workbook.
- Dates are ISO-8601 text (`YYYY-MM-DD`), so SQLite's date functions work.
- Money is `NUMERIC` in pounds; `mortgage.interest_rate` is a decimal fraction
  (`0.052` = 5.2%).
- Yes/No columns become `0`/`1` integers (`deposit_protected`,
  `insurance_checked`).
- Foreign keys are declared and enforced; the import aborts on a violation.

## Views

| View | Answers |
| --- | --- |
| `v_portfolio_dashboard` | The Dashboard sheet, recomputed from the tables |
| `v_property_overview` | Each property with its mortgage, current tenant and gross margin |
| `v_current_tenancies` | Active tenancies with days-to-end and a renewal flag |
| `v_monthly_rent_roll` | Let vs. potential rent roll, monthly and annual |
| `v_rent_payments` | Payments with derived arrears and month |
| `v_arrears_by_property` | Who owes what, worst first |
| `v_certificate_status` | Compliance status recomputed against today's date |
| `v_open_maintenance` | Open jobs, days outstanding, contractor to chase |
| `v_data_quality_issues` | Problems inherited from the workbook |

## What changed in the conversion

**Formula columns are not stored.** Anything the workbook calculated is a view
instead, so the numbers cannot drift from the data:

| Workbook column | Replaced by |
| --- | --- |
| `Properties.Annual Rent` | `v_property_overview.annual_rent` |
| `Rent Payments.Arrears` | `v_rent_payments.arrears` |
| `Rent Payments.Month` | `v_rent_payments.due_month` |
| `Tenancies.Days to End` | `v_current_tenancies.days_to_end` |
| Dashboard sheet | `v_portfolio_dashboard` |

**Broken formulas were repaired at load.** The Tenancies sheet stored rent and
deposit as `XLOOKUP` written by a non-Excel writer (`_xludf.XLOOKUP`), so all 8
rows read back as `#NAME?`. The importer resolves them from the Properties
sheet — exactly what the formula intended — and says so in its output.

**One duplicated link was collapsed.** The workbook stored `MortgageID` on
Properties *and* `PropertyID` on Mortgages. The database keeps the link once,
on `mortgage.property_id` (unique). The importer compares both directions and
warns on any mismatch; there were none.

**Rent roll is reported two ways.** The workbook's "Monthly Rent Roll" of
£18,900 summed all 10 units, including the 2 vacant ones. The dashboard view
reports both `Monthly Rent Roll (let)` (£15,000, the contracted figure) and
`Monthly Rent Potential (all)` (£18,900, the workbook's figure).

## Data quality

Bad data was loaded as-is and flagged, not silently corrected — run
`python3 scripts/report.py` or query `v_data_quality_issues`. Current findings:

- **4 tenancies end before they start** (`TN002`, `TN004`, `TN006`, `TN008`:
  start 2026-02-01, end 2026-01-31). These look like a mistyped year — 2027-01-31
  is the likely intent, which would also make them 12-month terms like the
  others. Fix in the workbook and re-import, or update the rows directly.
- **2 open jobs are with contractors whose insurance is not confirmed**
  (`RoofCare`, `GardenFix`).
- **8 occupied properties have no rent due in the last 60 days** — the payment
  data stops at June 2026, so July onwards has not been entered.

The schema deliberately has no `CHECK (end_date > start_date)`: it would have
rejected real rows from the source, and the aim was a faithful load with the
problems visible rather than a load that quietly drops data.

## Reconciliation

`scripts/verify.py` checks the load cell-for-cell against the workbook — all 19
checks pass:

- Row counts for all 9 data sheets.
- Money totals: property rent (£18,900/mo, £226,800/yr), rent due (£90,000),
  rent paid (£86,900), arrears (£3,100), mortgage balance (£2,050,000) and
  mortgage payments (£8,650/mo).
- Referential integrity, no unresolved tenancy rents, every property mortgaged.

## Re-importing

The load is idempotent — `scripts/import_xlsx.py` drops and rebuilds every
table, so update the workbook (or point `--xlsx` at a new one) and re-run:

```bash
python3 scripts/import_xlsx.py --xlsx /path/to/updated.xlsx --db data/property.db
python3 scripts/verify.py
```
