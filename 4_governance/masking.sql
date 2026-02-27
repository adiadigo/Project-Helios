-- =============================================================================
-- MASKING POLICIES - Project Helios PII Protection
-- =============================================================================

USE DATABASE HELIOS_GOVERNANCE_DB;
USE SCHEMA POLICIES;

-- =============================================================================
-- 1. MASKING POLICY DEFINITIONS
-- =============================================================================

-- Policy 1: Household ID - High PII (meter identifier)
CREATE OR REPLACE MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_HOUSEHOLD_ID
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN val
    WHEN IS_ROLE_IN_SESSION('ACCOUNTADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN 'XXX' || RIGHT(val, 4)
    ELSE '***MASKED***'
  END
COMMENT = 'Masks household identifiers based on role - full access for stewards, partial for analysts';

-- Policy 2: ACORN Group - Medium PII (demographic classification)
CREATE OR REPLACE MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_ACORN_GROUP
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN val
    WHEN IS_ROLE_IN_SESSION('ACCOUNTADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN SHA2(val, 256)
    ELSE '***MASKED***'
  END
COMMENT = 'Masks ACORN demographic groups - hashed for analysts to allow grouping without revealing category';

-- Policy 3: Tariff Type - Low PII (service classification)
CREATE OR REPLACE MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_TARIFF
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN val
    WHEN IS_ROLE_IN_SESSION('ACCOUNTADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN val
    WHEN IS_ROLE_IN_SESSION('HELIOS_BI_CONSUMER') THEN 
      CASE 
        WHEN val IN ('Standard', 'Std') THEN 'STANDARD_TARIFF'
        WHEN val IN ('Time-of-Use', 'ToU') THEN 'VARIABLE_TARIFF'
        ELSE 'OTHER_TARIFF'
      END
    ELSE '***MASKED***'
  END
COMMENT = 'Generalizes tariff types for BI consumers while preserving analytical value';

-- =============================================================================
-- 2. APPLY MASKING POLICIES TO COLUMNS - DIM_HOUSEHOLD
-- =============================================================================

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
  household_id SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_HOUSEHOLD_ID;

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
  acorn_group SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_ACORN_GROUP;

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
  tariff_type SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_TARIFF;

-- =============================================================================
-- 3. APPLY MASKING POLICIES TO COLUMNS - FACT_ENERGY_CONSUMPTION
-- =============================================================================

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION MODIFY COLUMN
  household_id SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_HOUSEHOLD_ID;

-- =============================================================================
-- 4. APPLY MASKING POLICIES TO COLUMNS - Silver Layer (CLEAN_HOUSEHOLD_INFO)
-- =============================================================================

ALTER TABLE HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO MODIFY COLUMN
  household_id SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_HOUSEHOLD_ID;

ALTER TABLE HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO MODIFY COLUMN
  acorn_group SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_ACORN_GROUP;

ALTER TABLE HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO MODIFY COLUMN
  tariff_type SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.MASK_TARIFF;
