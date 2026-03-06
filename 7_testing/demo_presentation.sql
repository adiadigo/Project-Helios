-- =============================================================================
-- PROJECT HELIOS: DEMONSTRATION SCRIPT
-- =============================================================================
-- Purpose: Walk through all implemented features for presentation
-- Duration: ~15-20 minutes
-- Prerequisite: Run as ACCOUNTADMIN with COMPUTE_WH
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- SECTION 1: MEDALLION ARCHITECTURE
-- "Data flows through four layers, each adding quality and structure."
-- =============================================================================

-- 1.1 Bronze Layer: Raw data as ingested (all VARCHAR, no transformation)
SELECT 'BRONZE LAYER' AS layer, 
       LCLid, tstp, energy, _source_file
FROM HELIOS_RAW_DB.GRID.RAW_METER_DATA
LIMIT 3;

-- 1.2 Silver Layer: Cleaned and typed (proper data types, renamed columns)
SELECT 'SILVER LAYER' AS layer,
       household_id, reading_timestamp, energy_kwh
FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA
LIMIT 3;

-- 1.3 Gold Layer: Star schema (fact + dimensions, governance applied)
SELECT 'GOLD LAYER' AS layer,
       f.household_id, f.reading_timestamp, f.energy_kwh,
       h.tariff_type, h.acorn_group
FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION f
JOIN HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD h 
    ON f.household_id = h.household_id
LIMIT 3;

-- 1.4 Platinum Layer: ML-ready features (derived attributes)
SELECT 'PLATINUM LAYER' AS layer,
       household_id, feature_timestamp, energy_kwh_hourly,
       day_of_week, hour_of_day, is_weekend
FROM HELIOS_AI_READY_DB.GRID.V_TRAINING_FEATURES
LIMIT 3;

-- =============================================================================
-- SECTION 2: DATA GOVERNANCE - TAGGING
-- "Every column is classified by PII level and business domain"
-- =============================================================================

-- 2.1 Show all tags defined in the system
SHOW TAGS IN SCHEMA HELIOS_GOVERNANCE_DB.POLICIES;

-- 2.2 Check PII classification on sensitive columns
SELECT 
    'household_id' AS column_name,
    SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL', 
        'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD.HOUSEHOLD_ID', 'COLUMN') AS pii_level,
    'Direct identifier - can link to physical address' AS rationale
UNION ALL
SELECT 
    'acorn_group',
    SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL', 
        'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD.ACORN_GROUP', 'COLUMN'),
    'Demographic classification - discrimination risk'
UNION ALL
SELECT 
    'tariff_type',
    SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL', 
        'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD.TARIFF_TYPE', 'COLUMN'),
    'Service tier - minimal privacy impact';

-- 2.3 Show retention policies by database
SELECT 
    DATABASE_NAME,
    SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY', 
        DATABASE_NAME, 'DATABASE') AS retention_policy
FROM (
    SELECT 'HELIOS_RAW_DB' AS DATABASE_NAME
    UNION ALL SELECT 'HELIOS_TRANSFORM_DB'
    UNION ALL SELECT 'HELIOS_ANALYTICS_DB'
    UNION ALL SELECT 'HELIOS_AI_READY_DB'
);

-- =============================================================================
-- SECTION 3: DATA GOVERNANCE - MASKING POLICIES
-- "Different roles see different levels of data detail"
-- =============================================================================

-- 3.1 Show which policies are applied to DIM_HOUSEHOLD
SELECT 
    POLICY_NAME,
    POLICY_KIND,
    REF_COLUMN_NAME AS masked_column,
    POLICY_STATUS
FROM TABLE(HELIOS_GOVERNANCE_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD'
));

-- 3.2 Side-by-side comparison: What each role sees
-- This view simulates the masking output without switching roles
SELECT 
    role_name,
    masked_household_id,
    masked_acorn_group,
    masked_tariff_type,
    expected_behavior
FROM HELIOS_GOVERNANCE_DB.POLICIES.V_MASKING_VALIDATION
ORDER BY 
    CASE role_name 
        WHEN 'HELIOS_DATA_STEWARD' THEN 1 
        WHEN 'HELIOS_ANALYST' THEN 2 
        WHEN 'HELIOS_BI_CONSUMER' THEN 3 
    END,
    masked_household_id;

-- 3.3 Masking logic explanation
SELECT 
    'HELIOS_DATA_STEWARD' AS role, 
    'Full Access' AS household_id_treatment,
    'Full Access' AS acorn_group_treatment,
    'Full Access' AS tariff_treatment,
    'Data governance, quality management' AS use_case
UNION ALL SELECT 
    'HELIOS_ANALYST',
    'Partial: XXX + last 4 chars',
    'SHA256 Hash (enables GROUP BY)',
    'Full Access',
    'Data science, advanced analytics'
UNION ALL SELECT 
    'HELIOS_BI_CONSUMER',
    'Fully Masked: ***MASKED***',
    'Fully Masked: ***MASKED***',
    'Generalized: STANDARD_TARIFF',
    'Dashboard consumption, reporting';

