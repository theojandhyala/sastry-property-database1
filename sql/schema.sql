-- Landlord property database - schema
--
-- Source: data/source/landlord_10_property_database.xlsx
-- Target: SQLite 3
--
-- Conventions
--   * Business keys from the spreadsheet (P001, T001, ...) are kept as the
--     primary keys so rows stay traceable back to the workbook.
--   * Dates are stored as ISO-8601 TEXT ('YYYY-MM-DD') so SQLite date
--     functions work on them.
--   * Money is stored as NUMERIC (pounds, 2dp).
--   * Columns the workbook computed with formulas (annual rent, arrears,
--     days to end, month label, dashboard totals) are NOT stored. They are
--     recreated as views in sql/views.sql so they cannot drift.

PRAGMA foreign_keys = ON;

DROP VIEW  IF EXISTS v_data_quality_issues;
DROP VIEW  IF EXISTS v_portfolio_dashboard;
DROP VIEW  IF EXISTS v_open_maintenance;
DROP VIEW  IF EXISTS v_certificate_status;
DROP VIEW  IF EXISTS v_arrears_by_property;
DROP VIEW  IF EXISTS v_rent_payments;
DROP VIEW  IF EXISTS v_monthly_rent_roll;
DROP VIEW  IF EXISTS v_current_tenancies;
DROP VIEW  IF EXISTS v_property_overview;

DROP TABLE IF EXISTS certificate;
DROP TABLE IF EXISTS maintenance;
DROP TABLE IF EXISTS rent_payment;
DROP TABLE IF EXISTS tenancy;
DROP TABLE IF EXISTS mortgage;
DROP TABLE IF EXISTS property;
DROP TABLE IF EXISTS tenant;
DROP TABLE IF EXISTS contractor;
DROP TABLE IF EXISTS landlord;
DROP TABLE IF EXISTS enum_value;

