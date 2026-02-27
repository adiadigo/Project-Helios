# Project Helios: Governance Design Process

**Author:** Cortex Code  
**Date:** 2026-02-26  
**Version:** 1.0

---

## Executive Summary

This document details the decision-making process behind the data governance framework implemented for Project Helios. The framework addresses three core pillars: **data classification** (tags), **column-level security** (masking policies), and **row-level security** (row access policies).

---

## 1. Understanding the Data Landscape

### 1.1 Data Sensitivity Analysis

Before designing governance controls, I analyzed the Helios data model to identify sensitive elements:

| Data Element | Sensitivity Concern | Risk if Exposed |
|--------------|---------------------|-----------------|
| `household_id` | Direct identifier for smart meter/household | Can be correlated with physical addresses, energy patterns reveal occupancy |
| `acorn_group` | Demographic classification (socioeconomic) | Reveals income bracket, lifestyle patterns - discriminatory potential |
| `tariff_type` | Service tier indicator | Less sensitive but reveals customer segmentation |
| `energy_kwh` | Usage data | Non-PII but sensitive when combined with household_id |
| `reading_timestamp` | Temporal data | Can reveal behavioral patterns (home/away times) |

### 1.2 Key Insight: Smart Meter Data is Quasi-PII

Smart meter data presents a unique challenge: while `energy_kwh` readings are not PII in isolation, they become **quasi-identifiers** when combined with temporal patterns. Research has shown that energy consumption patterns can:
- Reveal occupancy patterns (security risk)
- Indicate appliance usage (lifestyle inference)
- Identify household composition changes

This insight drove the decision to implement **layered protection** rather than simple column masking.

---

## 2. Tag Design Decisions

### 2.1 Why Three Tags?

I selected three tag dimensions that address distinct governance concerns:

```
┌─────────────────────────────────────────────────────────────────┐
│                     TAG TAXONOMY                                │
├─────────────────────────────────────────────────────────────────┤
│  PII_LEVEL        → Security/Privacy controls                   │
│  DATA_DOMAIN      → Business ownership/stewardship              │
│  RETENTION_POLICY → Compliance/lifecycle management             │
└─────────────────────────────────────────────────────────────────┘
```

**Alternative Considered:** A single `SENSITIVITY` tag with values like `PUBLIC`, `INTERNAL`, `CONFIDENTIAL`, `RESTRICTED`. 

**Why Rejected:** This approach conflates multiple concerns. A column might be `CONFIDENTIAL` from a privacy perspective but `PUBLIC` from a retention perspective. Multi-dimensional tagging provides flexibility for different governance use cases.

### 2.2 PII_LEVEL Values Explained

| Value | Definition | Application Criteria |
|-------|------------|---------------------|
| `HIGH` | Direct or easily linkable identifier | `household_id` - can be joined to external datasets |
| `MEDIUM` | Indirect identifier with discrimination risk | `acorn_group` - demographic data with bias potential |
| `LOW` | Business data with minimal privacy impact | `tariff_type` - service tier, not personally identifying |
| `NONE` | Non-sensitive operational data | `energy_kwh`, `temperature` - metrics without identity link |

**Design Principle:** The classification follows GDPR's concept of "special category data" where demographic/socioeconomic indicators receive elevated protection.

### 2.3 RETENTION_POLICY by Database Layer

| Database | Retention | Rationale |
|----------|-----------|-----------|
| `HELIOS_RAW_DB` | 90_DAYS | Bronze layer - raw ingestion, short retention for debugging/reprocessing |
| `HELIOS_TRANSFORM_DB` | 1_YEAR | Silver layer - cleaned data, retained for audit trail |
| `HELIOS_ANALYTICS_DB` | 7_YEARS | Gold layer - business reporting, regulatory retention requirements |
| `HELIOS_AI_READY_DB` | PERMANENT | ML features - model reproducibility requires historical access |

**Consideration:** UK energy regulations require 7-year retention for billing disputes. The gold layer inherits this requirement.

---

## 3. Masking Policy Design

### 3.1 Why Three Distinct Policies?

Rather than a single "mask everything" approach, I created **purpose-specific policies** that balance security with usability:

```
┌─────────────────────────────────────────────────────────────────┐
│              MASKING STRATEGY MATRIX                            │
├────────────────────┬────────────────────────────────────────────┤
│ Policy             │ Strategy                                   │
├────────────────────┼────────────────────────────────────────────┤
│ MASK_HOUSEHOLD_ID  │ Partial reveal (last 4) for analysts       │
│ MASK_ACORN_GROUP   │ Hash for grouping without revealing value  │
│ MASK_TARIFF        │ Generalize to categories                   │
└────────────────────┴────────────────────────────────────────────┘
```

### 3.2 MASK_HOUSEHOLD_ID: Partial Masking

**Decision:** Show last 4 characters for HELIOS_ANALYST role.

```sql
WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN 'XXX' || RIGHT(val, 4)
```

**Rationale:**
- Analysts need to verify join accuracy during development
- Last 4 characters allow visual confirmation without full ID exposure
- Pattern: `MAC000123` → `XXX0123`

**Alternative Considered:** Full SHA256 hash.

**Why Rejected:** Hashing prevents analysts from debugging data quality issues. A common scenario: "Why are 50 records not joining?" Partial masking allows pattern recognition (`XXX0123` appears twice = duplicate key issue) while preventing full identifier reconstruction.

### 3.3 MASK_ACORN_GROUP: Hash-Based Masking

**Decision:** Apply SHA256 hash for HELIOS_ANALYST role.

```sql
WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN SHA2(val, 256)
```

**Rationale:**
- ACORN groups are **categorical data** used for segmentation analysis
- Analysts need to GROUP BY acorn_group without knowing the actual values
- SHA256 produces consistent hashes, preserving analytical utility:
  - `COUNT(*) GROUP BY acorn_group` still works
  - Trend analysis (`acorn_group_hash` increased 20% MoM) still valid
- Actual values (`Affluent`, `Adversity`) are hidden, preventing bias in analysis interpretation

**Design Principle:** This implements **k-anonymity** principles - the analyst sees groups but cannot make discriminatory decisions based on knowing which group is "Affluent" vs "Adversity".

### 3.4 MASK_TARIFF: Generalization

**Decision:** Generalize specific tariff codes to broader categories.

```sql
WHEN IS_ROLE_IN_SESSION('HELIOS_BI_CONSUMER') THEN 
  CASE 
    WHEN val IN ('Standard', 'Std') THEN 'STANDARD_TARIFF'
    WHEN val IN ('Time-of-Use', 'ToU') THEN 'VARIABLE_TARIFF'
    ELSE 'OTHER_TARIFF'
  END
```

**Rationale:**
- BI consumers need tariff information for business reporting
- Exact tariff codes may reveal competitive pricing strategies
- Generalization preserves analytical value while reducing specificity

**Alternative Considered:** No masking for tariff data.

**Why Rejected:** Although low-sensitivity, tariff proliferation (10+ specific codes) creates confusion in BI dashboards. Generalization improves both security AND usability.

---

## 4. Row Access Policy Design

### 4.1 The Column Conflict Challenge

**Problem Encountered:** Snowflake does not allow a column to have BOTH a masking policy AND be used as a row access policy argument.

```
Error: Column 'HOUSEHOLD_ID' cannot be used as policy argument 
       because it is masked by another policy.
```

**Initial Design (Failed):**
```sql
-- This approach failed
CREATE ROW ACCESS POLICY RAP_HOUSEHOLD_ACCESS
AS (household_id VARCHAR) RETURNS BOOLEAN -> ...
```

### 4.2 Solution: Time-Based Row Access

**Pivoted Strategy:** Instead of filtering by `household_id`, I implemented time-based filtering using `reading_timestamp`:

```sql
CREATE ROW ACCESS POLICY RAP_ENERGY_DATA
AS (reading_timestamp TIMESTAMP_NTZ) RETURNS BOOLEAN ->
  CASE
    WHEN IS_ROLE_IN_SESSION('HELIOS_DATA_STEWARD') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('HELIOS_ANALYST') THEN TRUE
    WHEN IS_ROLE_IN_SESSION('HELIOS_BI_CONSUMER') THEN 
      reading_timestamp >= DATEADD(MONTH, -12, CURRENT_DATE())
    ELSE FALSE
  END
```

**Rationale:**
- BI consumers typically need recent data for dashboards (last 12 months)
- Historical data has diminishing business value but constant privacy risk
- Time-based filtering reduces attack surface (fewer rows = less exposure)

### 4.3 Defense in Depth

