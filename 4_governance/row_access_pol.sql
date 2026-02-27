-- =============================================================================
-- ROW ACCESS POLICY - Project Helios Row-Level Security
-- =============================================================================
-- Role: ACCOUNTADMIN (required for row access policy management)
-- Warehouse: COMPUTE_WH (admin operations)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

USE DATABASE HELIOS_GOVERNANCE_DB;
USE SCHEMA POLICIES;

-- =============================================================================
-- 1. MAPPING TABLES FOR FINE-GRAINED ACCESS CONTROL
-- =============================================================================

-- Maps roles to ACORN groups (for reference/future use)
CREATE OR REPLACE TABLE HELIOS_GOVERNANCE_DB.POLICIES.ROLE_ACORN_MAPPING (
    role_name VARCHAR NOT NULL,
    acorn_group VARCHAR NOT NULL,
    CONSTRAINT pk_role_acorn PRIMARY KEY (role_name, acorn_group)
)
COMMENT = 'Maps roles to allowed ACORN groups for row-level security';

-- Seed initial role-ACORN mappings
INSERT INTO HELIOS_GOVERNANCE_DB.POLICIES.ROLE_ACORN_MAPPING (role_name, acorn_group)
VALUES 
    ('HELIOS_DATA_STEWARD', 'Affluent'),
    ('HELIOS_DATA_STEWARD', 'Comfortable'),
    ('HELIOS_DATA_STEWARD', 'Adversity'),
    ('HELIOS_DATA_STEWARD', 'ACORN-U'),
    ('HELIOS_ANALYST', 'Affluent'),
    ('HELIOS_ANALYST', 'Comfortable');

-- Maps roles to household IDs (for granular access)
CREATE OR REPLACE TABLE HELIOS_GOVERNANCE_DB.POLICIES.ROLE_HOUSEHOLD_MAPPING (
    role_name VARCHAR NOT NULL,
    household_id VARCHAR NOT NULL,
    CONSTRAINT pk_role_household PRIMARY KEY (role_name, household_id)
)
COMMENT = 'Maps roles to allowed household IDs for row-level security';

-- =============================================================================
-- 2. ROW ACCESS POLICY DEFINITION
-- =============================================================================

-- RAP for FACT_ENERGY_CONSUMPTION - time-based filtering for BI consumers
-- Note: Cannot use household_id as RAP column when masking policy exists on it
CREATE OR REPLACE ROW ACCESS POLICY HELIOS_GOVERNANCE_DB.POLICIES.RAP_ENERGY_DATA
AS (reading_timestamp TIMESTAMP_NTZ) RETURNS BOOLEAN ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('ACCOUNTADMIN') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('HELIOS_BI_CONSUMER') THEN 
      reading_timestamp >= DATEADD(MONTH, -12, CURRENT_DATE())
    ELSE FALSE
  END
COMMENT = 'Controls row access to energy data - BI consumers limited to last 12 months';

-- =============================================================================
-- 3. APPLY ROW ACCESS POLICY
-- =============================================================================

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION
  ADD ROW ACCESS POLICY HELIOS_GOVERNANCE_DB.POLICIES.RAP_ENERGY_DATA ON (reading_timestamp);

-- =============================================================================
-- 4. ACCESS CONTROL SUMMARY
-- =============================================================================
/*
┌─────────────────────────┬──────────────────────────────────────────────────────┐
│ Role                    │ Access Level                                         │
├─────────────────────────┼──────────────────────────────────────────────────────┤
│ HELIOS_DATA_STEWARD     │ All rows, all time, full data visibility             │
│ HELIOS_ANALYST          │ All rows, all time, partial household_id masking     │
│ HELIOS_BI_CONSUMER      │ Last 12 months only, generalized tariff, masked PII  │
│ PUBLIC/Other            │ No access (FALSE returned by RAP)                    │
└─────────────────────────┴──────────────────────────────────────────────────────┘
*/
