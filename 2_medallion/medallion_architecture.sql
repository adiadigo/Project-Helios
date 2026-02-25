-- ============================================================================
-- PROJECT HELIOS: MEDALLION ARCHITECTURE (FINAL)
-- Single "GRID" schema per database
-- ============================================================================

-- ============================================================================
-- LAYER 1: BRONZE (RAW) - Land data as-is, all VARCHAR
-- ============================================================================

CREATE DATABASE IF NOT EXISTS HELIOS_RAW_DB;
CREATE SCHEMA IF NOT EXISTS HELIOS_RAW_DB.GRID;

CREATE TABLE IF NOT EXISTS HELIOS_RAW_DB.GRID.RAW_METER_DATA (
    LCLid           VARCHAR,
    tstp            VARCHAR,
    energy          VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR
);

CREATE TABLE IF NOT EXISTS HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO (
    LCLid           VARCHAR,
    stdorToU        VARCHAR,
    Acorn           VARCHAR,
    Acorn_grouped   VARCHAR,
    file            VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR
);

CREATE TABLE IF NOT EXISTS HELIOS_RAW_DB.GRID.RAW_WEATHER_DATA (
    time            VARCHAR,
    temperature     VARCHAR,
    humidity        VARCHAR,
    visibility      VARCHAR,
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR
);

-- ============================================================================
-- LAYER 2: SILVER (TRANSFORM) - Typed, cleaned, renamed
-- ============================================================================

CREATE DATABASE IF NOT EXISTS HELIOS_TRANSFORM_DB;
CREATE SCHEMA IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID;

CREATE TABLE IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA (
    household_id        VARCHAR NOT NULL,
    reading_timestamp   TIMESTAMP_NTZ NOT NULL,
    energy_kwh          FLOAT
);

CREATE TABLE IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO (
    household_id        VARCHAR NOT NULL,
    tariff_type         VARCHAR,
    acorn_group         VARCHAR,
    CONSTRAINT pk_clean_household PRIMARY KEY (household_id)
);

CREATE TABLE IF NOT EXISTS HELIOS_TRANSFORM_DB.GRID.CLEAN_WEATHER_DATA (
    weather_timestamp   TIMESTAMP_NTZ NOT NULL,
    temperature_c       FLOAT,
    humidity            FLOAT,
    visibility          FLOAT,
    CONSTRAINT pk_clean_weather PRIMARY KEY (weather_timestamp)
);

-- ============================================================================
-- LAYER 3: GOLD (ANALYTICS) - Star Schema
-- ============================================================================

CREATE DATABASE IF NOT EXISTS HELIOS_ANALYTICS_DB;
CREATE SCHEMA IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID;

CREATE TABLE IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD (
    household_id        VARCHAR NOT NULL,
    tariff_type         VARCHAR,
    acorn_group         VARCHAR,
    CONSTRAINT pk_dim_household PRIMARY KEY (household_id)
);

CREATE TABLE IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER (
    weather_timestamp   TIMESTAMP_NTZ NOT NULL,
    temperature_c       FLOAT,
    humidity            FLOAT,
    visibility          FLOAT,
    CONSTRAINT pk_dim_weather PRIMARY KEY (weather_timestamp)
);

CREATE TABLE IF NOT EXISTS HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION (
    household_id        VARCHAR NOT NULL,
    reading_timestamp   TIMESTAMP_NTZ NOT NULL,
    energy_kwh          FLOAT NOT NULL,
    CONSTRAINT pk_fact_energy PRIMARY KEY (household_id, reading_timestamp),
    CONSTRAINT fk_household FOREIGN KEY (household_id) 
        REFERENCES HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD(household_id)
);

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

-- ============================================================================
-- LAYER 4: PLATINUM (AI-READY) - ML Features & Forecasts
-- ============================================================================

CREATE DATABASE IF NOT EXISTS HELIOS_AI_READY_DB;
CREATE SCHEMA IF NOT EXISTS HELIOS_AI_READY_DB.GRID;

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

CREATE TABLE IF NOT EXISTS HELIOS_AI_READY_DB.GRID.CORTEX_LOAD_FORECAST (
    household_id        VARCHAR,
    forecast_timestamp  TIMESTAMP_NTZ,
    predicted_kwh       FLOAT,
    lower_bound         FLOAT,
    upper_bound         FLOAT,
    model_version       VARCHAR DEFAULT 'v1',
    generated_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
