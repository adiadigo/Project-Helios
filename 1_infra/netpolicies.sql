-- =============================================================================
-- NETWORK POLICIES - Project Helios
-- Role: ACCOUNTADMIN (required for network policies)
-- Warehouse: COMPUTE_WH (admin operations)
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- Create a database for infrastructure objects (SNOWFLAKE db is read-only)
CREATE DATABASE IF NOT EXISTS INFRA_DB;
CREATE SCHEMA IF NOT EXISTS INFRA_DB.SECURITY;
USE DATABASE INFRA_DB;
USE SCHEMA SECURITY;

-- 1. Create a Rule for your specific IP
CREATE OR REPLACE NETWORK RULE INFRA_DB.SECURITY.HELIOS_USER_IP_RULE
  TYPE = IPV4
  MODE = INGRESS
  VALUE_LIST = ('47.11.44.0/22');

-- 2. Create the Policy referencing the rule
CREATE OR REPLACE NETWORK POLICY HELIOS_NETWORK_POLICY
  ALLOWED_NETWORK_RULE_LIST = ('INFRA_DB.SECURITY.HELIOS_USER_IP_RULE')
  COMMENT = 'Project Helios: Primary access policy';

-- 3. ACTIVATE with caution
-- To test safely, apply it to your USER first, not the whole ACCOUNT
ALTER USER ADIWORKSATARIS SET NETWORK_POLICY = HELIOS_NETWORK_POLICY;


ALTER USER ADIWORKSATARIS UNSET NETWORK_POLICY;
-- Doing this to protect my ass from locking itself out