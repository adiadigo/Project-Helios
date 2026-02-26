-- =============================================================================
-- DATABASE CONTEXT
-- =============================================================================

USE DATABASE HELIOS_ANALYTICS_DB;
USE SCHEMA PUBLIC;

-- =============================================================================
-- NOTIFICATION INTEGRATION (Required for alerts)
-- =============================================================================

CREATE OR REPLACE NOTIFICATION INTEGRATION helios_alerts
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('aditya.kulkarni@arisdata.ai');

-- =============================================================================
-- QUERY ALERTS
-- =============================================================================

-- Long-running query detection (> 5 minutes)
CREATE OR REPLACE ALERT HELIOS_ANALYTICS_DB.PUBLIC.HELIOS_LONG_QUERY_ALERT
  WAREHOUSE = TRANSFORM_WH
  SCHEDULE = '15 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(MINUTE, -20, CURRENT_TIMESTAMP())
      AND TOTAL_ELAPSED_TIME > 300000
      AND EXECUTION_STATUS = 'SUCCESS'
      AND WAREHOUSE_NAME IN ('INGEST_WH', 'TRANSFORM_WH', 'REPORTING_WH', 'CORTEX_WH')
    LIMIT 1
  ))
  THEN CALL SYSTEM$SEND_EMAIL(
    'helios_alerts',
    'aditya.kulkarni@arisdata.ai',
    'HELIOS: Long-Running Query Detected',
    'Query exceeded 5 minutes. Review query performance.'
  );

ALTER ALERT HELIOS_ANALYTICS_DB.PUBLIC.HELIOS_LONG_QUERY_ALERT RESUME;

-- Query failure rate spike (> 5% failures in last hour)
CREATE OR REPLACE ALERT HELIOS_ANALYTICS_DB.PUBLIC.HELIOS_QUERY_FAILURE_ALERT
  WAREHOUSE = TRANSFORM_WH
  SCHEDULE = '60 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM (
      SELECT 
        COUNT_IF(EXECUTION_STATUS = 'FAIL') AS failed,
        COUNT(*) AS total
      FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
      WHERE START_TIME >= DATEADD(HOUR, -1, CURRENT_TIMESTAMP())
        AND WAREHOUSE_NAME IN ('INGEST_WH', 'TRANSFORM_WH', 'REPORTING_WH', 'CORTEX_WH')
    )
    WHERE total > 10 AND (failed / total) > 0.05
  ))
  THEN CALL SYSTEM$SEND_EMAIL(
    'helios_alerts',
    'aditya.kulkarni@arisdata.ai',
    'HELIOS: High Query Failure Rate',
    'Query failure rate exceeded 5% in the last hour.'
  );

ALTER ALERT HELIOS_ANALYTICS_DB.PUBLIC.HELIOS_QUERY_FAILURE_ALERT RESUME;

-- High queue time alert (> 30 seconds average)
CREATE OR REPLACE ALERT HELIOS_ANALYTICS_DB.PUBLIC.HELIOS_QUEUE_TIME_ALERT
  WAREHOUSE = TRANSFORM_WH
  SCHEDULE = '15 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE START_TIME >= DATEADD(MINUTE, -15, CURRENT_TIMESTAMP())
      AND WAREHOUSE_NAME IN ('INGEST_WH', 'TRANSFORM_WH', 'REPORTING_WH', 'CORTEX_WH')
    GROUP BY WAREHOUSE_NAME
    HAVING AVG(QUEUED_OVERLOAD_TIME) > 30000
  ))
  THEN CALL SYSTEM$SEND_EMAIL(
    'helios_alerts',
    'aditya.kulkarni@arisdata.ai',
    'HELIOS: High Warehouse Queue Time',
    'Average queue time exceeded 30 seconds. Consider scaling warehouse.'
  );

ALTER ALERT HELIOS_ANALYTICS_DB.PUBLIC.HELIOS_QUEUE_TIME_ALERT RESUME;