-- =============================================================================
-- SECTION 4: DATA GOVERNANCE - ROW ACCESS POLICY
-- "BI consumers only see the last 12 months of data"
-- =============================================================================

-- 4.1 Show RAP applied to fact table
SELECT 
    POLICY_NAME,
    POLICY_KIND,
    REF_ENTITY_NAME,
    POLICY_STATUS
FROM TABLE(HELIOS_GOVERNANCE_DB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_DOMAIN => 'TABLE',
    REF_ENTITY_NAME => 'HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION'
))
WHERE POLICY_KIND = 'ROW_ACCESS_POLICY';

-- 4.2 Explain RAP logic
SELECT 
    'HELIOS_DATA_STEWARD' AS role,
    'All historical data' AS data_access,
    'TRUE always returned' AS policy_logic
UNION ALL SELECT 
    'HELIOS_ANALYST',
    'All historical data',
    'TRUE always returned'
UNION ALL SELECT 
    'HELIOS_BI_CONSUMER',
    'Last 12 months only',
    'reading_timestamp >= DATEADD(MONTH, -12, CURRENT_DATE())'
UNION ALL SELECT 
    'Other roles',
    'No data access',
    'FALSE always returned';

-- 4.3 Show data date range (to understand RAP impact)
SELECT 
    'Current date' AS metric, 
    CURRENT_DATE()::VARCHAR AS value
UNION ALL SELECT 
    '12-month cutoff',
    DATEADD(MONTH, -12, CURRENT_DATE())::VARCHAR
UNION ALL SELECT 
    'Oldest data in table',
    (SELECT MIN(reading_timestamp)::VARCHAR FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION)
UNION ALL SELECT 
    'Newest data in table',
    (SELECT MAX(reading_timestamp)::VARCHAR FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION)
UNION ALL SELECT 
    'Total rows (all roles)',
    (SELECT COUNT(*)::VARCHAR FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION);

-- =============================================================================
-- SECTION 5: ROLE-BASED ACCESS CONTROL (RBAC)
-- "Hierarchical roles with least-privilege access"
-- =============================================================================

-- 5.1 Show all Helios roles
SELECT 
    NAME AS role_name,
    CREATED_ON,
    COMMENT
FROM SNOWFLAKE.ACCOUNT_USAGE.ROLES
WHERE NAME LIKE 'HELIOS%' 
    AND DELETED_ON IS NULL
ORDER BY CREATED_ON;

-- 5.2 Role hierarchy visualization
SELECT 
    'ACCOUNTADMIN' AS parent_role, 
    'SYSADMIN' AS child_role, 
    'System hierarchy' AS relationship
UNION ALL SELECT 'SYSADMIN', 'HELIOS_SYSADMIN', 'Custom admin'
UNION ALL SELECT 'HELIOS_SYSADMIN', 'HELIOS_DATA_ENGINEER', 'Pipeline development'
UNION ALL SELECT 'HELIOS_DATA_ENGINEER', 'HELIOS_DATA_ANALYST', 'Ad-hoc analysis'
UNION ALL SELECT 'HELIOS_DATA_ANALYST', 'HELIOS_BI_CONSUMER', 'Dashboard consumption'
UNION ALL SELECT 'ACCOUNTADMIN', 'HELIOS_DATA_STEWARD', 'Data governance (separate)'
UNION ALL SELECT 'ACCOUNTADMIN', 'HELIOS_ANALYST', 'Advanced analytics (separate)';

-- 5.3 Show warehouse access by role
SELECT 
    GRANTEE_NAME AS role,
    NAME AS warehouse,
    PRIVILEGE
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTED_ON = 'WAREHOUSE'
    AND PRIVILEGE = 'USAGE'
    AND GRANTEE_NAME LIKE 'HELIOS%'
    AND DELETED_ON IS NULL
ORDER BY GRANTEE_NAME, NAME;

-- 5.4 Test users (isolated for masking validation)
SELECT 
    NAME AS test_user,
    DEFAULT_ROLE,
    DEFAULT_WAREHOUSE,
    COMMENT
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE NAME LIKE 'HELIOS_TEST%'
    AND DELETED_ON IS NULL;

-- =============================================================================
-- SECTION 6: COST MANAGEMENT - RESOURCE MONITORS
-- "Credit budgets with automatic suspension"
-- =============================================================================

-- 6.1 Show all resource monitors and their quotas
SELECT 
    NAME AS monitor_name,
    CREDIT_QUOTA,
    USED_CREDITS,
    REMAINING_CREDITS,
    ROUND((USED_CREDITS / NULLIF(CREDIT_QUOTA, 0)) * 100, 1) AS pct_used
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE NAME LIKE '%MONITOR%'
ORDER BY CREDIT_QUOTA DESC;

-- 6.2 Show warehouse-to-monitor assignments
SELECT 
    w.NAME AS warehouse,
    w.WAREHOUSE_SIZE AS size,
    w.RESOURCE_MONITOR AS assigned_monitor,
    r.CREDIT_QUOTA AS monthly_quota
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES w
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS r 
    ON w.RESOURCE_MONITOR = r.NAME
