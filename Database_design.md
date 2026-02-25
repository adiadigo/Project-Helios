# Project Helios: Database Design Justification Document

## Executive Summary

This document provides meticulous justification for every architectural decision in the Project Helios medallion data architecture. Each database, schema, table, column, constraint, view, and join strategy is explained with rationale grounded in data engineering best practices, Snowflake-specific optimizations, and the unique requirements of smart meter telemetry data.

---

## 1. Database Layer Decisions

### 1.1 Four Separate Databases

**Decision:** Create four distinct databases instead of one database with multiple schemas.

```sql
CREATE DATABASE IF NOT EXISTS HELIOS_RAW_DB;
CREATE DATABASE IF NOT EXISTS HELIOS_TRANSFORM_DB;
CREATE DATABASE IF NOT EXISTS HELIOS_ANALYTICS_DB;
CREATE DATABASE IF NOT EXISTS HELIOS_AI_READY_DB;
```

**Justification:**

| Reason | Explanation |
|--------|-------------|
| **Access Control Isolation** | Snowflake grants operate at database level. Separating databases allows HELIOS_BI_CONSUMER to access ANALYTICS_DB without granting access to RAW_DB containing unmasked PII. |
| **Cost Attribution** | Snowflake's ACCOUNT_USAGE views track storage by database. Separate databases enable precise chargeback for raw vs. analytics storage costs. |
| **Data Lifecycle Management** | RAW_DB may have different retention policies (e.g., 90-day Time Travel) than ANALYTICS_DB (e.g., 7-day). Database-level settings simplify this. |
| **Failure Domain Isolation** | A failed COPY INTO on RAW_DB doesn't lock tables in ANALYTICS_DB. Transactions are scoped to their database context. |
| **Medallion Pattern Clarity** | Industry-standard Bronze/Silver/Gold/Platinum naming maps cleanly to separate databases, improving discoverability for new team members. |

**Alternative Considered:** Single database with `RAW`, `TRANSFORM`, `ANALYTICS`, `AI_READY` schemas.

**Why Rejected:** Schema-level grants are more complex to manage, and storage metrics would be aggregated, losing visibility into layer-specific costs.

---

### 1.2 Database Naming Convention: `HELIOS_<LAYER>_DB`

**Decision:** Prefix all databases with `HELIOS_` and suffix with `_DB`.

**Justification:**

| Reason | Explanation |
|--------|-------------|
| **Namespace Isolation** | Prevents collision with other projects in shared Snowflake accounts. `RAW_DB` alone could conflict; `HELIOS_RAW_DB` is unambiguous. |
| **Discoverability** | `SHOW DATABASES LIKE 'HELIOS%'` instantly reveals all project assets. |
| **Consistency** | The `_DB` suffix distinguishes databases from schemas or tables in documentation and conversation. |

---

## 2. Schema Layer Decisions

### 2.1 Single `GRID` Schema Per Database

**Decision:** Use one schema named `GRID` in each database instead of multiple schemas (e.g., `READINGS`, `REFERENCE`, `WEATHER`).

```sql
CREATE SCHEMA IF NOT EXISTS HELIOS_RAW_DB.GRID;
CREATE SCHEMA IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID;
CREATE SCHEMA IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID;
CREATE SCHEMA IF NOT EXISTS HELIOS_AI_READY_DB.GRID;
```

**Justification:**

| Reason | Explanation |
|--------|-------------|
| **Simplified Grants** | One `GRANT USAGE ON SCHEMA` per database instead of multiple. Reduces RBAC complexity. |
| **Reduced Cognitive Load** | Developers don't need to remember which schema contains which table. All objects are in `GRID`. |
| **Consistent Fully-Qualified Names** | `HELIOS_RAW_DB.GRID.RAW_METER_DATA` follows a predictable pattern. |
| **Lean Architecture** | With only 3-4 tables per layer, multiple schemas add overhead without benefit. |

**Alternative Considered:** `READINGS`, `REFERENCE`, `WEATHER` schemas in RAW_DB.

**Why Rejected:** For 3 tables, the overhead of managing 3 schemas (grants, documentation, navigation) outweighs the organizational benefit. Single schema is sufficient.

### 2.2 Schema Name: `GRID`

