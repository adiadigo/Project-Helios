# Project Helios: Smart Grid Telemetry & Forecasting Platform

## Executive Summary

**Project Helios** is an enterprise-grade Smart Grid Telemetry and Forecasting Platform built on Snowflake for the Energy sector. The platform ingests, transforms, and analyzes high-velocity IoT data from the London Smart Meter dataset to enable real-time energy consumption monitoring, demand forecasting, and operational intelligence.

### Problem Statement

Energy utilities face critical challenges in managing smart grid infrastructure:
- **Data Volume**: Millions of half-hourly meter readings require scalable ingestion pipelines
- **Data Latency**: Real-time visibility into consumption patterns is essential for grid stability
- **Forecasting Accuracy**: Accurate demand prediction prevents outages and optimizes generation
- **Regulatory Compliance**: PII protection and audit trails are mandatory for energy data
- **Cost Control**: Unmanaged compute costs can spiral with continuous streaming workloads

### Solution

Project Helios delivers a complete data platform leveraging Snowflake's native capabilities:
- **Snowpipe** for continuous, event-driven ingestion from AWS S3
- **Medallion Architecture** (Bronze → Silver → Gold → Platinum) for data quality progression
- **Cortex ML** for native time-series forecasting without external tooling
- **Cortex Analyst** for natural language querying via semantic models
- **Dynamic Data Masking & Row Access Policies** for governance at scale
- **Resource Monitors & Alerts** for FinOps cost control

---

## Architecture

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL SOURCES                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐          │
│   │  Smart Meters    │    │  Household Info  │    │  Weather API     │          │
│   │  (IoT Devices)   │    │  (CSV Upload)    │    │  (Dark Sky)      │          │
│   └────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘          │
│            │                       │                       │                     │
│            ▼                       ▼                       ▼                     │
│   ┌─────────────────────────────────────────────────────────────────┐           │
│   │                    AWS S3 BUCKET                                 │           │
│   │              s3://helios-smart-grid-telemetry                    │           │
│   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │           │
│   │  │ /readings/  │  │ /households/│  │ /weather/   │              │           │
│   │  │ block_*.csv │  │ info.csv    │  │ hourly.csv  │              │           │
│   │  └─────────────┘  └─────────────┘  └─────────────┘              │           │
│   └─────────────────────────────┬───────────────────────────────────┘           │
│                                 │                                                │
│                                 │ SQS Event Notification                         │
│                                 ▼                                                │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SNOWFLAKE PLATFORM                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                         INGESTION LAYER                                    │  │
│  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                    │  │
│  │  │ STORAGE     │    │ SNOWPIPE    │    │ INGEST_WH   │                    │  │
│  │  │ INTEGRATION │───▶│ (Auto-Load) │───▶│ (X-Small)   │                    │  │
│  │  └─────────────┘    └─────────────┘    └─────────────┘                    │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                           │
│                                      ▼                                           │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                    MEDALLION DATA ARCHITECTURE                             │  │
│  │                                                                            │  │
│  │  ┌────────────────┐   ┌────────────────┐   ┌────────────────┐             │  │
│  │  │   BRONZE       │   │    SILVER      │   │     GOLD       │             │  │
│  │  │ HELIOS_RAW_DB  │──▶│HELIOS_TRANSFORM│──▶│HELIOS_ANALYTICS│             │  │
│  │  │                │   │      _DB       │   │      _DB       │             │  │
│  │  │ • RAW_READINGS │   │ • CLEAN_       │   │ • FACT_ENERGY_ │             │  │
│  │  │ • RAW_HOUSEHOLD│   │   READINGS     │   │   CONSUMPTION  │             │  │
│  │  │ • RAW_WEATHER  │   │ • CLEAN_       │   │ • DIM_HOUSEHOLD│             │  │
│  │  │                │   │   HOUSEHOLD    │   │ • DIM_WEATHER  │             │  │
│  │  │ (VARIANT/STR)  │   │ • CLEAN_WEATHER│   │ • DIM_DATE     │             │  │
│  │  │                │   │                │   │                │             │  │
│  │  │                │   │ (Typed Columns)│   │ (Star Schema)  │             │  │
│  │  └────────────────┘   └────────────────┘   └────────────────┘             │  │
│  │         │                     │                    │                       │  │
│  │         │    TRANSFORM_WH     │    TRANSFORM_WH    │    REPORTING_WH       │  │
│  │         ▼                     ▼                    ▼                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                        PLATINUM LAYER                                │  │  │
│  │  │                      HELIOS_AI_READY_DB                              │  │  │
│  │  │  ┌─────────────────────┐    ┌─────────────────────┐                  │  │  │
│  │  │  │   ML FORECASTS      │    │   SEMANTIC MODEL    │                  │  │  │
│  │  │  │ • FORECAST_RESULTS  │    │ • energy_model.yaml │                  │  │  │
│  │  │  │ • ANOMALY_SCORES    │    │ (Cortex Analyst)    │                  │  │  │
│  │  │  │ (Cortex ML)         │    │                     │                  │  │  │
│  │  │  └─────────────────────┘    └─────────────────────┘                  │  │  │
│  │  │              │                         │                              │  │  │
│  │  │              │      CORTEX_WH          │                              │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                      SECURITY & GOVERNANCE                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │Network Policy│  │Dynamic Masking│ │Row Access    │  │Object Tags   │   │  │
│  │  │(IP Allowlist)│  │(PII Fields)  │  │Policy (Region)│ │(PII, SENS)   │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                         FINOPS & MONITORING                                │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │Resource      │  │Account Usage │  │Email Alerts  │  │Audit Views   │   │  │
│  │  │Monitors      │  │Dashboards    │  │(Cost/Failure)│  │(Login/Query) │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              RBAC HIERARCHY                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│                            ACCOUNTADMIN                                          │
│                                  │                                               │
│                    ┌─────────────┴─────────────┐                                │
│                    ▼                           ▼                                │
│               SYSADMIN                   SECURITYADMIN                          │
│                    │                           │                                │
│                    ▼                           ▼                                │
│           HELIOS_SYSADMIN            HELIOS_SECURITYADMIN                       │
│                    │                                                            │
│                    ▼                                                            │
│           HELIOS_DATA_ENGINEER                                                  │
│                    │                                                            │
│                    ▼                                                            │
│           HELIOS_DATA_ANALYST                                                   │
│                    │                                                            │
│                    ▼                                                            │
│           HELIOS_BI_CONSUMER                                                    │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Compute Resources

