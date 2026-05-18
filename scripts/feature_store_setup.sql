-- =====================================================================
-- Feature Store Setup - 2026 EY AI & Data Challenge
-- One-time setup: creates the database, schema, and feature tables used
-- by the TerraClimate and Landsat data-extraction notebooks.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS EY_AI_DATA_CHALLENGE;

CREATE SCHEMA IF NOT EXISTS EY_AI_DATA_CHALLENGE.FEATURE_STORE;

USE SCHEMA EY_AI_DATA_CHALLENGE.FEATURE_STORE;

-- ---------------------------------------------------------------------
-- TerraClimate features
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_TRAINING (
    LATITUDE     FLOAT,
    LONGITUDE    FLOAT,
    SAMPLE_DATE  STRING,
    PET          FLOAT
);

CREATE TABLE IF NOT EXISTS EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_VALIDATION (
    LATITUDE     FLOAT,
    LONGITUDE    FLOAT,
    SAMPLE_DATE  STRING,
    PET          FLOAT
);

-- ---------------------------------------------------------------------
-- Landsat features
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_TRAINING (
    LATITUDE     FLOAT,
    LONGITUDE    FLOAT,
    SAMPLE_DATE  STRING,
    NIR          FLOAT,
    GREEN        FLOAT,
    SWIR16       FLOAT,
    SWIR22       FLOAT,
    NDMI         FLOAT,
    MNDWI        FLOAT
);

CREATE TABLE IF NOT EXISTS EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_VALIDATION (
    LATITUDE     FLOAT,
    LONGITUDE    FLOAT,
    SAMPLE_DATE  STRING,
    NIR          FLOAT,
    GREEN        FLOAT,
    SWIR16       FLOAT,
    SWIR22       FLOAT,
    NDMI         FLOAT,
    MNDWI        FLOAT
);
