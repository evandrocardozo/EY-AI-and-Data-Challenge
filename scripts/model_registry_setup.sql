-- =====================================================================
-- Model Registry Setup - 2026 EY AI & Data Challenge
-- One-time setup: creates a dedicated schema to host the Snowflake ML
-- Model Registry. Run after scripts/feature_store_setup.sql.
--
-- The Snowflake ML Registry (snowflake.ml.registry.Registry) writes its
-- bookkeeping objects into the schema you point it at. We isolate it
-- from the FEATURE_STORE schema so feature data and model artifacts are
-- governed independently.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS EY_AI_DATA_CHALLENGE;

CREATE SCHEMA IF NOT EXISTS EY_AI_DATA_CHALLENGE.MODEL_REGISTRY
    COMMENT = 'Snowflake ML Model Registry for the 2026 EY AI & Data Challenge';

-- Sanity check
SHOW SCHEMAS IN DATABASE EY_AI_DATA_CHALLENGE;
