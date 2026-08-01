-- Landlord property database - reporting views
--
-- These replace the formula columns and the Dashboard sheet of the workbook.
-- Anything the spreadsheet calculated is calculated here instead, so the
-- stored data stays a single source of truth.
--
-- "Today" is DATE('now') (UTC), the equivalent of the workbook's TODAY().

-- Property + its mortgage + who is currently in it.
CREATE VIEW v_property_overview AS
SELECT
    p.property_id,
    p.address,
    p.town_city,
    p.postcode,
    p.property_type,
    p.bedrooms,
    p.status,
    p.monthly_rent,
    p.monthly_rent * 12                       AS annual_rent,
    m.mortgage_id,
    m.lender,
    m.balance                                 AS mortgage_balance,
    m.monthly_payment                         AS mortgage_monthly_payment,
    p.monthly_rent - COALESCE(m.monthly_payment, 0) AS monthly_gross_margin,
    t.tenancy_id                              AS current_tenancy_id,
    tn.tenant_id                              AS current_tenant_id,
    tn.name                                   AS current_tenant_name,
    t.end_date                                AS tenancy_end_date
FROM property p
LEFT JOIN mortgage m ON m.property_id = p.property_id
LEFT JOIN tenancy  t ON t.property_id = p.property_id AND t.status = 'Active'
LEFT JOIN tenant  tn ON tn.tenant_id  = t.tenant_id;

-- Active tenancies with the countdown the workbook kept in "Days to End".
CREATE VIEW v_current_tenancies AS
SELECT
    t.tenancy_id,
    t.property_id,
    p.address,
    t.tenant_id,
    tn.name AS tenant_name,
    tn.phone AS tenant_phone,
    tn.email AS tenant_email,
    t.start_date,
    t.end_date,
    t.monthly_rent,
    t.deposit,
    t.deposit_protected,
    t.status,
    CAST(JULIANDAY(t.end_date) - JULIANDAY(DATE('now')) AS INTEGER) AS days_to_end,
    CASE
        WHEN t.end_date IS NULL THEN NULL
        WHEN JULIANDAY(t.end_date) < JULIANDAY(DATE('now')) THEN 'Expired'
        WHEN JULIANDAY(t.end_date) - JULIANDAY(DATE('now')) <= 60 THEN 'Ending Soon'
        ELSE 'OK'
    END AS renewal_flag
FROM tenancy t
JOIN property p  ON p.property_id = t.property_id
JOIN tenant   tn ON tn.tenant_id  = t.tenant_id
WHERE t.status = 'Active';

-- Rent roll of the let portfolio.
CREATE VIEW v_monthly_rent_roll AS
SELECT
    COUNT(*)                                    AS properties,
    SUM(CASE WHEN status = 'Occupied'  THEN 1 ELSE 0 END) AS occupied,
    SUM(CASE WHEN status = 'Available' THEN 1 ELSE 0 END) AS available,
    SUM(CASE WHEN status = 'Occupied' THEN monthly_rent ELSE 0 END)      AS monthly_rent_roll,
    SUM(CASE WHEN status = 'Occupied' THEN monthly_rent ELSE 0 END) * 12 AS annual_rent_roll,
    SUM(monthly_rent)                           AS monthly_rent_potential,
    SUM(monthly_rent) * 12                      AS annual_rent_potential
FROM property;

-- Payments with the derived arrears and month label.
CREATE VIEW v_rent_payments AS
SELECT
    r.payment_id,
    r.property_id,
    p.address,
    r.tenant_id,
    t.name AS tenant_name,
    r.due_date,
    r.paid_date,
    r.amount_due,
    r.amount_paid,
    r.amount_due - r.amount_paid AS arrears,
    r.status,
    STRFTIME('%Y-%m', r.due_date) AS due_month,
    r.notes
FROM rent_payment r
JOIN property p ON p.property_id = r.property_id
JOIN tenant   t ON t.tenant_id   = r.tenant_id;

-- Outstanding money, worst first.
CREATE VIEW v_arrears_by_property AS
SELECT
    r.property_id,
    p.address,
    r.tenant_id,
    t.name AS tenant_name,
    SUM(r.amount_due - r.amount_paid) AS total_arrears,
    COUNT(*)                          AS payments_in_arrears,
    MIN(r.due_date)                   AS oldest_unpaid_due_date
FROM rent_payment r
JOIN property p ON p.property_id = r.property_id
JOIN tenant   t ON t.tenant_id   = r.tenant_id
WHERE r.amount_due > r.amount_paid
GROUP BY r.property_id, p.address, r.tenant_id, t.name;

-- Compliance: recalculates Valid / Expiring Soon / Expired against today.
CREATE VIEW v_certificate_status AS
SELECT
    c.certificate_id,
    c.property_id,
    p.address,
    c.certificate_type,
    c.issue_date,
    c.expiry_date,
    c.status AS recorded_status,
    CASE
        WHEN c.expiry_date IS NULL THEN 'Unknown'
        WHEN JULIANDAY(c.expiry_date) < JULIANDAY(DATE('now')) THEN 'Expired'
        WHEN JULIANDAY(c.expiry_date) - JULIANDAY(DATE('now')) <= 60 THEN 'Expiring Soon'
        ELSE 'Valid'
    END AS current_status,
    CAST(JULIANDAY(c.expiry_date) - JULIANDAY(DATE('now')) AS INTEGER) AS days_to_expiry,
    c.provider,
    c.cost