-- ---------------------------------------------------------------------------
-- Reference data (the workbook's "Lists" sheet, used for its dropdowns)
-- ---------------------------------------------------------------------------
CREATE TABLE enum_value (
    category    TEXT NOT NULL,   -- e.g. 'Property Type', 'Payment Status'
    value       TEXT NOT NULL,
    sort_order  INTEGER NOT NULL,
    PRIMARY KEY (category, value)
);

-- ---------------------------------------------------------------------------
-- Parties
-- ---------------------------------------------------------------------------
CREATE TABLE landlord (
    landlord_id TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT,
    email       TEXT,
    address     TEXT,
    notes       TEXT
);

CREATE TABLE tenant (
    tenant_id         TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    phone             TEXT,
    email             TEXT,
    emergency_contact TEXT,
    notes             TEXT,
    -- The workbook uses placeholder rows named 'Vacant' for unlet units.
    is_placeholder    INTEGER NOT NULL DEFAULT 0 CHECK (is_placeholder IN (0, 1))
);

CREATE TABLE contractor (
    contractor_id     TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    trade             TEXT,
    phone             TEXT,
    email             TEXT,
    area              TEXT,
    insurance_checked INTEGER CHECK (insurance_checked IN (0, 1)),
    notes             TEXT
);

-- ---------------------------------------------------------------------------
-- Portfolio
-- ---------------------------------------------------------------------------
CREATE TABLE property (
    property_id   TEXT PRIMARY KEY,
    landlord_id   TEXT NOT NULL REFERENCES landlord (landlord_id),
    address       TEXT NOT NULL,
    town_city     TEXT,
    postcode      TEXT,
    property_type TEXT,           -- Flat / House / HMO / Studio / Commercial
    bedrooms      INTEGER CHECK (bedrooms IS NULL OR bedrooms >= 0),
    status        TEXT,           -- Available / Occupied / Maintenance / ...
    monthly_rent  NUMERIC CHECK (monthly_rent IS NULL OR monthly_rent >= 0),
    notes         TEXT
);
CREATE INDEX idx_property_landlord ON property (landlord_id);
CREATE INDEX idx_property_status   ON property (status);

-- The workbook keeps MortgageID on the Properties sheet and PropertyID on the
-- Mortgages sheet. One mortgage per property, so the link lives here only.
CREATE TABLE mortgage (
    mortgage_id     TEXT PRIMARY KEY,
    property_id     TEXT NOT NULL UNIQUE REFERENCES property (property_id),
    lender          TEXT,
    balance         NUMERIC CHECK (balance IS NULL OR balance >= 0),
    monthly_payment NUMERIC CHECK (monthly_payment IS NULL OR monthly_payment >= 0),
    interest_rate   REAL,          -- decimal fraction, 0.052 = 5.2%
    fixed_until     TEXT,          -- ISO date
    notes           TEXT
);

-- ---------------------------------------------------------------------------
-- Lettings
-- ---------------------------------------------------------------------------
CREATE TABLE tenancy (
    tenancy_id        TEXT PRIMARY KEY,
    property_id       TEXT NOT NULL REFERENCES property (property_id),
    tenant_id         TEXT NOT NULL REFERENCES tenant (tenant_id),
    start_date        TEXT,        -- ISO date
    end_date          TEXT,        -- ISO date
    monthly_rent      NUMERIC CHECK (monthly_rent IS NULL OR monthly_rent >= 0),
    deposit           NUMERIC CHECK (deposit IS NULL OR deposit >= 0),
    deposit_protected INTEGER CHECK (deposit_protected IN (0, 1)),
    status            TEXT,        -- Active / Ending Soon / Ended / Prospect
    notes             TEXT
);
CREATE INDEX idx_tenancy_property ON tenancy (property_id);
CREATE INDEX idx_tenancy_tenant   ON tenancy (tenant_id);
CREATE INDEX idx_tenancy_status   ON tenancy (status);

CREATE TABLE rent_payment (
    payment_id  TEXT PRIMARY KEY,
    property_id TEXT NOT NULL REFERENCES property (property_id),
    tenant_id   TEXT NOT NULL REFERENCES tenant (tenant_id),
    due_date    TEXT NOT NULL,     -- ISO date
    paid_date   TEXT,              -- ISO date, NULL when unpaid
    amount_due  NUMERIC NOT NULL CHECK (amount_due >= 0),
    amount_paid NUMERIC NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
    status      TEXT,              -- Paid / Due / Late / Partial
    notes       TEXT
    -- arrears and the 'Mon yyyy' label are derived; see v_rent_payments.
);
CREATE INDEX idx_payment_property ON rent_payment (property_id);
CREATE INDEX idx_payment_tenant   ON rent_payment (tenant_id);
CREATE INDEX idx_payment_due_date ON rent_payment (due_date);

-- ---------------------------------------------------------------------------
-- Compliance and works
-- ---------------------------------------------------------------------------
CREATE TABLE maintenance (
    maintenance_id TEXT PRIMARY KEY,
    property_id    TEXT NOT NULL REFERENCES property (property_id),
    reported_date  TEXT,           -- ISO date
    description    TEXT,
    contractor_id  TEXT REFERENCES contractor (contractor_id),
    priority       TEXT,           -- Low / Medium / High
    status         TEXT,           -- Open / In Progress / Completed / Deferred
    cost_estimate  NUMERIC CHECK (cost_estimate IS NULL OR cost_estimate >= 0),
    actual_cost    NUMERIC CHECK (actual_cost IS NULL OR actual_cost >= 0),
    completed_date TEXT,           -- ISO date
    notes          TEXT
);
CREATE INDEX idx_maintenance_property   ON maintenance (property_id);
CREATE INDEX idx_maintenance_status     ON maintenance (status);
CREATE INDEX idx_maintenance_contractor ON maintenance (contractor_id);

CREATE TABLE certificate (
    certificate_id   TEXT PRIMARY KEY,
    property_id      TEXT NOT NULL REFERENCES property (property_id),
    certificate_type TEXT NOT NULL, -- EPC / Gas Safety / EICR / ...
    issue_date       TEXT,          -- ISO date
    expiry_date      TEXT,          -- ISO date
    status           TEXT,          -- Valid / Expiring Soon / Expired
    provider         TEXT,
    cost             NUMERIC CHECK (cost IS NULL OR cost >= 0),
    document_link    TEXT,
    notes            TEXT
);
CREATE INDEX idx_certificate_property ON certificate (property_id);
CREATE INDEX idx_certificate_expiry   ON certificate (expiry_date);