WHERE w.NAME IN ('INGEST_WH', 'TRANSFORM_WH', 'REPORTING_WH', 'CORTEX_WH')
    AND w.DELETED IS NULL;

-- 6.3 Budget allocation summary
SELECT 
    'Account Total Budget' AS category,
    200 AS credits,
    '100%' AS allocation
UNION ALL SELECT 
    'INGEST_WH (Bronze loading)', 30, '15%'
UNION ALL SELECT 
    'TRANSFORM_WH (Silver/Gold ETL)', 50, '25%'
UNION ALL SELECT 
    'REPORTING_WH (BI queries)', 30, '15%'
UNION ALL SELECT 
    'CORTEX_WH (ML workloads)', 60, '30%'
UNION ALL SELECT 
    'Buffer (cloud services)', 30, '15%';

-- =============================================================================
-- SECTION 7: COST MANAGEMENT - CONSUMPTION VIEWS
-- "10 views for understanding spend patterns"
-- =============================================================================

-- 7.1 Month-to-date budget tracker (key executive view)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_MTD_BUDGET_TRACKER;

-- 7.2 Daily credit trend (last 7 days)
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_DAILY_CREDIT_SUMMARY
LIMIT 7;

-- 7.3 Warehouse usage breakdown
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_WAREHOUSE_DAILY_USAGE
WHERE USAGE_DATE >= CURRENT_DATE() - 7
LIMIT 10;

-- 7.4 Top consumers by user
SELECT * FROM HELIOS_ANALYTICS_DB.PUBLIC.V_USER_CONSUMPTION
LIMIT 5;

-- 7.5 List all consumption views available
SELECT 
    TABLE_NAME AS view_name,
    COMMENT
FROM HELIOS_ANALYTICS_DB.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'PUBLIC' 
    AND TABLE_NAME LIKE 'V_%'
ORDER BY TABLE_NAME;

-- =============================================================================
-- SECTION 8: ALERTING
-- "Automated notifications for anomalies"
-- =============================================================================

-- 8.1 Show configured alerts
SELECT 
    NAME AS alert_name,
    STATE,
    SCHEDULE,
    CONDITION
FROM SNOWFLAKE.ACCOUNT_USAGE.ALERTS
WHERE NAME LIKE 'HELIOS%'
    AND DELETED_ON IS NULL;

-- 8.2 Alert purposes
SELECT 
    'HELIOS_LONG_QUERY_ALERT' AS alert,
    'Query exceeds 5 minutes' AS trigger_condition,
    'Performance investigation' AS action_required
UNION ALL SELECT 
    'HELIOS_QUERY_FAILURE_ALERT',
    'Failure rate > 5% in last hour',
    'Error investigation'
UNION ALL SELECT 
    'HELIOS_QUEUE_TIME_ALERT',
    'Avg queue time > 30 seconds',
    'Warehouse scaling consideration';

-- =============================================================================
-- SECTION 9: SUMMARY DASHBOARD
-- "Single view of system health"
-- =============================================================================

SELECT '1. DATABASES' AS component, 
       (SELECT COUNT(DISTINCT DATABASE_NAME) 
        FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASES 
        WHERE DATABASE_NAME LIKE 'HELIOS%' AND DELETED IS NULL)::VARCHAR AS count,
       'HELIOS_RAW_DB, TRANSFORM_DB, ANALYTICS_DB, AI_READY_DB, GOVERNANCE_DB' AS details
UNION ALL SELECT '2. TABLES', 
       (SELECT COUNT(*) FROM HELIOS_ANALYTICS_DB.INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_TYPE = 'BASE TABLE')::VARCHAR,
       'Across all HELIOS databases'
UNION ALL SELECT '3. ROLES', 
       (SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.ROLES 
        WHERE NAME LIKE 'HELIOS%' AND DELETED_ON IS NULL)::VARCHAR,
       'Custom functional roles'
UNION ALL SELECT '4. MASKING POLICIES', 
       '3',
       'MASK_HOUSEHOLD_ID, MASK_ACORN_GROUP, MASK_TARIFF'
UNION ALL SELECT '5. ROW ACCESS POLICIES', 
       '1',
       'RAP_ENERGY_DATA (time-based)'
UNION ALL SELECT '6. TAGS', 
       '3',
       'PII_LEVEL, DATA_DOMAIN, RETENTION_POLICY'
UNION ALL SELECT '7. RESOURCE MONITORS', 
       '5',
       '1 account + 4 warehouse monitors'
UNION ALL SELECT '8. CONSUMPTION VIEWS', 
       '10',
       'Budget, usage, anomaly tracking'
UNION ALL SELECT '9. ALERTS', 
       '3',
       'Long query, failures, queue time';

-- =============================================================================
-- END OF DEMONSTRATION
-- =============================================================================

SELECT 'DEMONSTRATION COMPLETE' AS status,
       'Project Helios implements enterprise-grade governance, RBAC, and cost controls on Snowflake' AS summary;
