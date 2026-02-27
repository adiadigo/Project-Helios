-- =============================================================================
-- CONSUMPTION VIEWS TEST - Project Helios
-- Run each query SEPARATELY (not as a batch) for faster execution
-- =============================================================================
-- Role: ACCOUNTADMIN (required for ACCOUNT_USAGE views access)
-- Warehouse: COMPUTE_WH (lightweight test queries)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- 1. Budget Tracker (most important - single row, fast)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_MTD_BUDGET_TRACKER;

-- 2. Resource Monitor Status (small dataset)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_RESOURCE_MONITOR_STATUS;

-- 3. Daily Credit Summary (last 7 days only)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_DAILY_CREDIT_SUMMARY LIMIT 7;

-- 4. Warehouse Daily Usage (last 7 days)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_WAREHOUSE_DAILY_USAGE LIMIT 20;

-- 5. Top Queries by Cost (already limited to 100 in view)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_TOP_QUERIES_BY_COST LIMIT 10;

-- 6. User Consumption
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_USER_CONSUMPTION LIMIT 10;

-- 7. Database Storage (Helios DBs only)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_DATABASE_STORAGE LIMIT 10;

-- 8. Warehouse Hourly Pattern
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_WAREHOUSE_HOURLY_PATTERN LIMIT 20;

-- 9. Cortex AI Usage (may be empty if no Cortex usage)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_CORTEX_AI_USAGE LIMIT 10;

-- 10. Cost Anomalies (may be empty - needs 14+ days of data)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_COST_ANOMALIES LIMIT 10;

-- =============================================================================
-- OPTIONAL: Quick row count check (run separately if needed)
-- =============================================================================
/*
SELECT 'V_DAILY_CREDIT_SUMMARY', COUNT(*) FROM HELIOS_ANALYTICS_DB.PUBLIC.V_DAILY_CREDIT_SUMMARY;
SELECT 'V_WAREHOUSE_DAILY_USAGE', COUNT(*) FROM HELIOS_ANALYTICS_DB.PUBLIC.V_WAREHOUSE_DAILY_USAGE;
SELECT 'V_MTD_BUDGET_TRACKER', COUNT(*) FROM HELIOS_ANALYTICS_DB.PUBLIC.V_MTD_BUDGET_TRACKER;
*/
