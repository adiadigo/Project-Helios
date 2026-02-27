-- =============================================================================
-- RESOURCE MONITORS & ALERTS TEST - Project Helios
-- Tests resource monitors, credit quotas, and alert configurations
-- =============================================================================
-- Role: ACCOUNTADMIN (required for resource monitor access)
-- Warehouse: COMPUTE_WH (lightweight test queries)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- TEST 1: Verify All Resource Monitors Exist
-- =============================================================================

SELECT 'RESOURCE_MONITORS_EXIST' AS TEST_NAME,
    CASE WHEN COUNT(DISTINCT NAME) = 5 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(DISTINCT NAME) || ' of 5 resource monitors found' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME IN ('HELIOS_ACCOUNT_MONITOR', 'INGEST_WH_MONITOR', 'TRANSFORM_WH_MONITOR', 
               'REPORTING_WH_MONITOR', 'CORTEX_WH_MONITOR');

-- =============================================================================
-- TEST 2: Verify Account Monitor Has Correct Quota (200 credits)
-- =============================================================================

SELECT 'ACCOUNT_MONITOR_QUOTA' AS TEST_NAME,
    CASE WHEN CREDIT_QUOTA = 200 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_ACCOUNT_MONITOR quota: ' || CREDIT_QUOTA || ' credits' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME = 'HELIOS_ACCOUNT_MONITOR';

-- =============================================================================
-- TEST 3: Verify Per-Warehouse Monitor Quotas
-- =============================================================================

SELECT 'INGEST_WH_MONITOR_QUOTA' AS TEST_NAME,
    CASE WHEN CREDIT_QUOTA = 30 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'INGEST_WH quota: ' || CREDIT_QUOTA || ' credits (expected: 30)' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME = 'INGEST_WH_MONITOR';

SELECT 'TRANSFORM_WH_MONITOR_QUOTA' AS TEST_NAME,
    CASE WHEN CREDIT_QUOTA = 50 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'TRANSFORM_WH quota: ' || CREDIT_QUOTA || ' credits (expected: 50)' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME = 'TRANSFORM_WH_MONITOR';

SELECT 'CORTEX_WH_MONITOR_QUOTA' AS TEST_NAME,
    CASE WHEN CREDIT_QUOTA = 60 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'CORTEX_WH quota: ' || CREDIT_QUOTA || ' credits (expected: 60)' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME = 'CORTEX_WH_MONITOR';

-- =============================================================================
-- TEST 4: Verify Resource Monitor Assignments to Warehouses
-- =============================================================================

SELECT 'WH_MONITOR_ASSIGNMENTS' AS TEST_NAME,
    CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' of 4 warehouses have monitors assigned' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES
WHERE NAME IN ('INGEST_WH', 'TRANSFORM_WH', 'REPORTING_WH', 'CORTEX_WH')
  AND RESOURCE_MONITOR IS NOT NULL
  AND DELETED IS NULL;

-- =============================================================================
-- TEST 5: Verify Alerts Exist
-- =============================================================================

SELECT 'ALERTS_EXIST' AS TEST_NAME,
    CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' Helios alerts found' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.ALERTS
WHERE NAME LIKE 'HELIOS%' AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 6: Verify Alert States (Should be STARTED/RESUMED)
-- =============================================================================

SELECT 'ALERT_STATES' AS TEST_NAME,
    NAME AS ALERT_NAME,
    CASE WHEN STATE = 'STARTED' THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'State: ' || STATE AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.ALERTS
WHERE NAME LIKE 'HELIOS%' AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 7: Verify Total Budget Allocation (Sum of WH quotas <= Account quota)
-- =============================================================================

SELECT 'BUDGET_ALLOCATION' AS TEST_NAME,
    CASE WHEN SUM(CREDIT_QUOTA) <= 200 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'Total WH allocation: ' || SUM(CREDIT_QUOTA) || ' credits (account limit: 200)' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME IN ('INGEST_WH_MONITOR', 'TRANSFORM_WH_MONITOR', 
               'REPORTING_WH_MONITOR', 'CORTEX_WH_MONITOR');

-- =============================================================================
-- TEST 8: Verify Current Credit Usage (Should be within limits)
-- =============================================================================

SELECT 'CURRENT_CREDIT_USAGE' AS TEST_NAME,
    CASE WHEN COALESCE(SUM(USED_CREDITS), 0) < 200 THEN 'PASS' ELSE 'WARNING' END AS RESULT,
    'Current usage: ' || ROUND(COALESCE(SUM(USED_CREDITS), 0), 2) || ' of 200 credits' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME = 'HELIOS_ACCOUNT_MONITOR';

-- =============================================================================
-- TEST 9: Verify Notification Integration Exists
-- =============================================================================

SELECT 'NOTIFICATION_INTEGRATION' AS TEST_NAME,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' notification integration(s) for alerts' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.NOTIFICATION_INTEGRATIONS
WHERE NAME = 'HELIOS_ALERTS' AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 10: Verify Consumption Views Exist
-- =============================================================================

SELECT 'CONSUMPTION_VIEWS_EXIST' AS TEST_NAME,
    CASE WHEN COUNT(*) = 10 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' of 10 consumption views found' AS DETAILS
FROM HELIOS_ANALYTICS_DB.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'PUBLIC' AND TABLE_NAME LIKE 'V_%';

-- =============================================================================
-- TEST 11: Verify MTD Budget Tracker Shows Correct Status
-- =============================================================================

SELECT 'MTD_BUDGET_STATUS' AS TEST_NAME,
    CASE WHEN BUDGET_STATUS IN ('ON TRACK', 'AT RISK', 'OVER BUDGET') THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'Budget status: ' || BUDGET_STATUS || ' (' || PCT_CONSUMED || '% consumed)' AS DETAILS
FROM HELIOS_ANALYTICS_DB.PUBLIC.V_MTD_BUDGET_TRACKER;

-- =============================================================================
-- SUMMARY
-- =============================================================================

SELECT '========== RESOURCE MONITORS & ALERTS TEST SUMMARY ==========' AS TEST_SUMMARY;