**Decision:** Name the schema `GRID` (not `PUBLIC`, `MAIN`, or `DATA`).

**Justification:**

| Reason | Explanation |
|--------|-------------|
| **Domain Relevance** | "Grid" refers to the electrical grid—the core domain of this project. It's semantically meaningful. |
| **Avoids Reserved Words** | `PUBLIC` is Snowflake's default schema and has special behavior. Custom names avoid confusion. |
| **Brevity** | 4 characters keeps fully-qualified names manageable: `HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION`. |

---

## 3. Bronze Layer: HELIOS_RAW_DB.GRID

### 3.1 Design Philosophy

**Principle:** Land data exactly as received. No transformations, no type casting, no filtering. Preserve source fidelity for auditability and reprocessing.

---

### 3.2 RAW_METER_DATA

```sql
CREATE TABLE IF NOT EXISTS HELIOS_RAW_DB.GRID.RAW_METER_DATA (
    LCLid           VARCHAR,
    tstp            VARCHAR,
    energy          VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR
);
```

#### Column Decisions

| Column | Type | Justification |
|--------|------|---------------|
| `LCLid` | VARCHAR | **Preserve source format.** The CSV contains string identifiers like `MAC000001`. Casting to an integer would lose the prefix. VARCHAR accommodates any format. |
| `tstp` | VARCHAR | **Defer parsing to Silver layer.** Source timestamps may have inconsistent formats (`2012-10-12 00:30:00` vs `2012/10/12 00:30`). VARCHAR landing prevents COPY failures on malformed rows. |
| `energy` | VARCHAR | **Handle edge cases.** Source may contain blanks, `Null` strings, or scientific notation (`1.23E-4`). VARCHAR landing captures all values; Silver layer handles conversion. |
| `_loaded_at` | TIMESTAMP_NTZ | **Audit trail.** Records when each row was ingested. Essential for debugging Snowpipe latency and identifying stale data. `DEFAULT CURRENT_TIMESTAMP()` auto-populates. |
| `_source_file` | VARCHAR | **Lineage tracking.** Populated via `METADATA$FILENAME` during COPY. Enables tracing any row back to its source CSV block file. Critical for data quality investigations. |

#### Why No Primary Key

**Decision:** No PRIMARY KEY constraint on RAW_METER_DATA.

**Justification:**
- **Duplicates are possible:** Source CSV blocks may overlap or be re-delivered. RAW layer should accept all rows.
- **Deduplication is Silver's job:** We'll use `QUALIFY ROW_NUMBER()` or `DISTINCT` when transforming to CLEAN_METER_DATA.
- **Performance:** PK enforcement adds overhead during high-velocity Snowpipe ingestion.

#### Why VARCHAR for All Business Columns

**Decision:** Use VARCHAR for `LCLid`, `tstp`, and `energy` instead of their "correct" types.

**Justification:**

