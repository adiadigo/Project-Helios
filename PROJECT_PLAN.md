# Project Helios: Technical Documentation

## Overview

Project Helios is a Smart Grid Analytics Platform built on Snowflake, implementing enterprise data governance, role-based access control, and cost management for energy consumption data. This document describes the current implementation state and technical specifications.

**Scope**: This documentation covers implemented components only. External integrations (S3, Snowpipe) and AI/ML features are excluded.

---

## Business Context

### Problem Statement

Energy utilities managing smart meter data face challenges in data governance, access control, and cost management. Specifically:

- Household identifiers and demographic classifications constitute PII requiring protection
- Different user roles require different levels of data visibility
- Uncontrolled compute costs can exceed budgets without proper monitoring
- Audit requirements mandate tracking of data access and policy enforcement

### Solution Summary

Project Helios implements a governed data platform with:

- Four-layer medallion architecture for data quality progression
- Role-based access control with three consumer tiers
- Column-level masking for PII protection
- Row-level security for time-based data filtering
- Resource monitors and consumption views for cost control

---

## Technical Architecture

### Database Architecture

The platform implements a medallion architecture across four databases:

```
HELIOS_RAW_DB          HELIOS_TRANSFORM_DB       HELIOS_ANALYTICS_DB      HELIOS_AI_READY_DB
(Bronze Layer)         (Silver Layer)            (Gold Layer)             (Platinum Layer)
     |                      |                         |                        |
     v                      v                         v                        v
RAW_METER_DATA    ->   CLEAN_METER_DATA    ->   FACT_ENERGY_         ->  V_TRAINING_
RAW_HOUSEHOLD_INFO     CLEAN_HOUSEHOLD_INFO     CONSUMPTION              FEATURES
RAW_WEATHER_DATA       CLEAN_WEATHER_DATA       DIM_HOUSEHOLD            CORTEX_LOAD_
                                                DIM_WEATHER              FORECAST
                                                V_DASHBOARD_FEED
```

#### Layer Specifications

| Layer | Database | Purpose | Data Characteristics |
|-------|----------|---------|---------------------|
| Bronze | HELIOS_RAW_DB | Raw data landing | VARCHAR columns, no validation |
| Silver | HELIOS_TRANSFORM_DB | Cleaned and typed | Proper data types, constraints |
| Gold | HELIOS_ANALYTICS_DB | Star schema | Fact/dimension model, aggregations |
| Platinum | HELIOS_AI_READY_DB | ML-ready features | Derived features, forecast outputs |

#### Schema Design

All data tables reside in the `GRID` schema within each database. This single-schema approach simplifies access control and reduces grant management overhead.

```sql
-- Example: Gold layer fact table
HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION
    household_id        VARCHAR NOT NULL    -- PK, FK to DIM_HOUSEHOLD
    reading_timestamp   TIMESTAMP_NTZ NOT NULL  -- PK
    energy_kwh          FLOAT NOT NULL
```

### Compute Architecture

Four purpose-specific warehouses provide workload isolation:

| Warehouse | Size | Auto-Suspend | Purpose |
|-----------|------|--------------|---------|
| INGEST_WH | X-Small | 60 seconds | Data loading operations |
| TRANSFORM_WH | Small | 60 seconds | ELT transformations |
| REPORTING_WH | X-Small | 60 seconds | BI and analytics queries |
| CORTEX_WH | Small | 60 seconds | ML workloads |

Warehouse sizing rationale:
- INGEST_WH and REPORTING_WH use X-Small as workloads are I/O-bound rather than compute-bound
- TRANSFORM_WH uses Small for complex JOIN operations during Silver-to-Gold transformations
- CORTEX_WH uses Small to accommodate ML model training requirements

---

## Role-Based Access Control (RBAC)

### Role Hierarchy

The implementation follows Snowflake's recommended pattern of custom functional roles connected to system roles:

```
ACCOUNTADMIN
    |
    +-- SYSADMIN
    |       |
    |       +-- HELIOS_SYSADMIN
    |               |
    |               +-- HELIOS_DATA_ENGINEER
    |                       |
    |                       +-- HELIOS_DATA_ANALYST
    |                               |
    |                               +-- HELIOS_BI_CONSUMER
    |
    +-- SECURITYADMIN
            |
            +-- HELIOS_SECURITYADMIN
```

Additionally, two governance-specific roles exist outside this hierarchy:

- `HELIOS_DATA_STEWARD`: Full data access for governance and quality management
- `HELIOS_ANALYST`: Intermediate access with partial masking

### Role Definitions

