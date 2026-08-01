-- Example queries. Run with:  sqlite3 -box data/property.db < sql/queries.sql

.headers on
.mode box

.print == Portfolio dashboard ==
SELECT metric, value FROM v_portfolio_dashboard ORDER BY sort_order;

.print
.print == Properties, tenant and mortgage ==
SELECT property_id, address, property_type, bedrooms, status, monthly_rent,
       current_tenant_name, tenancy_end_date, monthly_gross_margin
FROM v_property_overview
ORDER BY property_id;

.print
.print == Tenancies ending in the next 90 days ==
SELECT tenancy_id, property_id, tenant_name, end_date, days_to_end, renewal_flag
FROM v_current_tenancies
WHERE days_to_end IS NOT NULL AND days_to_end <= 90
ORDER BY days_to_end;

.print
.print == Who owes money ==
SELECT property_id, address, tenant_name, total_arrears, payments_in_arrears,
       oldest_unpaid_due_date
FROM v_arrears_by_property
ORDER BY total_arrears DESC;

.print
.print == Rent collected by month ==
SELECT due_month,
       COUNT(*)          AS payments,
       SUM(amount_due)   AS due,
       SUM(amount_paid)  AS collected,
       SUM(arrears)      AS outstanding
FROM v_rent_payments
GROUP BY due_month
ORDER BY due_month;

.print
.print == Certificates due for renewal first ==
SELECT property_id, certificate_type, expiry_date, days_to_expiry, current_status
FROM v_certificate_status
ORDER BY expiry_date
LIMIT 15;

.print
.print == Compliance gaps (property missing a required certificate type) ==
SELECT p.property_id, p.address, t.certificate_type AS missing
FROM property p
CROSS JOIN (SELECT 'EPC' AS certificate_type
            UNION ALL SELECT 'Gas Safety'
            UNION ALL SELECT 'EICR') t
WHERE NOT EXISTS (SELECT 1 FROM certificate c
                  WHERE c.property_id = p.property_id
                    AND c.certificate_type = t.certificate_type)
ORDER BY p.property_id, missing;

.print
.print == Open maintenance ==
SELECT maintenance_id, property_id, description, priority, status, days_open,
       cost_estimate, contractor_name
FROM v_open_maintenance
ORDER BY days_open DESC;

.print
.print == Portfolio cashflow (rent in vs mortgage out) ==
SELECT SUM(monthly_rent)                      AS rent_in,
       SUM(mortgage_monthly_payment)          AS mortgage_out,
       SUM(monthly_gross_margin)              AS gross_margin
FROM v_property_overview
WHERE status = 'Occupied';

.print
.print == Data quality issues carried over from the workbook ==
SELECT entity, record_id, issue FROM v_data_quality_issues ORDER BY entity, record_id;
