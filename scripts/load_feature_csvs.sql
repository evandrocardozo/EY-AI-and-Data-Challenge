-- =====================================================================
-- Load Feature CSVs into the Feature Store - 2026 EY AI & Data Challenge
-- One-time bulk load of pre-extracted feature CSVs (in /files) into the
-- four FEATURE_STORE tables. Run after scripts/feature_store_setup.sql.
-- =====================================================================

USE DATABASE EY_AI_DATA_CHALLENGE;
USE SCHEMA EY_AI_DATA_CHALLENGE.FEATURE_STORE;

-- ---------------------------------------------------------------------
-- 1) Staging area + file format
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_STAGE;

CREATE OR REPLACE FILE FORMAT EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_FF
    TYPE = CSV
    PARSE_HEADER = FALSE
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null', 'NaN');

-- ---------------------------------------------------------------------
-- 2) Copy workspace CSVs into the stage
-- ---------------------------------------------------------------------
COPY FILES INTO @EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_STAGE
FROM 'snow://workspace/USER$.PUBLIC."EY-AI-and-Data-Challenge"/versions/live'
FILES = (
    'files/terraclimate_features_training.csv',
    'files/terraclimate_features_validation.csv',
    'files/landsat_features_training.csv',
    'files/landsat_features_validation.csv'
);

-- ---------------------------------------------------------------------
-- 3) Truncate target tables (idempotent reload)
-- ---------------------------------------------------------------------
TRUNCATE TABLE EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_TRAINING;
TRUNCATE TABLE EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_VALIDATION;
TRUNCATE TABLE EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_TRAINING;
TRUNCATE TABLE EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_VALIDATION;

-- ---------------------------------------------------------------------
-- 4) Load TerraClimate features
--    CSV cols: Latitude, Longitude, Sample Date, pet
--    Table cols: LATITUDE, LONGITUDE, SAMPLE_DATE, PET
-- ---------------------------------------------------------------------
COPY INTO EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_TRAINING
    (LATITUDE, LONGITUDE, SAMPLE_DATE, PET)
FROM @EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_STAGE/files/terraclimate_features_training.csv
FILE_FORMAT = (FORMAT_NAME = EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_FF)
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_VALIDATION
    (LATITUDE, LONGITUDE, SAMPLE_DATE, PET)
FROM @EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_STAGE/files/terraclimate_features_validation.csv
FILE_FORMAT = (FORMAT_NAME = EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_FF)
ON_ERROR = 'ABORT_STATEMENT';

-- ---------------------------------------------------------------------
-- 5) Load Landsat features
--    CSV cols: Latitude, Longitude, Sample Date, nir, green, swir16, swir22, NDMI, MNDWI
--    Table cols: LATITUDE, LONGITUDE, SAMPLE_DATE, NIR, GREEN, SWIR16, SWIR22, NDMI, MNDWI
-- ---------------------------------------------------------------------
COPY INTO EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_TRAINING
    (LATITUDE, LONGITUDE, SAMPLE_DATE, NIR, GREEN, SWIR16, SWIR22, NDMI, MNDWI)
FROM @EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_STAGE/files/landsat_features_training.csv
FILE_FORMAT = (FORMAT_NAME = EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_FF)
ON_ERROR = 'ABORT_STATEMENT';

COPY INTO EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_VALIDATION
    (LATITUDE, LONGITUDE, SAMPLE_DATE, NIR, GREEN, SWIR16, SWIR22, NDMI, MNDWI)
FROM @EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_STAGE/files/landsat_features_validation.csv
FILE_FORMAT = (FORMAT_NAME = EY_AI_DATA_CHALLENGE.FEATURE_STORE.FEATURE_CSV_FF)
ON_ERROR = 'ABORT_STATEMENT';

-- ---------------------------------------------------------------------
-- 6) Verify row counts
-- ---------------------------------------------------------------------
SELECT 'TERRACLIMATE_FEATURES_TRAINING'   AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_TRAINING
UNION ALL
SELECT 'TERRACLIMATE_FEATURES_VALIDATION', COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_VALIDATION
UNION ALL
SELECT 'LANDSAT_FEATURES_TRAINING',        COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_TRAINING
UNION ALL
SELECT 'LANDSAT_FEATURES_VALIDATION',      COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_VALIDATION;
