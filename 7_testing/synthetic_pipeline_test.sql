-- ============================================================================
-- PROJECT HELIOS: SYNTHETIC DATA PIPELINE TEST
-- Inserts 50 rows of test data and validates end-to-end flow
-- ============================================================================

-- ============================================================================
-- STEP 1: INSERT SYNTHETIC DATA INTO RAW TABLES
-- ============================================================================

-- RAW_HOUSEHOLD_INFO (10 households)
INSERT INTO HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO (LCLid, stdorToU, Acorn, Acorn_grouped, file, _source_file)
SELECT 
    'MAC00000' || seq4() AS LCLid,
    CASE WHEN seq4() % 2 = 0 THEN 'Std' ELSE 'ToU' END AS stdorToU,
    'ACORN-' || CHR(65 + MOD(seq4(), 6)) AS Acorn,
    CASE MOD(seq4(), 3) 
        WHEN 0 THEN 'Affluent'
        WHEN 1 THEN 'Comfortable' 
        ELSE 'Adversity' 
    END AS Acorn_grouped,
    'block_0.csv' AS file,
    'synthetic_test.csv' AS _source_file
FROM TABLE(GENERATOR(ROWCOUNT => 10));

-- RAW_WEATHER_DATA (50 hourly observations - ~2 days)
INSERT INTO HELIOS_RAW_DB.GRID.RAW_WEATHER_DATA (time, temperature, humidity, visibility, _source_file)
SELECT 
    TO_VARCHAR(DATEADD('HOUR', seq4(), '2013-01-15 00:00:00'::TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS') AS time,
    TO_VARCHAR(ROUND(5 + (RANDOM() / 1e18) * 10, 1)) AS temperature,
    TO_VARCHAR(ROUND(0.4 + (RANDOM() / 1e18) * 0.5, 2)) AS humidity,
    TO_VARCHAR(ROUND(5 + (RANDOM() / 1e18) * 10, 1)) AS visibility,
    'synthetic_test.csv' AS _source_file
FROM TABLE(GENERATOR(ROWCOUNT => 50));

-- RAW_METER_DATA (50 readings - 10 households x 5 readings each)
INSERT INTO HELIOS_RAW_DB.GRID.RAW_METER_DATA (LCLid, tstp, energy, _source_file)
SELECT 
    'MAC00000' || MOD(seq4(), 10) AS LCLid,
    TO_VARCHAR(DATEADD('MINUTE', FLOOR(seq4() / 10) * 30, '2013-01-15 00:00:00'::TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS') AS tstp,
    TO_VARCHAR(ROUND(0.1 + (RANDOM() / 1e18) * 2, 3)) AS energy,
    'synthetic_test.csv' AS _source_file
FROM TABLE(GENERATOR(ROWCOUNT => 50));

-- ============================================================================
-- STEP 2: TRANSFORM RAW -> CLEAN (Silver Layer)
-- ============================================================================

-- CLEAN_HOUSEHOLD_INFO
INSERT INTO HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO (household_id, tariff_type, acorn_group)
SELECT DISTINCT
    LCLid AS household_id,
    CASE stdorToU 
        WHEN 'Std' THEN 'Standard' 
        WHEN 'ToU' THEN 'Time-of-Use' 
        ELSE stdorToU 
    END AS tariff_type,
    Acorn_grouped AS acorn_group
FROM HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO
WHERE LCLid IS NOT NULL;

-- CLEAN_WEATHER_DATA
INSERT INTO HELIOS_TRANSFORM_DB.GRID.CLEAN_WEATHER_DATA (weather_timestamp, temperature_c, humidity, visibility)
SELECT 
    TRY_TO_TIMESTAMP_NTZ(time) AS weather_timestamp,
    TRY_TO_DOUBLE(temperature) AS temperature_c,
    TRY_TO_DOUBLE(humidity) AS humidity,
    TRY_TO_DOUBLE(visibility) AS visibility
FROM HELIOS_RAW_DB.GRID.RAW_WEATHER_DATA
WHERE TRY_TO_TIMESTAMP_NTZ(time) IS NOT NULL;

-- CLEAN_METER_DATA
INSERT INTO HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA (household_id, reading_timestamp, energy_kwh)
SELECT 
    LCLid AS household_id,
    TRY_TO_TIMESTAMP_NTZ(tstp) AS reading_timestamp,
    TRY_TO_DOUBLE(energy) AS energy_kwh
FROM HELIOS_RAW_DB.GRID.RAW_METER_DATA
WHERE LCLid IS NOT NULL 
  AND TRY_TO_TIMESTAMP_NTZ(tstp) IS NOT NULL;

-- ============================================================================
-- STEP 3: LOAD CLEAN -> ANALYTICS (Gold Layer)
-- ============================================================================

-- DIM_HOUSEHOLD
INSERT INTO HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD (household_id, tariff_type, acorn_group)
SELECT household_id, tariff_type, acorn_group
FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO;

-- DIM_WEATHER
INSERT INTO HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER (weather_timestamp, temperature_c, humidity, visibility)
SELECT weather_timestamp, temperature_c, humidity, visibility
FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_WEATHER_DATA;

-- FACT_ENERGY_CONSUMPTION
INSERT INTO HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION (household_id, reading_timestamp, energy_kwh)
SELECT household_id, reading_timestamp, energy_kwh
FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA;

-- ============================================================================
-- STEP 4: VALIDATE ROW COUNTS
-- ============================================================================

SELECT 'RAW_HOUSEHOLD_INFO' AS table_name, COUNT(*) AS row_count FROM HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO
UNION ALL
SELECT 'RAW_WEATHER_DATA', COUNT(*) FROM HELIOS_RAW_DB.GRID.RAW_WEATHER_DATA
UNION ALL
SELECT 'RAW_METER_DATA', COUNT(*) FROM HELIOS_RAW_DB.GRID.RAW_METER_DATA
UNION ALL
SELECT 'CLEAN_HOUSEHOLD_INFO', COUNT(*) FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO
UNION ALL
SELECT 'CLEAN_WEATHER_DATA', COUNT(*) FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_WEATHER_DATA
UNION ALL
SELECT 'CLEAN_METER_DATA', COUNT(*) FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA
UNION ALL
SELECT 'DIM_HOUSEHOLD', COUNT(*) FROM HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD
UNION ALL
SELECT 'DIM_WEATHER', COUNT(*) FROM HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER
UNION ALL
SELECT 'FACT_ENERGY_CONSUMPTION', COUNT(*) FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION
ORDER BY table_name;

-- ============================================================================
-- STEP 5: TEST GOLD LAYER VIEW
-- ============================================================================

SELECT * FROM HELIOS_ANALYTICS_DB.GRID.V_DASHBOARD_FEED;

-- ============================================================================
-- STEP 6: TEST AI-READY LAYER VIEW
-- ============================================================================

SELECT * FROM HELIOS_AI_READY_DB.GRID.V_TRAINING_FEATURES LIMIT 10;

-- ============================================================================
-- STEP 7: CLEANUP (Run after validation if needed)
-- ============================================================================
/*
DELETE FROM HELIOS_AI_READY_DB.GRID.CORTEX_LOAD_FORECAST WHERE model_version = 'v1';
DELETE FROM HELIOS_ANALYTICS_DB.GRID.FACT_ENERGY_CONSUMPTION;
DELETE FROM HELIOS_ANALYTICS_DB.GRID.DIM_WEATHER;
DELETE FROM HELIOS_ANALYTICS_DB.GRID.DIM_HOUSEHOLD;
DELETE FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_METER_DATA;
DELETE FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_WEATHER_DATA;
DELETE FROM HELIOS_TRANSFORM_DB.GRID.CLEAN_HOUSEHOLD_INFO;
DELETE FROM HELIOS_RAW_DB.GRID.RAW_METER_DATA WHERE _source_file = 'synthetic_test.csv';
DELETE FROM HELIOS_RAW_DB.GRID.RAW_WEATHER_DATA WHERE _source_file = 'synthetic_test.csv';
DELETE FROM HELIOS_RAW_DB.GRID.RAW_HOUSEHOLD_INFO WHERE _source_file = 'synthetic_test.csv';
*/
