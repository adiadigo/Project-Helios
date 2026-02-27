-- =============================================================================
-- RBAC & ACCESS CONTROL TEST - Project Helios
-- Tests role hierarchy, permissions, and warehouse access
-- =============================================================================
-- Role: SECURITYADMIN (to verify role configurations)
-- Warehouse: COMPUTE_WH (lightweight test queries)
-- =============================================================================

USE ROLE SECURITYADMIN;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- TEST 1: Verify All Helios Roles Exist
-- =============================================================================

SELECT 'HELIOS_ROLES_EXIST' AS TEST_NAME,
    CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' Helios roles found' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.ROLES
WHERE NAME LIKE 'HELIOS%' AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 2: Verify Role Hierarchy (BI_CONSUMER -> ANALYST -> ENGINEER -> SYSADMIN)
-- =============================================================================

USE ROLE ACCOUNTADMIN;

SELECT 'ROLE_HIERARCHY_BI_TO_ANALYST' AS TEST_NAME,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_BI_CONSUMER granted to HELIOS_DATA_ANALYST' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME = 'HELIOS_DATA_ANALYST' 
  AND NAME = 'HELIOS_BI_CONSUMER'
  AND GRANTED_ON = 'ROLE'
  AND DELETED_ON IS NULL;

SELECT 'ROLE_HIERARCHY_ANALYST_TO_ENGINEER' AS TEST_NAME,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_DATA_ANALYST granted to HELIOS_DATA_ENGINEER' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME = 'HELIOS_DATA_ENGINEER' 
  AND NAME = 'HELIOS_DATA_ANALYST'
  AND GRANTED_ON = 'ROLE'
  AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 3: Verify Warehouse Grants to Roles
-- =============================================================================

SELECT 'WAREHOUSE_GRANTS' AS TEST_NAME,
    CASE WHEN COUNT(DISTINCT NAME) >= 3 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(DISTINCT NAME) || ' warehouses granted to HELIOS_DATA_ENGINEER' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME = 'HELIOS_DATA_ENGINEER'
  AND GRANTED_ON = 'WAREHOUSE'
  AND PRIVILEGE = 'USAGE'
  AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 4: Verify Database Grants to Roles
-- =============================================================================

SELECT 'DB_GRANTS_BI_CONSUMER' AS TEST_NAME,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_BI_CONSUMER has USAGE on HELIOS_ANALYTICS_DB' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME = 'HELIOS_BI_CONSUMER'
  AND NAME = 'HELIOS_ANALYTICS_DB'
  AND PRIVILEGE = 'USAGE'
  AND DELETED_ON IS NULL;

SELECT 'DB_GRANTS_ANALYST' AS TEST_NAME,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_ANALYST has USAGE on HELIOS_ANALYTICS_DB' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME = 'HELIOS_ANALYST'
  AND NAME = 'HELIOS_ANALYTICS_DB'
  AND PRIVILEGE = 'USAGE'
  AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 5: Verify Table Grants
-- =============================================================================

SELECT 'TABLE_SELECT_GRANTS' AS TEST_NAME,
    CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' table SELECT grants to HELIOS roles' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME IN ('HELIOS_BI_CONSUMER', 'HELIOS_ANALYST', 'HELIOS_DATA_STEWARD')
  AND PRIVILEGE = 'SELECT'
  AND GRANTED_ON = 'TABLE'
  AND TABLE_SCHEMA = 'GRID'
  AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 6: Verify Test Users Have Correct Default Roles
-- =============================================================================

SELECT 'TEST_USER_BI_DEFAULT_ROLE' AS TEST_NAME,
    CASE WHEN DEFAULT_ROLE = 'HELIOS_BI_CONSUMER' THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_TEST_BI_USER default role: ' || DEFAULT_ROLE AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE NAME = 'HELIOS_TEST_BI_USER' AND DELETED_ON IS NULL;

SELECT 'TEST_USER_ANALYST_DEFAULT_ROLE' AS TEST_NAME,
    CASE WHEN DEFAULT_ROLE = 'HELIOS_ANALYST' THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_TEST_ANALYST_USER default role: ' || DEFAULT_ROLE AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE NAME = 'HELIOS_TEST_ANALYST_USER' AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 7: Verify Role Isolation (Test Users Have NO ACCOUNTADMIN)
-- =============================================================================

SELECT 'BI_USER_NO_ACCOUNTADMIN' AS TEST_NAME,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'HELIOS_TEST_BI_USER should NOT have ACCOUNTADMIN' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
WHERE GRANTEE_NAME = 'HELIOS_TEST_BI_USER'
  AND ROLE = 'ACCOUNTADMIN'
  AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 8: Verify Warehouses Are Properly Configured
-- =============================================================================

USE ROLE SYSADMIN;

SELECT 'WAREHOUSE_CONFIG' AS TEST_NAME,
    CASE WHEN COUNT(*) = 4 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' of 4 Helios warehouses configured' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES
WHERE NAME IN ('INGEST_WH', 'TRANSFORM_WH', 'REPORTING_WH', 'CORTEX_WH')
  AND DELETED IS NULL;

-- =============================================================================
-- SUMMARY
-- =============================================================================

SELECT '========== RBAC TEST SUMMARY ==========' AS TEST_SUMMARY;