| Role | Purpose | Database Access | Warehouse Access |
|------|---------|-----------------|------------------|
| HELIOS_DATA_STEWARD | Data governance, quality management | All databases, unmasked | TRANSFORM_WH |
| HELIOS_ANALYST | Advanced analytics, data science | HELIOS_ANALYTICS_DB, partial masking | TRANSFORM_WH |
| HELIOS_BI_CONSUMER | Dashboard consumption, reporting | HELIOS_ANALYTICS_DB, full masking | REPORTING_WH |
| HELIOS_DATA_ENGINEER | Pipeline development | All databases | All warehouses |
| HELIOS_DATA_ANALYST | Ad-hoc analysis | HELIOS_ANALYTICS_DB | REPORTING_WH |

### Grant Structure

Database and schema grants follow a consistent pattern:

```sql
-- Pattern for consumer roles
GRANT USAGE ON DATABASE <db> TO ROLE <role>;
GRANT USAGE ON SCHEMA <db>.<schema> TO ROLE <role>;
GRANT SELECT ON ALL TABLES IN SCHEMA <db>.<schema> TO ROLE <role>;
```

Warehouse grants are role-specific to enforce workload isolation:

```sql
GRANT USAGE ON WAREHOUSE REPORTING_WH TO ROLE HELIOS_BI_CONSUMER;
GRANT USAGE ON WAREHOUSE TRANSFORM_WH TO ROLE HELIOS_ANALYST;
```

### Test Users

Two isolated test users validate masking behavior without ACCOUNTADMIN inheritance:

| User | Default Role | Default Warehouse | Purpose |
|------|--------------|-------------------|---------|
| HELIOS_TEST_BI_USER | HELIOS_BI_CONSUMER | REPORTING_WH | Verify full masking |
| HELIOS_TEST_ANALYST_USER | HELIOS_ANALYST | TRANSFORM_WH | Verify partial masking |

---

## Data Governance

### Tagging Framework

Three object tags classify data across the platform:

#### PII_LEVEL Tag

Classifies personally identifiable information sensitivity:

| Value | Definition | Example Columns |
|-------|------------|-----------------|
| HIGH | Direct identifier, can be linked to individual | household_id |
| MEDIUM | Indirect identifier, demographic classification | acorn_group |
| LOW | Business data with minimal privacy impact | tariff_type |
| NONE | Non-sensitive operational data | energy_kwh, temperature |

#### DATA_DOMAIN Tag

Classifies data by business domain:

| Value | Description |
|-------|-------------|
| HOUSEHOLD | Customer and meter information |
| ENERGY | Consumption readings and metrics |
| WEATHER | Environmental conditions |
| FINANCIAL | Billing and tariff data |

#### RETENTION_POLICY Tag

Applied at database level to define data lifecycle:

| Value | Retention Period | Applied To |
|-------|------------------|------------|
| 90_DAYS | 3 months | HELIOS_RAW_DB |
| 1_YEAR | 12 months | HELIOS_TRANSFORM_DB |
| 7_YEARS | 84 months | HELIOS_ANALYTICS_DB |
| PERMANENT | Indefinite | HELIOS_AI_READY_DB |

#### Tag Application

Tags are applied at column level for PII classification:

```sql
ALTER TABLE HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD MODIFY COLUMN
    household_id SET TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL = 'HIGH';
```

Tags are applied at database level for retention:

```sql
ALTER DATABASE HELIOS_RAW_DB SET TAG
    HELIOS_GOVERNANCE_DB.POLICIES.RETENTION_POLICY = '90_DAYS';
```

### Dynamic Data Masking

Three masking policies protect sensitive columns based on session role:

#### MASK_HOUSEHOLD_ID

Protects household identifier (HIGH PII):

| Role | Output | Example |
|------|--------|---------|
| HELIOS_DATA_STEWARD | Full value | MAC000123 |
| ACCOUNTADMIN | Full value | MAC000123 |
| HELIOS_ANALYST | Partial mask (last 4 characters) | XXX0123 |
| All other roles | Full mask | ***MASKED*** |

Implementation:

```sql
CREATE OR REPLACE MASKING POLICY MASK_HOUSEHOLD_ID
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN val
    WHEN IS_ROLE_IN_SESSION('ACCOUNTADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN 'XXX' || RIGHT(val, 4)
    ELSE '***MASKED***'
  END;
```

#### MASK_ACORN_GROUP

Protects demographic classification (MEDIUM PII):