| Scenario | What Happens with Typed Columns | What Happens with VARCHAR |
|----------|--------------------------------|---------------------------|
| Malformed timestamp: `2012-13-45 99:99:99` | COPY fails, row rejected | Row lands, flagged in Silver |
| Energy value: `Null` (string) | COPY fails (can't cast to FLOAT) | Row lands, handled in Silver |
| Unexpected LCLid format: `MAC-000001-A` | Works (still VARCHAR) | Works |
| Scientific notation: `1.5E-10` | May fail depending on format | Lands as string, parsed later |

**Bronze Principle:** "Land everything, filter nothing." Type casting failures should never block ingestion.

---

### 3.3 RAW_HOUSEHOLD_INFO

```sql
CREATE TABLE IF NOT EXISTS HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO (
    LCLid           VARCHAR,
    stdorToU        VARCHAR,
    Acorn           VARCHAR,
    Acorn_grouped   VARCHAR,
    file            VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR
);
```

#### Column Decisions

| Column | Justification |
|--------|---------------|
| `LCLid` | Meter identifier. VARCHAR to match source format exactly. |
| `stdorToU` | Tariff type: `Std` or `ToU`. VARCHAR because source contains string abbreviations. |
| `Acorn` | ACORN classification code. VARCHAR because it's alphanumeric (e.g., `ACORN-A`). |
| `Acorn_grouped` | Grouped classification. VARCHAR for same reason. |
| `file` | Source file reference from the original dataset. This is a **business column** from the CSV, not our metadata. |
| `_loaded_at`, `_source_file` | Metadata columns (same rationale as RAW_METER_DATA). |

#### Why Both `file` and `_source_file`

**Clarification:**
- `file`: Column from the source CSV indicating which original data file the household appeared in (business data).
- `_source_file`: Our metadata column tracking which CSV we loaded into Snowflake (operational data).

These serve different purposes and both are retained.

---

### 3.4 RAW_WEATHER_DATA

```sql
CREATE TABLE IF NOT EXISTS HELIOS_RAW_DB.GRID.RAW_WEATHER_DATA (
    time            VARCHAR,
    temperature     VARCHAR,
    humidity        VARCHAR,
    visibility      VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR
);
```

#### Column Decisions

| Column | Justification |
|--------|---------------|
| `time` | Timestamp from Dark Sky API. VARCHAR to handle any format variations. |
| `temperature` | Temperature reading. VARCHAR because source may include units or nulls. |
| `humidity` | Humidity percentage. VARCHAR for same reason. |
| `visibility` | Visibility distance. VARCHAR to handle unit variations (km vs miles). |

#### Why Only 4 Weather Columns (Not All 12 from Source)

**Decision:** Land only `time`, `temperature`, `humidity`, `visibility` from the weather CSV.

**Justification:**
- **Scope reduction:** Original Dark Sky CSV has 12+ columns. Only 4 are relevant for energy consumption correlation.
- **Columns excluded:** `windBearing`, `dewPoint`, `pressure`, `apparentTemperature`, `windSpeed`, `precipType`, `icon`, `summary`.
- **Rationale:** Energy consumption correlates primarily with temperature (heating/cooling) and humidity (HVAC load). Visibility was retained for potential anomaly detection (fog events).
- **Extensibility:** If needed later, we can add columns to RAW and re-ingest.

---

## 4. Silver Layer: HELIOS_TRANSFORM_DB.GRID

### 4.1 Design Philosophy

**Principle:** Clean, type-cast, rename, and standardize. This layer enforces data quality contracts that Gold layer consumers can rely on.

---

### 4.2 CLEAN_METER_DATA

```sql
CREATE TABLE IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA (
    household_id        VARCHAR NOT NULL,
    reading_timestamp   TIMESTAMP_NTZ NOT NULL,
    energy_kwh          FLOAT
);
```

#### Column Decisions

| Column | Type | Transformation from RAW | Justification |
|--------|------|------------------------|---------------|
| `household_id` | VARCHAR NOT NULL | `LCLid` | **Renamed for clarity.** `household_id` is more descriptive than `LCLid`. NOT NULL enforces that we don't load rows without identifiers. |
| `reading_timestamp` | TIMESTAMP_NTZ NOT NULL | `TRY_TO_TIMESTAMP_NTZ(tstp)` | **Type casting with safety.** `TRY_TO_*` returns NULL for unparseable values instead of failing. NOT NULL ensures only valid timestamps proceed. |
| `energy_kwh` | FLOAT | `TRY_TO_DOUBLE(energy)` | **Nullable intentionally.** Some readings may be missing or invalid. We allow NULL here and filter in Gold if needed. FLOAT handles decimal precision for kWh values. |

#### Why TIMESTAMP_NTZ (Not TIMESTAMP_LTZ or TIMESTAMP_TZ)

**Decision:** Use `TIMESTAMP_NTZ` (No Time Zone) for all timestamps.

**Justification:**

| Type | Behavior | Why Not Used |
|------|----------|--------------|
| TIMESTAMP_LTZ | Stores in UTC, displays in session TZ | Requires consistent session TZ across all users. Adds complexity. |
| TIMESTAMP_TZ | Stores timestamp + timezone | Source data doesn't include TZ info. Would require assumption. |
| TIMESTAMP_NTZ | Stores exactly as provided | **Best fit.** London Smart Meter data is in UK local time. NTZ preserves this without TZ conversion confusion. |

**Assumption:** All timestamps represent UK local time (GMT/BST). Documented for consumers.

#### Why No Primary Key

**Decision:** No PK on CLEAN_METER_DATA.

**Justification:**
- **Duplicates possible:** A household may have multiple readings at the same timestamp in edge cases (re-reads, corrections).
- **Performance:** PK enforcement on high-volume table adds insert overhead.
- **Deduplication strategy:** Handle in Gold layer with `QUALIFY ROW_NUMBER() OVER (PARTITION BY household_id, reading_timestamp ORDER BY _loaded_at DESC) = 1` if needed.

---

### 4.3 CLEAN_HOUSEHOLD_INFO

```sql
CREATE TABLE IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO (
    household_id        VARCHAR NOT NULL,
    tariff_type         VARCHAR,
    acorn_group         VARCHAR,
    CONSTRAINT pk_clean_household PRIMARY KEY (household_id)
);
```

#### Column Decisions

| Column | Transformation | Justification |
|--------|---------------|---------------|
| `household_id` | `LCLid` | Renamed for consistency with CLEAN_METER_DATA. |
| `tariff_type` | `CASE stdorToU WHEN 'Std' THEN 'Standard' WHEN 'ToU' THEN 'Time-of-Use' ELSE stdorToU END` | **Expanded abbreviations** for readability in BI tools. |
| `acorn_group` | `Acorn_grouped` | Renamed. The grouped classification is more useful than granular `Acorn` for analytics. |

#### Why PRIMARY KEY Here (But Not on Meter Data)

**Decision:** Add PK constraint on `household_id`.

**Justification:**
- **Dimension table:** Household info is a slowly-changing dimension. Each household should appear exactly once.
- **Row count:** ~5,500 households. PK overhead is negligible.
- **FK enforcement:** Gold layer's DIM_HOUSEHOLD will reference this. PK ensures referential integrity is possible.
- **Deduplication signal:** If COPY attempts to insert duplicate `household_id`, it fails—alerting us to data quality issues upstream.

---

### 4.4 CLEAN_WEATHER_DATA

```sql
CREATE TABLE IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID.CLEAN_WEATHER_DATA (
    weather_timestamp   TIMESTAMP_NTZ NOT NULL,
    temperature_c       FLOAT,
    humidity            FLOAT,
    visibility          FLOAT,
    CONSTRAINT pk_clean_weather PRIMARY KEY (weather_timestamp)
);
```

#### Column Decisions

| Column | Transformation | Justification |
|--------|---------------|---------------|
| `weather_timestamp` | `TRY_TO_TIMESTAMP_NTZ(time)` | Renamed from `time` (reserved word in some SQL dialects). |
| `temperature_c` | `TRY_TO_DOUBLE(temperature)` | Renamed to include unit suffix `_c` for Celsius. Prevents ambiguity. |
| `humidity` | `TRY_TO_DOUBLE(humidity)` | Retained name. Assumed 0-1 scale (proportion, not percentage). |
| `visibility` | `TRY_TO_DOUBLE(visibility)` | Retained name. Unit assumed from source (km). |

#### Why PRIMARY KEY on weather_timestamp

**Decision:** PK on timestamp.

**Justification:**
- **Hourly grain:** Weather data is one observation per hour. Timestamp is the natural key.
- **Join target:** Gold layer joins on this timestamp. PK ensures no duplicates that would cause row multiplication.
- **Small table:** ~17,500 rows (2 years × 8,760 hours). PK overhead is trivial.

---

## 5. Gold Layer: HELIOS_ANALYTICS_DB.GRID

### 5.1 Design Philosophy

**Principle:** Star schema optimized for BI consumption. Dimension tables for slicing, fact table for measures. Views for pre-aggregated dashboards.

---

### 5.2 DIM_HOUSEHOLD

```sql
CREATE TABLE IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD (
    household_id        VARCHAR NOT NULL,
    tariff_type         VARCHAR,
    acorn_group         VARCHAR,
    CONSTRAINT pk_dim_household PRIMARY KEY (household_id)
);
```

#### Design Decisions

| Decision | Justification |
|----------|---------------|
| **Same structure as CLEAN_HOUSEHOLD_INFO** | Intentional simplicity. No additional derived columns needed at this stage. Gold layer is a copy with PK for FK relationships. |
| **No surrogate key** | `household_id` (`LCLid`) is already a stable, unique business key. Surrogate integers add complexity without benefit here. |
| **No SCD Type 2 columns** | Household attributes (tariff, ACORN) are static in this dataset. No `effective_from`, `effective_to`, or `is_current` needed. |

#### Why Not Just Reference CLEAN_HOUSEHOLD_INFO Directly?

**Decision:** Copy data to DIM_HOUSEHOLD instead of creating a view.

**Justification:**
- **Layer isolation:** ANALYTICS_DB should not depend on TRANSFORM_DB at query time. If TRANSFORM_DB is unavailable (maintenance, permissions), Gold layer still works.
- **Performance:** Materialized dimension tables enable clustering and statistics that views don't have.
- **Governance:** Masking policies in Phase 8 will apply to ANALYTICS_DB. Applying them to a view pointing to TRANSFORM_DB complicates policy management.

---

### 5.3 DIM_WEATHER

```sql
CREATE TABLE IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER (
    weather_timestamp   TIMESTAMP_NTZ NOT NULL,
    temperature_c       FLOAT,
    humidity            FLOAT,
    visibility          FLOAT,
    CONSTRAINT pk_dim_weather PRIMARY KEY (weather_timestamp)
);
```

#### Design Decisions

| Decision | Justification |
|----------|---------------|
| **Timestamp as PK** | Natural key for hourly weather. No surrogate needed. |
| **Hourly grain preserved** | Weather observations are hourly. We don't roll up to daily—joins to fact data need hourly precision. |
| **No derived columns (e.g., temp_band)** | Keeping dimensions lean. Derived attributes (`Cold`, `Mild`, `Warm`) can be computed in views or BI tools. |

---

### 5.4 FACT_ENERGY_CONSUMPTION

```sql
CREATE TABLE IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION (
    household_id        VARCHAR NOT NULL,
    reading_timestamp   TIMESTAMP_NTZ NOT NULL,
    energy_kwh          FLOAT NOT NULL,
    CONSTRAINT pk_fact_energy PRIMARY KEY (household_id, reading_timestamp),
    CONSTRAINT fk_household FOREIGN KEY (household_id) 
        REFERENCES HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD(household_id)
);
```

#### Column Decisions

| Column | Justification |
|--------|---------------|
| `household_id` | FK to DIM_HOUSEHOLD. Enables slicing by tariff type and ACORN group. |
| `reading_timestamp` | Degenerate dimension. Stored in fact table rather than separate DIM_TIME because time-series queries need direct timestamp access. |
| `energy_kwh` | The measure. NOT NULL because a consumption fact without a value is meaningless. |

#### Why Composite Primary Key (household_id, reading_timestamp)

**Decision:** PK on both columns together.

**Justification:**
- **Business rule:** Each household has exactly one reading per timestamp (half-hourly).
- **Uniqueness:** Neither column alone is unique. A household has many readings; a timestamp has many households.
- **Query performance:** Snowflake uses PK for micro-partition pruning. Composite PK enables efficient queries like `WHERE household_id = 'X' AND reading_timestamp BETWEEN ...`.

#### Why FK to DIM_HOUSEHOLD But NOT to DIM_WEATHER

**Decision:** Create FK constraint for household, not for weather.

**FK to DIM_HOUSEHOLD:**
```sql
CONSTRAINT fk_household FOREIGN KEY (household_id) 
    REFERENCES HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD(household_id)
```

**Justification:**
- **Grain alignment:** Every `household_id` in the fact table must exist in DIM_HOUSEHOLD. 1:1 match on the key.
- **Data integrity:** FK prevents orphan facts—consumption records for households we have no info about.

**NO FK to DIM_WEATHER:**

**Justification:**

| Issue | Explanation |
|-------|-------------|
| **Grain mismatch** | Fact table: half-hourly (00:00, 00:30, 01:00, 01:30...). DIM_WEATHER: hourly (00:00, 01:00...). FK on `reading_timestamp` → `weather_timestamp` would fail for :30 readings. |
| **Logical join instead** | Weather is joined via `DATE_TRUNC('HOUR', reading_timestamp) = weather_timestamp` in views. This is a logical relationship, not a physical FK. |
| **Performance** | FK checks on high-volume fact table inserts add latency. Since the join is handled in views, FK adds overhead without benefit. |

---

### 5.5 V_DASHBOARD_FEED

```sql
CREATE OR REPLACE VIEW HELIOS_ANALYTICS_DB.GRID.V_DASHBOARD_FEED AS
SELECT
    DATE_TRUNC('DAY', f.reading_timestamp) AS consumption_date,
    h.tariff_type,
    h.acorn_group,
    COUNT(DISTINCT f.household_id) AS active_households,
    COUNT(*) AS reading_count,
    SUM(f.energy_kwh) AS total_kwh,
    AVG(f.energy_kwh) AS avg_kwh_per_reading,
    MIN(f.energy_kwh) AS min_kwh,
    MAX(f.energy_kwh) AS max_kwh,
    AVG(w.temperature_c) AS avg_temperature_c,
    AVG(w.humidity) AS avg_humidity
FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION f
JOIN HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD h 
    ON f.household_id = h.household_id
LEFT JOIN HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER w 
    ON DATE_TRUNC('HOUR', f.reading_timestamp) = w.weather_timestamp
GROUP BY 1, 2, 3;
```

#### Design Decisions

| Decision | Justification |
|----------|---------------|
| **VIEW not TABLE** | Aggregations are computed at query time. Ensures data is always fresh without ETL to maintain a separate aggregate table. |
| **Daily grain** | Dashboard shows daily trends. Half-hourly detail is too granular for overview dashboards. |
| **GROUP BY tariff_type, acorn_group** | Enables filtering in Streamlit: "Show me Standard tariff households only." |

#### JOIN Strategy

**INNER JOIN to DIM_HOUSEHOLD:**
```sql
JOIN HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD h ON f.household_id = h.household_id
```
- **Why INNER:** Every fact row must have a valid household (FK enforced). INNER JOIN is semantically correct and performs better than LEFT JOIN.

**LEFT JOIN to DIM_WEATHER:**
```sql
LEFT JOIN HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER w 
    ON DATE_TRUNC('HOUR', f.reading_timestamp) = w.weather_timestamp
```
- **Why LEFT:** Weather data may have gaps. A missing weather observation shouldn't exclude consumption facts. LEFT JOIN returns NULL for weather columns when no match exists.

#### DATE_TRUNC Explanation

**Usage:** `DATE_TRUNC('HOUR', f.reading_timestamp) = w.weather_timestamp`

**Justification:**

| Fact Timestamp | After DATE_TRUNC('HOUR') | Matches Weather |
|----------------|--------------------------|-----------------|
| 2013-01-15 08:00:00 | 2013-01-15 08:00:00 | ✅ Yes |
| 2013-01-15 08:30:00 | 2013-01-15 08:00:00 | ✅ Yes (same hour) |
| 2013-01-15 09:00:00 | 2013-01-15 09:00:00 | ✅ Yes |

- **Why necessary:** Meter readings at 08:30 have no direct weather match (weather is hourly). `DATE_TRUNC` maps the :30 reading to its containing hour.
- **Assumption:** Weather conditions at 08:00 apply to the entire 08:00-08:59 window. Reasonable for hourly weather data.

---

## 6. Platinum Layer: HELIOS_AI_READY_DB.GRID

### 6.1 Design Philosophy

**Principle:** Provide ML-ready datasets with pre-computed features and store model outputs. Optimized for Cortex ML functions, not human analysis.

---

### 6.2 V_TRAINING_FEATURES

```sql
CREATE OR REPLACE VIEW HELIOS_AI_READY_DB.GRID.V_TRAINING_FEATURES AS
SELECT
    f.household_id,
    DATE_TRUNC('HOUR', f.reading_timestamp) AS feature_timestamp,
    SUM(f.energy_kwh) AS energy_kwh_hourly,
    COUNT(*) AS readings_in_hour,
    AVG(w.temperature_c) AS temperature_c,
    AVG(w.humidity) AS humidity,
    DAYOFWEEK(DATE_TRUNC('HOUR', f.reading_timestamp)) AS day_of_week,
    HOUR(DATE_TRUNC('HOUR', f.reading_timestamp)) AS hour_of_day,
    MONTH(DATE_TRUNC('HOUR', f.reading_timestamp)) AS month_num,
    CASE WHEN DAYOFWEEK(DATE_TRUNC('HOUR', f.reading_timestamp)) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend
FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION f
LEFT JOIN HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER w 
    ON DATE_TRUNC('HOUR', f.reading_timestamp) = w.weather_timestamp
GROUP BY 
    f.household_id,
    DATE_TRUNC('HOUR', f.reading_timestamp);
```

#### Design Decisions

| Decision | Justification |
|----------|---------------|
| **VIEW not TABLE** | Features are derived from Gold layer. View ensures features always reflect latest fact data without separate ETL. |
| **Hourly grain (not half-hourly)** | Aggregating 30-min to 1-hour reduces noise and aligns with weather data grain. ML models perform better with aligned feature/target granularity. |
| **Cross-database reference** | View in AI_READY_DB queries ANALYTICS_DB. This is intentional—Platinum layer builds on Gold, not Raw/Silver. |

#### Feature Engineering Justification

| Feature | Calculation | ML Purpose |
|---------|-------------|------------|
| `energy_kwh_hourly` | `SUM(energy_kwh)` | **Target variable** for forecasting. Hourly consumption is what we predict. |
| `readings_in_hour` | `COUNT(*)` | **Data quality feature.** Should be 2 (two 30-min readings). Values < 2 indicate missing data. |
| `temperature_c` | `AVG(w.temperature_c)` | **Weather feature.** Temperature drives heating/cooling load. Strongest predictor of energy use. |
| `humidity` | `AVG(w.humidity)` | **Weather feature.** High humidity increases HVAC load (dehumidification). |
| `day_of_week` | `DAYOFWEEK()` | **Calendar feature.** Consumption patterns differ weekday vs. weekend. Snowflake: 0=Sunday, 6=Saturday. |
| `hour_of_day` | `HOUR()` | **Calendar feature.** Consumption peaks at certain hours (morning, evening). |
| `month_num` | `MONTH()` | **Seasonality feature.** Winter months have higher heating load in UK. |
| `is_weekend` | `CASE WHEN DAYOFWEEK IN (0,6)` | **Binary feature.** Simplifies model input. TRUE for Saturday/Sunday. |

#### Why GROUP BY Only household_id and Truncated Timestamp

```sql
GROUP BY 
    f.household_id,
    DATE_TRUNC('HOUR', f.reading_timestamp);
```

**Justification:**
- **Minimal GROUP BY:** Only the dimensions that define the grain are in GROUP BY. Other columns (day_of_week, hour_of_day, etc.) are deterministic functions of the timestamp—no need to group by them.
- **Snowflake behavior:** Snowflake allows selecting expressions derived from GROUP BY columns without including them in GROUP BY. `HOUR(DATE_TRUNC('HOUR', ts))` is deterministic given `DATE_TRUNC('HOUR', ts)`.

---

### 6.3 CORTEX_LOAD_FORECAST

```sql
CREATE TABLE IF NOT EXISTS HELIOS_AI_READY_DB.GRID.CORTEX_LOAD_FORECAST (
    household_id        VARCHAR,
    forecast_timestamp  TIMESTAMP_NTZ,
    predicted_kwh       FLOAT,
    lower_bound         FLOAT,
    upper_bound         FLOAT,
    model_version       VARCHAR DEFAULT 'v1',
    generated_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

#### Column Decisions

| Column | Justification |
|--------|---------------|
| `household_id` | Forecasts are per-household. Enables filtering predictions for specific meters. |
| `forecast_timestamp` | The future timestamp being predicted. E.g., "What is consumption at 2024-01-15 14:00?" |
| `predicted_kwh` | Point forecast. The model's best estimate of hourly consumption. |
| `lower_bound` | Lower end of prediction interval (e.g., 90% CI). Cortex FORECAST outputs this. |
| `upper_bound` | Upper end of prediction interval. Essential for uncertainty quantification. |
| `model_version` | Tracks which model produced the forecast. Enables A/B testing and rollback. |
| `generated_at` | When the forecast was created. Identifies stale predictions. |

#### Why TABLE Not VIEW

**Decision:** Materialize forecasts as a table.

**Justification:**
- **Cortex FORECAST output:** `SNOWFLAKE.ML.FORECAST` returns results that must be stored somewhere. You can't create a view over a function that generates predictions.
- **Historical tracking:** Table preserves past forecasts for accuracy analysis. "How well did we predict last week?"
- **Performance:** Dashboards reading forecasts don't need to re-run ML inference on every query.

#### Why No Primary Key

**Decision:** No PK on forecast table.

**Justification:**
- **Multiple forecasts per timestamp:** We may generate forecasts daily, creating multiple predictions for the same future timestamp. All are valid historical records.
- **Append-only pattern:** New forecasts are inserted, not updated. PK would prevent this.
- **Query pattern:** Consumers query `WHERE generated_at = (SELECT MAX(generated_at))` to get latest forecasts.

---

## 7. Cross-Cutting Design Decisions

### 7.1 Metadata Columns (_loaded_at, _source_file)

**Decision:** Add `_loaded_at` and `_source_file` to all RAW tables.

**Justification:**

| Column | Purpose |
|--------|---------|
| `_loaded_at` | **Debugging:** Identify when data arrived. Detect Snowpipe latency issues. |
| `_source_file` | **Lineage:** Trace any row back to its source file. Essential for data quality investigations. |

**Why underscore prefix:** Convention indicating these are system/metadata columns, not business data. Clearly distinguishes from source columns like `file` in RAW_HOUSEHOLD_INFO.

**Why not in Silver/Gold:** By the time data reaches Silver, lineage is established. Adding metadata columns to every layer creates redundancy and storage overhead.

---

### 7.2 NOT NULL Constraints

**Pattern:**
- RAW: No NOT NULL (accept everything)
- Silver: NOT NULL on identifiers and timestamps
- Gold: NOT NULL on keys and measures

**Justification:**
- **RAW flexibility:** Source data may have blanks. NOT NULL would reject rows we need to investigate.
- **Silver data contract:** After cleaning, identifiers and timestamps must be valid. NOT NULL enforces this.
- **Gold integrity:** Fact measures must exist. A consumption fact with NULL energy_kwh is meaningless.

---

### 7.3 FLOAT vs NUMBER for Numeric Columns

**Decision:** Use FLOAT for energy and weather measurements.

**Justification:**

| Type | Precision | Use Case |
|------|-----------|----------|
| NUMBER(38,2) | Exact decimal | Financial amounts (currency) |
| FLOAT | ~15 significant digits | Scientific measurements |

- **Energy readings:** Measured in kWh with variable precision (0.234, 1.5, 12.789). FLOAT handles this naturally.
- **Temperature:** Continuous measurement. FLOAT is appropriate.
- **No currency:** We're not storing prices. Exact decimal precision isn't required.

---

### 7.4 No DIM_DATE Table

**Decision:** Do not create a date dimension table.

**Justification:**
- **Snowflake functions:** `DAYOFWEEK()`, `MONTH()`, `YEAR()`, `DATE_TRUNC()` provide all needed calendar attributes at query time.
- **No custom attributes:** We don't need UK bank holidays or fiscal periods (yet). Native functions suffice.
- **Lean architecture:** One less table to maintain and populate.

**When to add DIM_DATE:** If we later need custom attributes (is_uk_holiday, is_school_holiday, fiscal_quarter), we'll create it.

---

## 8. Summary: Decision Matrix

| Aspect | Decision | Primary Justification |
|--------|----------|----------------------|
| 4 databases | Separate by medallion layer | Access control, cost attribution |
| Single GRID schema | One schema per database | Simplicity, lean grants |
| VARCHAR in RAW | All business columns as strings | Prevent COPY failures |
| TIMESTAMP_NTZ | No timezone type | Source is UK local time, no TZ info |
| PK on dimensions | Yes | Enable FK from facts |
| PK on CLEAN_METER_DATA | No | Allow duplicates, dedup in Gold |
| FK fact → DIM_HOUSEHOLD | Yes | Enforce referential integrity |
| FK fact → DIM_WEATHER | No | Grain mismatch (30min vs 1hr) |
| DATE_TRUNC in joins | Map 30-min to hourly weather | Logical relationship, not physical |
| View for features | V_TRAINING_FEATURES | Always fresh, no ETL needed |
| Table for forecasts | CORTEX_LOAD_FORECAST | Store ML output, historical tracking |
| Metadata columns | _loaded_at, _source_file in RAW only | Lineage without redundancy |

---

*Document Version: 1.0*
*Last Updated: 2026-02-25*
*Author: Cortex Code (CoCo)*