| Warehouse | Size | Purpose | Primary Role |
|-----------|------|---------|--------------|
| INGEST_WH | X-Small | Snowpipe loading, COPY INTO | HELIOS_DATA_ENGINEER |
| TRANSFORM_WH | Small | ELT transformations, Tasks | HELIOS_DATA_ENGINEER |
| REPORTING_WH | X-Small | BI queries, dashboards | HELIOS_DATA_ANALYST |
| CORTEX_WH | Small | ML training, inference | HELIOS_DATA_ENGINEER |

---

## 15-Phase Execution Checklist

### Phase 1: Network Security
- [ ] Create INFRA_DB database for infrastructure objects
- [ ] Create Network Rule for allowed IP ranges
- [ ] Create Network Policy referencing the rule
- [ ] Apply Network Policy to account/users

### Phase 2: Role-Based Access Control (RBAC)
- [ ] Create HELIOS_SYSADMIN role
- [ ] Create HELIOS_SECURITYADMIN role
- [ ] Create HELIOS_DATA_ENGINEER role
- [ ] Create HELIOS_DATA_ANALYST role
- [ ] Create HELIOS_BI_CONSUMER role
- [ ] Establish role hierarchy with GRANT ROLE statements
- [ ] Connect custom roles to system roles

### Phase 3: Compute Warehouses
- [ ] Create INGEST_WH (X-Small, auto-suspend 60s)
- [ ] Create TRANSFORM_WH (Small, auto-suspend 60s)
- [ ] Create REPORTING_WH (X-Small, auto-suspend 60s)
- [ ] Create CORTEX_WH (Small, auto-suspend 60s)
- [ ] Grant USAGE privileges to appropriate roles

### Phase 4: Medallion Databases & Schemas
- [ ] Create HELIOS_RAW_DB (Bronze layer)
- [ ] Create HELIOS_TRANSFORM_DB (Silver layer)
- [ ] Create HELIOS_ANALYTICS_DB (Gold layer)
- [ ] Create HELIOS_AI_READY_DB (Platinum layer)
- [ ] Create schemas within each database
- [ ] Grant database/schema privileges to roles