| Role | Output | Rationale |
|------|--------|-----------|
| HELIOS_DATA_STEWARD | Full value | Governance requires visibility |
| ACCOUNTADMIN | Full value | Administrative access |
| HELIOS_ANALYST | SHA256 hash | Enables grouping without revealing category |
| All other roles | Full mask | No demographic visibility |

The hash-based approach for analysts preserves analytical utility. Analysts can perform `GROUP BY acorn_group` operations and observe trends without knowing which hash corresponds to which demographic category.

#### MASK_TARIFF

Protects tariff type (LOW PII) with generalization:

| Role | Output | Example |
|------|--------|---------|
| HELIOS_DATA_STEWARD | Full value | Standard |
| HELIOS_ANALYST | Full value | Standard |
| HELIOS_BI_CONSUMER | Generalized category | STANDARD_TARIFF |
| All other roles | Full mask | ***MASKED*** |

Generalization mapping:
- Standard, Std -> STANDARD_TARIFF
- Time-of-Use, ToU -> VARIABLE_TARIFF
- All others -> OTHER_TARIFF

#### Policy Application

Masking policies are applied to columns across multiple tables:

| Table | Columns with Masking |
|-------|---------------------|
| HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD | household_id, acorn_group, tariff_type |
| HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION | household_id |
| HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO | household_id, acorn_group, tariff_type |

### Row Access Policy

A row access policy restricts data visibility based on time:

```sql
CREATE OR REPLACE ROW ACCESS POLICY RAP_ENERGY_DATA
AS (reading_timestamp TIMESTAMP_NTZ) RETURNS BOOLEAN ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('ACCOUNTADMIN') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('HELIOS_BI_CONSUMER') THEN 
      reading_timestamp >= DATEADD(MONTH, -12, CURRENT_DATE())
    ELSE FALSE
  END;
```

Access matrix:

| Role | Data Access |
|------|-------------|
| HELIOS_DATA_STEWARD | All historical data |
| HELIOS_ANALYST | All historical data |
| HELIOS_BI_CONSUMER | Last 12 months only |
| Other roles | No access |

#### Technical Constraint

Snowflake does not permit a column to have both a masking policy and serve as a row access policy argument. For this reason, the RAP uses `reading_timestamp` rather than `household_id`. This constraint influenced the policy design to use time-based rather than entity-based filtering.

### Governance Database

All governance objects reside in a dedicated database:

```
HELIOS_GOVERNANCE_DB.POLICIES
    |
    +-- Tags
    |   +-- PII_LEVEL
    |   +-- DATA_DOMAIN
    |   +-- RETENTION_POLICY
    |
    +-- Masking Policies
    |   +-- MASK_HOUSEHOLD_ID
    |   +-- MASK_ACORN_GROUP
    |   +-- MASK_TARIFF
    |
    +-- Row Access Policies
    |   +-- RAP_ENERGY_DATA
    |
    +-- Mapping Tables
    |   +-- ROLE_ACORN_MAPPING
    |   +-- ROLE_HOUSEHOLD_MAPPING
    |
    +-- Validation Views
        +-- V_MASKING_VALIDATION
```

### Policy Validation

The `V_MASKING_VALIDATION` view simulates masking output for each role without requiring role switching:

```sql
SELECT * FROM HELIOS_GOVERNANCE_DB.POLICIES.V_MASKING_VALIDATION;
```

This view replicates the masking policy logic to show expected output per role, enabling validation without creating test sessions.

---

## Resource Monitoring and Cost Control

### Resource Monitor Configuration

Five resource monitors enforce credit limits:

#### Account-Level Monitor

```sql
CREATE OR REPLACE RESOURCE MONITOR HELIOS_ACCOUNT_MONITOR
  WITH CREDIT_QUOTA = 200
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 90 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
```

This monitor serves as the hard limit for the entire account.

#### Per-Warehouse Monitors

| Monitor | Warehouse | Quota | 70% Action | 90% Action |
|---------|-----------|-------|------------|------------|
| INGEST_WH_MONITOR | INGEST_WH | 30 | Notify | Suspend |
| TRANSFORM_WH_MONITOR | TRANSFORM_WH | 50 | Notify | Suspend |
| REPORTING_WH_MONITOR | REPORTING_WH | 30 | Notify | Suspend |
| CORTEX_WH_MONITOR | CORTEX_WH | 60 | Notify | Suspend |

Total warehouse allocation (170 credits) remains below account limit (200 credits) to provide buffer for cloud services consumption.

### Consumption Views

Ten views in `HELIOS_ANALYTICS_DB.PUBLIC` provide consumption insights:

| View | Purpose | Data Source |
|------|---------|-------------|
| V_DAILY_CREDIT_SUMMARY | Daily credit totals | METERING_HISTORY |
| V_WAREHOUSE_DAILY_USAGE | Per-warehouse daily breakdown | WAREHOUSE_METERING_HISTORY |
| V_WAREHOUSE_HOURLY_PATTERN | Peak usage hour identification | WAREHOUSE_METERING_HISTORY |
| V_TOP_QUERIES_BY_COST | Most expensive queries (7 days) | QUERY_ATTRIBUTION_HISTORY |
| V_USER_CONSUMPTION | Credit usage by user | QUERY_ATTRIBUTION_HISTORY |
| V_DATABASE_STORAGE | Storage by Helios database | DATABASE_STORAGE_USAGE_HISTORY |
| V_CORTEX_AI_USAGE | Cortex function costs | CORTEX_FUNCTIONS_USAGE_HISTORY |
| V_RESOURCE_MONITOR_STATUS | Monitor quotas vs usage | RESOURCE_MONITORS |
| V_COST_ANOMALIES | ML-detected spending anomalies | ANOMALIES_DAILY |
| V_MTD_BUDGET_TRACKER | Month-to-date budget status | METERING_HISTORY |

#### V_MTD_BUDGET_TRACKER

Provides budget status with projection:

```sql
SELECT 
    MONTHLY_BUDGET,        -- 200
    MTD_CREDITS,           -- Credits used this month
    REMAINING_CREDITS,     -- Budget remaining
    PCT_CONSUMED,          -- Percentage consumed
    DAILY_BURN_RATE,       -- Average daily consumption
    DAYS_REMAINING,        -- Days left in month
    PROJECTED_MONTHLY,     -- Projected end-of-month total
    BUDGET_STATUS          -- ON TRACK | AT RISK | OVER BUDGET
FROM HELIOS_ANALYTICS_DB.PUBLIC.V_MTD_BUDGET_TRACKER;
```

### System Alerts

Three alerts monitor system health:

| Alert | Schedule | Condition | Action |
|-------|----------|-----------|--------|
| HELIOS_LONG_QUERY_ALERT | 15 minutes | Query > 5 minutes | Email notification |
| HELIOS_QUERY_FAILURE_ALERT | 60 minutes | Failure rate > 5% | Email notification |
| HELIOS_QUEUE_TIME_ALERT | 15 minutes | Avg queue > 30 seconds | Email notification |

Alerts execute on TRANSFORM_WH and send notifications via the `helios_alerts` notification integration.

---

## File Structure

```
project-helios/
|
+-- PROJECT_PLAN.md                  # This document
+-- Database_design.md               # Schema specifications
|
+-- 1_infra/
|   +-- warehouses.sql               # Warehouse definitions (SYSADMIN)
|   +-- netpolicies.sql              # Network policies (ACCOUNTADMIN)
|   +-- rbac.sql                     # Role hierarchy (SECURITYADMIN)
|
+-- 2_medallion/
|   +-- medallion_architecture.sql   # All layer definitions (SYSADMIN)
|
+-- 4_governance/
|   +-- tags.sql                     # Tag definitions and assignments
|   +-- masking.sql                  # Masking policy definitions
|   +-- row_access_pol.sql           # Row access policy
|   +-- governance_process.md        # Design rationale documentation
|
+-- 5_monitoring/
|   +-- monitors.sql                 # Resource monitor definitions
|   +-- consumption_views.sql        # ACCOUNT_USAGE views
|   +-- system_alerts.sql            # Alert definitions
|
+-- 7_testing/
    +-- synthetic_pipeline_test.sql  # Pipeline validation
    +-- Consumption_views_test.sql   # View validation
    +-- governance_policies_test.sql # Governance validation
    +-- rbac_access_test.sql         # RBAC validation
    +-- resource_monitors_test.sql   # Monitor validation
```

### Execution Context by File

Each SQL file includes role and warehouse context at the header:

