-- =============================================================================
-- TAGS - Project Helios Data Classification
-- =============================================================================

USE DATABASE HELIOS_GOVERNANCE_DB;
USE SCHEMA POLICIES;

-- =============================================================================
-- 1. TAG DEFINITIONS
-- =============================================================================

CREATE OR REPLACE TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL
  ALLOWED_VALUES 'HIGH', 'MEDIUM', 'LOW', 'NONE'
  COMMENT = 'Classifies PII sensitivity level for data governance';

CREATE OR REPLACE TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN
  ALLOWED_VALUES 'HOUSEHOLD', 'ENERGY', 'WEATHER', 'FINANCIAL'
  COMMENT = 'Business domain classification for data categorization';

CREATE OR REPLACE TAG HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY
  ALLOWED_VALUES '90_DAYS', '1_YEAR', '7_YEARS', 'PERMANENT'
  COMMENT = 'Data lifecycle and retention requirements';

-- =============================================================================
-- 2. TAG ASSIGNMENTS - DIM_HOUSEHOLD (Gold Layer)
-- =============================================================================

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
  household_id SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'HIGH',
  household_id SET TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'HOUSEHOLD';

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
  tariff_type SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'LOW',
  tariff_type SET TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'HOUSEHOLD';

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
  acorn_group SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'MEDIUM',
  acorn_group SET TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'HOUSEHOLD';

-- =============================================================================
-- 3. TAG ASSIGNMENTS - FACT_ENERGY_CONSUMPTION (Gold Layer)
-- =============================================================================

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION MODIFY COLUMN
  household_id SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'HIGH',
  household_id SET TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'HOUSEHOLD';

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION MODIFY COLUMN
  reading_timestamp SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'LOW',
  reading_timestamp SET TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'ENERGY';

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION MODIFY COLUMN
  energy_kwh SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'NONE',
  energy_kwh SET TAG HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'ENERGY';

-- =============================================================================
-- 4. TAG ASSIGNMENTS - DIM_WEATHER (Gold Layer)
-- =============================================================================

ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER SET TAG
  HELIOS_GOVERNANCE_DB.POLICIES.DATA_DOMAIN = 'WEATHER',
  HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'NONE';

-- =============================================================================
-- 5. DATABASE-LEVEL RETENTION TAGS
-- =============================================================================

ALTER DATABASE HELIOS_RAW_DB SET TAG
  HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY = '90_DAYS';

ALTER DATABASE HELIOS_TRANSFORM_DB SET TAG
  HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY = '1_YEAR';

ALTER DATABASE HELIOS_ANALYTICS_DB SET TAG
  HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY = '7_YEARS';

ALTER DATABASE HELIOS_AI_READY_DB SET TAG
  HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY = 'PERMANENT';