### Phase 5: External Storage Integration
- [ ] Create Storage Integration for AWS S3
- [ ] Create External Stages for each data source
- [ ] Test stage connectivity with LIST commands
- [ ] Grant USAGE on stages to HELIOS_DATA_ENGINEER

### Phase 6: Raw Layer Tables & Snowpipe
- [ ] Create RAW_READINGS table (VARIANT or raw strings)
- [ ] Create RAW_HOUSEHOLDS table
- [ ] Create RAW_WEATHER table
- [ ] Create Snowpipe for readings ingestion
- [ ] Create Snowpipe for households ingestion
- [ ] Create Snowpipe for weather ingestion
- [ ] Configure SQS notifications (external)

### Phase 7: Data Governance - Tagging
- [ ] Create tag HELIOS_PII for personally identifiable information
- [ ] Create tag HELIOS_SENSITIVE for business-sensitive data
- [ ] Create tag HELIOS_COST_CENTER for chargeback
- [ ] Apply tags to relevant columns and objects

### Phase 8: Data Governance - Masking & Row Access
- [ ] Create Dynamic Data Masking policy for LCLid
- [ ] Create Dynamic Data Masking policy for Tariff
- [ ] Create Dynamic Data Masking policy for ACORN Group
- [ ] Create Row Access Policy for regional data restriction
- [ ] Apply masking policies to relevant columns
- [ ] Apply row access policy to fact tables

### Phase 9: FinOps - Resource Monitors
- [ ] Create Account-level Resource Monitor (hard limit)
- [ ] Create INGEST_WH Resource Monitor
- [ ] Create TRANSFORM_WH Resource Monitor
- [ ] Create REPORTING_WH Resource Monitor
- [ ] Create CORTEX_WH Resource Monitor
- [ ] Set appropriate credit thresholds and actions

### Phase 10: FinOps - Monitoring Views
- [ ] Create view: Daily Credit Consumption by Warehouse
- [ ] Create view: Weekly Credit Trend Analysis
- [ ] Create view: Query Performance by User
- [ ] Create view: Warehouse Queue Time Analysis
- [ ] Create view: Storage Consumption by Database
- [ ] Create view: Top 10 Expensive Queries
- [ ] Create view: Failed Query Analysis
- [ ] Create view: User Activity Summary
- [ ] Create view: Role Usage Statistics
- [ ] Create view: Data Transfer Metrics

### Phase 11: FinOps - Alerts
- [ ] Create alert: Daily Credit Threshold Exceeded
- [ ] Create alert: Warehouse Queue Time High
- [ ] Create alert: Query Failure Rate Spike
- [ ] Create alert: Unusual Login Activity
- [ ] Create alert: Large Data Transfer Detected
- [ ] Create alert: Storage Growth Anomaly
- [ ] Create alert: Long-Running Query Detected
- [ ] Create alert: Resource Monitor Warning
- [ ] Create alert: Failed Authentication Attempts
- [ ] Create alert: Schema Change Detected

### Phase 12: Transform Layer (Silver)
- [ ] Create CLEAN_READINGS table with typed columns
- [ ] Create CLEAN_HOUSEHOLDS table with typed columns
- [ ] Create CLEAN_WEATHER table with typed columns
- [ ] Create Stream on RAW_READINGS for CDC
- [ ] Create Task for continuous RAW → CLEAN transformation
- [ ] Implement data quality checks in transformation

### Phase 13: Analytics Layer (Gold)
- [ ] Create DIM_DATE dimension table
- [ ] Create DIM_HOUSEHOLD dimension table
- [ ] Create DIM_WEATHER dimension table
- [ ] Create FACT_ENERGY_CONSUMPTION fact table
- [ ] Create Stream on CLEAN tables for CDC
- [ ] Create Task for Silver → Gold transformation
- [ ] Create aggregation views for reporting

### Phase 14: Verification & Testing
- [ ] Create row count validation: RAW vs CLEAN
- [ ] Create row count validation: CLEAN vs ANALYTICS
- [ ] Create data quality check: NULL value percentages
- [ ] Create data quality check: Value range validation
- [ ] Create referential integrity check: FK validation
- [ ] Create freshness check: Latest timestamp validation

