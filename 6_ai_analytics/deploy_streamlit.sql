-- =============================================================================
-- STREAMLIT DEPLOYMENT - Project Helios Dashboard
-- =============================================================================
-- Role: ACCOUNTADMIN (or role with CREATE STREAMLIT privilege)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE HELIOS_ANALYTICS_DB;
USE SCHEMA GRID;
USE WAREHOUSE COMPUTE_WH;

-- =============================================================================
-- OPTION 1: Create Streamlit from Stage (Recommended)
-- =============================================================================

-- Step 1: Create a stage for Streamlit files
CREATE OR REPLACE STAGE HELIOS_ANALYTICS_DB.GRID.STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE);

-- Step 2: Upload files to stage using Snowsight UI or SnowSQL:
-- PUT file:///path/to/helios_dashboard.py @HELIOS_ANALYTICS_DB.GRID.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT file:///path/to/environment.yml @HELIOS_ANALYTICS_DB.GRID.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Step 3: Create the Streamlit app
CREATE OR REPLACE STREAMLIT HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD
    ROOT_LOCATION = '@HELIOS_ANALYTICS_DB.GRID.STREAMLIT_STAGE'
    MAIN_FILE = 'helios_dashboard.py'
    QUERY_WAREHOUSE = COMPUTE_WH
    COMMENT = 'Project Helios: Energy Operations and Cost Management Dashboard';

-- =============================================================================
-- OPTION 2: Create from Workspace (If files are in Snowflake Workspace)
-- =============================================================================

-- If the files are already in your Snowflake Workspace, you can create
-- the Streamlit app directly from Snowsight:
-- 1. Navigate to Streamlit in Snowsight
-- 2. Click "+ Streamlit App"
-- 3. Select HELIOS_ANALYTICS_DB.GRID as the location
-- 4. Copy the code from helios_dashboard.py
-- 5. Save and run

-- =============================================================================
-- GRANT ACCESS TO ROLES
-- =============================================================================

-- Allow data stewards to view the dashboard
GRANT USAGE ON STREAMLIT HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD 
    TO ROLE HELIOS_DATA_STEWARD;

-- Allow analysts to view the dashboard
GRANT USAGE ON STREAMLIT HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD 
    TO ROLE HELIOS_ANALYST;

-- Allow BI consumers to view the dashboard
GRANT USAGE ON STREAMLIT HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD 
    TO ROLE HELIOS_BI_CONSUMER;

-- =============================================================================
-- VERIFY DEPLOYMENT
-- =============================================================================

SHOW STREAMLITS IN SCHEMA HELIOS_ANALYTICS_DB.GRID;

-- =============================================================================
-- ACCESS THE DASHBOARD
-- =============================================================================

-- Option A: Via Snowsight
-- Navigate to: Projects > Streamlit > HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD

-- Option B: Direct URL (format varies by account)
-- https://<account>.snowflakecomputing.com/streamlit/HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD

-- =============================================================================
-- CLEANUP (if needed)
-- =============================================================================

-- DROP STREAMLIT HELIOS_ANALYTICS_DB.GRID.HELIOS_DASHBOARD;
-- DROP STAGE HELIOS_ANALYTICS_DB.GRID.STREAMLIT_STAGE;