The final architecture implements **layered security**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Row Access Policy                                     │
│           └─ Filters WHICH rows a role can see                  │
│                                                                 │
│  Layer 2: Masking Policies                                      │
│           └─ Controls HOW visible rows appear                   │
│                                                                 │
│  Layer 3: Tags                                                  │
│           └─ Documents WHAT sensitivity each column has         │
│                                                                 │
│  Layer 4: RBAC (Roles)                                          │
│           └─ Determines WHO can access objects                  │
└─────────────────────────────────────────────────────────────────┘
```

A HELIOS_BI_CONSUMER querying FACT_ENERGY_CONSUMPTION:
1. **RAP filters rows** → Only sees last 12 months
2. **Masking hides household_id** → Sees `***MASKED***`
3. **Tags document** → Audit trail shows HIGH PII was accessed (masked)
4. **RBAC enforces** → Can only access gold layer, not raw/silver

---

## 5. Role Hierarchy Design

### 5.1 Three-Tier Access Model

```
                    ACCOUNTADMIN
                         │
              ┌──────────┴──────────┐
              │                     │
    HELIOS_DATA_STEWARD      (other admin roles)
              │
              │
       HELIOS_ANALYST
              │
              │
    HELIOS_BI_CONSUMER
```

### 5.2 Role Definitions

| Role | Purpose | Access Pattern |
|------|---------|----------------|
| `HELIOS_DATA_STEWARD` | Data governance, quality management | Full access, can see all PII for data correction |
| `HELIOS_ANALYST` | Data science, advanced analytics | Partial masking, needs join capability |
| `HELIOS_BI_CONSUMER` | Dashboard consumers, business users | Heavy masking, time-limited, aggregation focus |

**Design Principle:** Follows **principle of least privilege** - each role gets minimum access required for their job function.

---

## 6. Challenges and Lessons Learned

### 6.1 Masking + RAP Column Conflict

**Lesson:** Plan column usage before applying policies. If a column needs both masking AND row-level filtering, consider:
- Adding a surrogate key column for RAP
- Using a different filter dimension (time, region, etc.)
- Creating a secure view with pre-filtered data

### 6.2 ACCOUNT_USAGE Latency

**Observation:** Tag assignments don't appear immediately in `SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES`. Use `SYSTEM$GET_TAG()` for real-time verification.

### 6.3 Policy Testing Strategy

**Recommendation:** Always test policies by temporarily assuming each role:

```sql
USE ROLE HELIOS_BI_CONSUMER;
SELECT * FROM HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD LIMIT 5;
-- Verify masking appears correctly

USE ROLE HELIOS_ANALYST;
SELECT * FROM HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD LIMIT 5;
-- Verify partial masking for household_id
```

---

## 7. Future Enhancements

### 7.1 Tag-Based Dynamic Masking

Instead of hardcoding policies per column, implement **tag-based policy assignment**:

```sql
-- Future: Apply masking based on PII_LEVEL tag
ALTER TAG HELIOS_GOVERNANCE_DB.POLICIES.PII_LEVEL 
  SET MASKING POLICY HELIOS_GOVERNANCE_DB.POLICIES.DYNAMIC_MASK;
```

### 7.2 Automated Classification

Consider implementing `SYSTEM$CLASSIFY` for automatic PII detection on new columns:

```sql
CALL SYSTEM$CLASSIFY('HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO', 
  {'auto_tag': true});
```

### 7.3 Access Request Workflow

Build a Streamlit app for self-service access requests:
- User requests access to specific ACORN groups
- Data steward approves/denies
- Automatic `ROLE_ACORN_MAPPING` table update

---

## 8. Artifacts Summary

| File | Contents |
|------|----------|
| `/4_governance/tags.sql` | Tag definitions + column assignments |
| `/4_governance/masking.sql` | 3 masking policies + application statements |
| `/4_governance/row_access_pol.sql` | RAP definition + mapping tables |
| `/4_governance/governance_process.md` | This document |

---

## 9. Compliance Alignment

| Regulation | How Addressed |
|------------|---------------|
| **GDPR** | PII_LEVEL tag identifies personal data; masking implements "privacy by design" |
| **UK DPA 2018** | ACORN group masking prevents automated decision-making on protected characteristics |
| **OFGEM Requirements** | 7-year retention on gold layer; audit trail via ACCOUNT_USAGE |

---

*Document Version: 1.0*  
*Last Updated: 2026-02-26*  
*Project Codename: HELIOS*