### Phase 15: AI & ML Layer (Platinum)
- [ ] Create FORECAST_RESULTS table for ML output
- [ ] Create ANOMALY_SCORES table for anomaly detection
- [ ] Train Cortex ML FORECAST model on consumption data
- [ ] Create scheduled Task for forecast refresh
- [ ] Create Semantic Model YAML for Cortex Analyst
- [ ] Deploy Semantic Model to stage
- [ ] Test Cortex Analyst natural language queries

---

## Repository Structure

```
project-helios/
│
├── PROJECT_PLAN.md                    # This file - Master documentation
├── README.md                          # Quick start guide (auto-generated)
│
├── 1_infra/                           # Phase 1-3: Infrastructure & Security
│   ├── warehouses.sql                 # Warehouse creation + grants
│   ├── netpolicies.sql                # Network rules and policies
│   └── rbac.sql                       # Roles and hierarchy
│
├── 2_storage/                         # Phase 4-6: Storage & Ingestion
│   ├── databases.sql                  # Medallion databases and schemas
│   ├── storage_integration.sql        # AWS S3 storage integration
│   ├── stages.sql                     # External stages for each source
│   ├── raw_tables.sql                 # Bronze layer table definitions
│   └── snowpipes.sql                  # Snowpipe definitions for auto-ingest
│
├── 3_governance/                      # Phase 7-8: Data Governance
│   ├── tags.sql                       # Object and column tags
│   ├── masking_policies.sql           # Dynamic data masking policies
│   └── row_access_policies.sql        # Row-level security policies
│
├── 4_finops/                          # Phase 9-11: FinOps & Monitoring
│   ├── resource_monitors.sql          # Account and warehouse monitors
│   ├── monitoring_views.sql           # ACCOUNT_USAGE analytical views
│   ├── alerts.sql                     # SYSTEM$SEND_EMAIL alert definitions
│   └── audit_views.sql                # Login and query history views
│
├── 5_transformation/                  # Phase 12-13: ELT Pipeline
│   ├── silver_tables.sql              # Clean/typed table definitions
│   ├── gold_tables.sql                # Star schema tables (facts + dims)
│   ├── streams.sql                    # CDC streams for incremental load
│   ├── tasks.sql                      # Scheduled transformation tasks
│   └── views.sql                      # Reporting and aggregation views
│
├── 6_ai_and_analytics/                # Phase 15: AI/ML Layer
│   ├── ml_tables.sql                  # Forecast and anomaly output tables
│   ├── cortex_ml.sql                  # Cortex ML model training/inference
│   ├── semantic_model.yaml            # Cortex Analyst semantic model
│   └── ml_tasks.sql                   # Scheduled ML refresh tasks
│
└── 7_testing/                         # Phase 14: Verification
    ├── row_count_validation.sql       # Layer-to-layer count checks
    ├── data_quality_checks.sql        # NULL, range, and type validation
    └── freshness_checks.sql           # Data latency monitoring
```

### File Naming Conventions

| Pattern | Purpose | Example |
|---------|---------|---------|
| `*.sql` | Executable DDL/DML scripts | `warehouses.sql` |
| `*.yaml` | Semantic model definitions | `semantic_model.yaml` |
| `*_test.sql` | Test/validation scripts | `row_count_test.sql` |

### Execution Order

Scripts should be executed in numerical folder order (1_ → 2_ → 3_ → ...) and alphabetically within each folder unless dependencies require otherwise.

---

## Success Criteria

| Metric | Target |
|--------|--------|
| Data Freshness | < 5 minutes from S3 landing to RAW |
| Transform Latency | < 15 minutes from RAW to ANALYTICS |
| Forecast Accuracy | MAPE < 15% on 24-hour predictions |
| Query Performance | P95 < 5 seconds for dashboard queries |
| Cost Control | < 100 credits/day during development |
| Data Quality | > 99.5% row-level completeness |
| Zero Data Loss | RAW count = ANALYTICS count (validated) |

---

## Contacts & Ownership

| Role | Responsibility |
|------|----------------|
| Data Platform Lead | Architecture, infrastructure, FinOps |
| Data Engineer | Ingestion, transformation, testing |
| Analytics Engineer | Gold layer, semantic models, Cortex |
| Security Admin | RBAC, masking, row access policies |

---

*Document Version: 1.0*  
*Last Updated: 2026-02-24*  
*Project Codename: HELIOS*
