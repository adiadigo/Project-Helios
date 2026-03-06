-- =============================================================================
-- GOVERNANCE POLICIES TEST - Project Helios
-- Tests masking policies, row access policies, and tags
-- =============================================================================
-- Role: ACCOUNTADMIN (to verify policy configurations)
-- Warehouse: COMPUTE_WH (lightweight test queries)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- TEST 1: Verify All Tags Exist
-- =============================================================================

SELECT 'TAG_EXISTENCE' AS TEST_NAME,
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' of 3 tags found' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.TAGS
WHERE TAG_DATABASE = 'HELIOS_GOVERNANCE_DB' 
  AND TAG_SCHEMA = 'POLICIES'
  AND TAG_NAME IN ('PII_LEVEL', 'DATA_DOMAIN', 'RETENTION_POLICY')
  AND DELETED IS NULL;

-- =============================================================================
-- TEST 2: Verify Masking Policies Are Active on DIM_HOUSEHOLD
-- =============================================================================

SELECT 'MASKING_POLICIES_DIM_HOUSEHOLD' AS TEST_NAME,
    CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' of 3 masking policies active' AS DETAILS
FROM TABLE(HELIOS_GOVERNANCE_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD'
))
WHERE POLICY_KIND = 'MASKING_POLICY' AND POLICY_STATUS = 'ACTIVE';

-- =============================================================================
-- TEST 3: Verify Row Access Policy Is Active on FACT Table
-- =============================================================================

SELECT 'RAP_FACT_ENERGY' AS TEST_NAME,
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' row access policy active' AS DETAILS
FROM TABLE(HELIOS_GOVERNANCE_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION'
))
WHERE POLICY_KIND = 'ROW_ACCESS_POLICY' AND POLICY_STATUS = 'ACTIVE';

-- =============================================================================
-- TEST 4: Verify Tag Assignments on Columns
-- =============================================================================

SELECT 'TAG_ASSIGNMENT_HOUSEHOLD_ID' AS TEST_NAME,
    CASE WHEN SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL', 
         'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD.HOUSEHOLD_ID', 'COLUMN') = 'HIGH'
         THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'household_id should have PII_LEVEL=HIGH' AS DETAILS;

SELECT 'TAG_ASSIGNMENT_ACORN_GROUP' AS TEST_NAME,
    CASE WHEN SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL', 
         'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD.ACORN_GROUP', 'COLUMN') = 'MEDIUM'
         THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'acorn_group should have PII_LEVEL=MEDIUM' AS DETAILS;

-- =============================================================================
-- TEST 5: Verify Expected Masking Output Per Role
-- =============================================================================

SELECT 'MASKING_VALIDATION_VIEW' AS TEST_NAME,
    CASE WHEN COUNT(DISTINCT role_name) = 3 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'Validation view shows masking for ' || COUNT(DISTINCT role_name) || ' roles' AS DETAILS
FROM HELIOS_GOVERNANCE_DB.POLICIES.V_MASKING_VALIDATION;

-- =============================================================================
-- TEST 6: Verify Test Users Exist (Isolated for Masking Tests)
-- =============================================================================

SELECT 'TEST_USERS_EXIST' AS TEST_NAME,
    CASE WHEN COUNT(*) = 2 THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    COUNT(*) || ' of 2 test users found' AS DETAILS
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE NAME LIKE 'HELIOS_TEST%' AND DELETED_ON IS NULL;

-- =============================================================================
-- TEST 7: Masking Policy Logic Validation
-- =============================================================================

SELECT 'BI_CONSUMER_FULL_MASK' AS TEST_NAME,
    CASE WHEN masked_household_id = '***MASKED***' 
         AND masked_acorn_group = '***MASKED***'
         THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'BI Consumer sees: ' || masked_household_id || ' | ' || masked_acorn_group AS DETAILS
FROM HELIOS_GOVERNANCE_DB.POLICIES.V_MASKING_VALIDATION
WHERE role_name = 'HELIOS_BI_CONSUMER'
LIMIT 1;

SELECT 'ANALYST_PARTIAL_MASK' AS TEST_NAME,
    CASE WHEN masked_household_id LIKE 'XXX%' 
         AND LENGTH(masked_acorn_group) = 64  -- SHA256 hash length
         THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    'Analyst sees: ' || masked_household_id || ' | ' || LEFT(masked_acorn_group, 16) || '...' AS DETAILS
FROM HELIOS_GOVERNANCE_DB.POLICIES.V_MASKING_VALIDATION
WHERE role_name = 'HELIOS_ANALYST'
LIMIT 1;

-- =============================================================================
-- SUMMARY: Run All Tests
-- =============================================================================

SELECT '========== GOVERNANCE TEST SUMMARY ==========' AS TEST_SUMMARY;