FROM certificate c
JOIN property p ON p.property_id = c.property_id;

-- Work in flight, with the contractor to chase.
CREATE VIEW v_open_maintenance AS
SELECT
    m.maintenance_id,
    m.property_id,
    p.address,
    m.reported_date,
    CAST(JULIANDAY(DATE('now')) - JULIANDAY(m.reported_date) AS INTEGER) AS days_open,
    m.description,
    m.priority,
    m.status,
    m.cost_estimate,
    c.contractor_id,
    c.name  AS contractor_name,
    c.trade AS contractor_trade,
    c.insurance_checked
FROM maintenance m
JOIN property p ON p.property_id = m.property_id
LEFT JOIN contractor c ON c.contractor_id = m.contractor_id
WHERE m.status IN ('Open', 'In Progress', 'Deferred');

-- The Dashboard sheet, rebuilt from the tables.
CREATE VIEW v_portfolio_dashboard AS
SELECT 1 AS sort_order, 'Total Properties'      AS metric, (SELECT COUNT(*) FROM property) AS value
UNION ALL SELECT 2, 'Occupied Properties',  (SELECT COUNT(*) FROM property WHERE status = 'Occupied')
UNION ALL SELECT 3, 'Available Properties', (SELECT COUNT(*) FROM property WHERE status = 'Available')
-- Contracted rent counts let units only. The workbook's "Monthly Rent Roll"
-- (18,900) summed all 10 units, so it is kept here as the potential figure.
UNION ALL SELECT 4, 'Monthly Rent Roll (let)',      (SELECT monthly_rent_roll FROM v_monthly_rent_roll)
UNION ALL SELECT 5, 'Annual Rent Roll (let)',       (SELECT annual_rent_roll  FROM v_monthly_rent_roll)
UNION ALL SELECT 6, 'Monthly Rent Potential (all)', (SELECT monthly_rent_potential FROM v_monthly_rent_roll)
UNION ALL SELECT 7, 'Annual Rent Potential (all)',  (SELECT annual_rent_potential  FROM v_monthly_rent_roll)
UNION ALL SELECT 8, 'Current Arrears',      (SELECT COALESCE(SUM(amount_due - amount_paid), 0)
                                             FROM rent_payment WHERE amount_due > amount_paid)
UNION ALL SELECT 9, 'Open Maintenance',     (SELECT COUNT(*) FROM maintenance WHERE status = 'Open')
UNION ALL SELECT 10,'Maintenance Spend',    (SELECT COALESCE(SUM(actual_cost), 0) FROM maintenance)
UNION ALL SELECT 11,'Mortgage Balance',     (SELECT COALESCE(SUM(balance), 0) FROM mortgage)
UNION ALL SELECT 12,'Monthly Mortgage Cost',(SELECT COALESCE(SUM(monthly_payment), 0) FROM mortgage)
UNION ALL SELECT 13,'Certificates Expiring (60d)',
                                            (SELECT COUNT(*) FROM v_certificate_status
                                             WHERE current_status IN ('Expiring Soon', 'Expired'));

-- Problems carried over from the workbook, surfaced rather than silently fixed.
CREATE VIEW v_data_quality_issues AS
SELECT 'tenancy' AS entity, t.tenancy_id AS record_id,
       'End date is before start date (' || t.start_date || ' -> ' || t.end_date || ')' AS issue
FROM tenancy t
WHERE t.end_date IS NOT NULL AND t.start_date IS NOT NULL AND t.end_date < t.start_date

UNION ALL
SELECT 'property', p.property_id, 'Status is Occupied but has no active tenancy'
FROM property p
WHERE p.status = 'Occupied'
  AND NOT EXISTS (SELECT 1 FROM tenancy t
                  WHERE t.property_id = p.property_id AND t.status = 'Active')

UNION ALL
SELECT 'property', p.property_id, 'Status is Available but has an active tenancy'
FROM property p
WHERE p.status = 'Available'
  AND EXISTS (SELECT 1 FROM tenancy t
              WHERE t.property_id = p.property_id AND t.status = 'Active')

UNION ALL
SELECT 'tenancy', t.tenancy_id,
       'Tenancy rent (' || t.monthly_rent || ') differs from property rent (' || p.monthly_rent || ')'
FROM tenancy t
JOIN property p ON p.property_id = t.property_id
WHERE t.status = 'Active' AND t.monthly_rent IS NOT NULL
  AND t.monthly_rent <> p.monthly_rent

UNION ALL
SELECT 'certificate', c.certificate_id,
       'Recorded status "' || c.status || '" but certificate is ' || v.current_status
FROM certificate c
JOIN v_certificate_status v ON v.certificate_id = c.certificate_id
WHERE c.status <> v.current_status

UNION ALL
SELECT 'maintenance', m.maintenance_id, 'Contractor has no insurance check recorded as passed'
FROM maintenance m
JOIN contractor c ON c.contractor_id = m.contractor_id
WHERE m.status IN ('Open', 'In Progress') AND COALESCE(c.insurance_checked, 0) = 0

UNION ALL
SELECT 'property', p.property_id, 'Occupied property has no rent payment in the last 60 days'
FROM property p
WHERE p.status = 'Occupied'
  AND NOT EXISTS (SELECT 1 FROM rent_payment r
                  WHERE r.property_id = p.property_id
                    AND JULIANDAY(DATE('now')) - JULIANDAY(r.due_date) <= 60);