| Directory | Role | Warehouse |
|-----------|------|-----------|
| 1_infra/rbac.sql | SECURITYADMIN | COMPUTE_WH |
| 1_infra/warehouses.sql | SYSADMIN | N/A |
| 1_infra/netpolicies.sql | ACCOUNTADMIN | COMPUTE_WH |
| 4_governance/*.sql | ACCOUNTADMIN | COMPUTE_WH |
| 5_monitoring/monitors.sql | ACCOUNTADMIN | N/A |
| 5_monitoring/consumption_views.sql | ACCOUNTADMIN | COMPUTE_WH |
| 5_monitoring/system_alerts.sql | ACCOUNTADMIN | TRANSFORM_WH |

---

## Testing Framework

### Test Coverage

Five test scripts validate all implemented components:

| Test Script | Validates |
|-------------|-----------|
| governance_policies_test.sql | Tags, masking policies, RAP, test users |
| rbac_access_test.sql | Role hierarchy, grants, warehouse access |
| resource_monitors_test.sql | Monitors, quotas, alerts, budget tracking |
| synthetic_pipeline_test.sql | Data flow through medallion layers |
| Consumption_views_test.sql | All 10 consumption insight views |

### Test Output Format

Tests return consistent result format:

```sql
SELECT 
    'TEST_NAME' AS TEST_NAME,
    CASE WHEN <condition> THEN 'PASS' ELSE 'FAIL' END AS RESULT,
    '<details>' AS DETAILS;
```

### Running Tests

Execute each test file individually. Tests query ACCOUNT_USAGE views which have inherent latency (1-3 seconds per query). Avoid combining tests with UNION ALL as latency compounds.

---

## Technical Constraints and Design Decisions

### Masking Policy and IS_ROLE_IN_SESSION

The `IS_ROLE_IN_SESSION()` function checks the entire role hierarchy of the current session, not just the active role. Consequence: users with ACCOUNTADMIN granted (even if not active) will see unmasked data regardless of their current role.

Mitigation: Test users (HELIOS_TEST_BI_USER, HELIOS_TEST_ANALYST_USER) have only their designated roles, enabling accurate masking validation.

### Masking and Row Access Policy Conflict

Snowflake prohibits using a masked column as a row access policy argument. The error `Column cannot be used as policy argument because it is masked by another policy` prevents entity-based RAP on household_id.

Resolution: RAP uses reading_timestamp instead, implementing time-based filtering rather than entity-based filtering.

### ACCOUNT_USAGE View Latency

ACCOUNT_USAGE views have up to 45-minute data latency. Tags may not appear in TAG_REFERENCES immediately after creation.

Workaround: Use `SYSTEM$GET_TAG()` for real-time tag verification:

```sql
SELECT SYSTEM$GET_TAG('HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL', 
    'HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD.HOUSEHOLD_ID', 'COLUMN');
```

### ACCOUNT_USAGE Column Name Discrepancies

Column names in ACCOUNT_USAGE views differ from SHOW command output and documentation examples. Always execute `DESCRIBE VIEW SNOWFLAKE.ACCOUNT_USAGE.<view_name>` before building queries.

Example discrepancy:
- SHOW RESOURCE MONITORS returns: `frequency`
- RESOURCE_MONITORS view contains: No `frequency` column (use CREATED instead)

---

## Appendix: Object Inventory

### Databases

| Database | Purpose | Tables | Views |
|----------|---------|--------|-------|
| HELIOS_RAW_DB | Bronze layer | 3 | 0 |
| HELIOS_TRANSFORM_DB | Silver layer | 3 | 0 |
| HELIOS_ANALYTICS_DB | Gold layer + monitoring | 3 | 11 |
| HELIOS_AI_READY_DB | Platinum layer | 1 | 1 |
| HELIOS_GOVERNANCE_DB | Governance objects | 2 | 1 |

### Roles

| Role | Type | Granted To |
|------|------|------------|
| HELIOS_DATA_STEWARD | Custom | ADIWORKSATARIS |
| HELIOS_ANALYST | Custom | ADIWORKSATARIS, HELIOS_TEST_ANALYST_USER |
| HELIOS_BI_CONSUMER | Custom | ADIWORKSATARIS, HELIOS_TEST_BI_USER |
| HELIOS_DATA_ENGINEER | Custom | (hierarchy) |
| HELIOS_DATA_ANALYST | Custom | (hierarchy) |
| HELIOS_SYSADMIN | Custom | SYSADMIN |
| HELIOS_SECURITYADMIN | Custom | SECURITYADMIN |

### Resource Monitors

| Monitor | Quota | Assigned To |
|---------|-------|-------------|
| HELIOS_ACCOUNT_MONITOR | 200 | Account |
| INGEST_WH_MONITOR | 30 | INGEST_WH |
| TRANSFORM_WH_MONITOR | 50 | TRANSFORM_WH |
| REPORTING_WH_MONITOR | 30 | REPORTING_WH |
| CORTEX_WH_MONITOR | 60 | CORTEX_WH |

---

*Document Version: 2.1*
*Last Updated: 2026-02-27*
*Project Codename: HELIOS*
