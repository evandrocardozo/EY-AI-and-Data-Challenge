# EY AI & Data Challenge — Snowflake Solution

End-to-end Snowflake-native pipeline for the [EY AI & Data Challenge](https://challenge.ey.com/?utm_medium=institutions&utm_source=snowflake&utm_campaign=github_repo) — predicting three water-quality parameters (Total Alkalinity, Electrical Conductance, Dissolved Reactive Phosphorus) from satellite (Landsat) and climate (TerraClimate) features.

This repo extends the original challenge starter with:

- a **Feature Store** (Snowflake tables) replacing CSV intermediates,
- a **Model Registry** entry for each trained regressor (warehouse-served, callable from SQL),
- a **Task DAG** orchestrating extraction → training → inference end-to-end.

---

## Architecture

```
                  ┌───────────────────────────────────────────────────────────────┐
                  │                     Snowflake account                          │
                  │                                                                │
   Microsoft       │   EY_AI_DATA_CHALLENGE                                         │
   Planetary       │   ├── FEATURE_STORE                                            │
   Computer        │   │   ├── LANDSAT_FEATURES_TRAINING        (table)             │
   STAC API   ──►  │   │   ├── LANDSAT_FEATURES_VALIDATION      (table)             │
                   │   │   ├── TERRACLIMATE_FEATURES_TRAINING   (table)             │
                   │   │   └── TERRACLIMATE_FEATURES_VALIDATION (table)             │
                   │   │                                                            │
                   │   └── MODEL_REGISTRY                                           │
                   │       ├── NB_LANDSAT_EXTRACTION            (notebook)          │
                   │       ├── NB_TERRACLIMATE_EXTRACTION       (notebook)          │
                   │       ├── NB_BENCHMARK_MODEL               (notebook)          │
                   │       ├── WATER_QUALITY_TOTAL_ALKALINITY            (model)    │
                   │       ├── WATER_QUALITY_ELECTRICAL_CONDUCTANCE      (model)    │
                   │       ├── WATER_QUALITY_DISSOLVED_REACTIVE_PHOSPHORUS (model)  │
                   │       └── EY_WATER_QUALITY_PIPELINE        (task DAG)          │
                   └───────────────────────────────────────────────────────────────┘
```

**DAG**
```
EY_WATER_QUALITY_PIPELINE  (root, daily schedule, suspended by default)
        │
        ├──► LANDSAT_EXTRACTION         ──► EXECUTE NOTEBOOK NB_LANDSAT_EXTRACTION
        ├──► TERRACLIMATE_EXTRACTION    ──► EXECUTE NOTEBOOK NB_TERRACLIMATE_EXTRACTION
        │
        └──► (after both succeed)
             BENCHMARK_MODEL_AND_INFERENCE ──► EXECUTE NOTEBOOK NB_BENCHMARK_MODEL
```

---

## Repository Layout

```
.
├── notebooks/
│   ├── LANDSAT_DATA_EXTRACTION_NOTEBOOK_SNOWFLAKE.ipynb        # Extract Landsat features → Feature Store
│   ├── TERRACLIMATE_DATA_EXTRACTION_NOTEBOOK_SNOWFLAKE.ipynb   # Extract TerraClimate features → Feature Store
│   ├── benchmark_model_notebook_snowflake.ipynb               # Train + register models, write submission
│   ├── TERRACLIMATE_DEMONSTRATION_NOTEBOOK_SNOWFLAKE.ipynb     # Tutorial / EDA
│   ├── landsat_demo_notebook_snowflake.ipynb                  # Tutorial / EDA
│   └── getting_started_notebook.ipynb
│
├── scripts/
│   ├── snowflake_setup.sql            # Original challenge env bootstrap
│   ├── feature_store_setup.sql        # Creates EY_AI_DATA_CHALLENGE.FEATURE_STORE + 4 tables
│   ├── load_feature_csvs.sql          # One-off bulk load of pre-extracted CSVs into the feature tables
│   ├── model_registry_setup.sql       # Creates EY_AI_DATA_CHALLENGE.MODEL_REGISTRY schema
│   └── orchestration_dag.py           # Programmatic deploy of the Task DAG (snowflake.core)
│
├── files/                             # Pre-extracted feature CSVs + ground truth
├── submission_template.csv
├── requirements.txt
└── README.md
```

---

## Quick Start

### 0. Prerequisites

Register through the [EY AI & Data Challenge portal](https://challenge.ey.com/) to get a Snowflake account, then open this workspace in Snowsight.

### 1. Run the original challenge bootstrap

```sql
-- Provided by the challenge organizers. Sets up DB, role, warehouse for the demo notebooks.
@scripts/snowflake_setup.sql
```

### 2. Create the Feature Store

```sql
@scripts/feature_store_setup.sql
```

Creates `EY_AI_DATA_CHALLENGE.FEATURE_STORE` and four tables:

| Table                                | Columns |
| ------------------------------------ | ------- |
| `LANDSAT_FEATURES_TRAINING`          | `LATITUDE, LONGITUDE, SAMPLE_DATE, NIR, GREEN, SWIR16, SWIR22, NDMI, MNDWI` |
| `LANDSAT_FEATURES_VALIDATION`        | same as above |
| `TERRACLIMATE_FEATURES_TRAINING`     | `LATITUDE, LONGITUDE, SAMPLE_DATE, PET` |
| `TERRACLIMATE_FEATURES_VALIDATION`   | same as above |

### 3. (Option A) Bulk-load pre-extracted CSVs

If you want to skip the multi-hour API extraction, use the CSVs that ship in `files/`:

```sql
@scripts/load_feature_csvs.sql
```

This stages the four CSVs and `COPY INTO`s the feature tables (idempotent — truncates first).

Verify:

```sql
SELECT 'TERRACLIMATE_FEATURES_TRAINING' AS T, COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_TRAINING
UNION ALL SELECT 'TERRACLIMATE_FEATURES_VALIDATION', COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_VALIDATION
UNION ALL SELECT 'LANDSAT_FEATURES_TRAINING', COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_TRAINING
UNION ALL SELECT 'LANDSAT_FEATURES_VALIDATION', COUNT(*) FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_VALIDATION;
```

Expected:

| TABLE                                 | ROW_COUNT |
| ------------------------------------- | --------- |
| TERRACLIMATE_FEATURES_TRAINING        | 9,319     |
| TERRACLIMATE_FEATURES_VALIDATION      | 200       |
| LANDSAT_FEATURES_TRAINING             | 9,319     |
| LANDSAT_FEATURES_VALIDATION           | 200       |

### 3. (Option B) Re-extract features from the API

Run the two extraction notebooks. Each one queries Microsoft's Planetary Computer STAC API and writes its DataFrame straight to the feature tables via `session.write_pandas(...)`:

- `notebooks/LANDSAT_DATA_EXTRACTION_NOTEBOOK_SNOWFLAKE.ipynb`
- `notebooks/TERRACLIMATE_DATA_EXTRACTION_NOTEBOOK_SNOWFLAKE.ipynb`

> Each extraction can take several hours. Option A is recommended unless you've changed the input keys.

### 4. Set up the Model Registry

```sql
@scripts/model_registry_setup.sql
```

Creates the `EY_AI_DATA_CHALLENGE.MODEL_REGISTRY` schema.

### 5. Train + register models

Open `notebooks/benchmark_model_notebook_snowflake.ipynb` and run all cells. The notebook:

1. Reads training/validation features **from the feature store** (not from CSV) and aligns rows to the ground-truth dataset on `(Latitude, Longitude, Sample Date)`.
2. Trains three `RandomForestRegressor` models (one per parameter) inside an `sklearn.pipeline.Pipeline` that bundles the fitted `StandardScaler`.
3. Logs each pipeline to the **Snowflake Model Registry** with:
   - `target_platforms=[TargetPlatform.WAREHOUSE]` (SQL-callable inference)
   - `task=Task.TABULAR_REGRESSION`
   - signature inferred from a sample input
   - metrics dict (R², RMSE on train/test)
   - UTC-timestamped `version_name`
4. Writes predictions to `submission.csv` (kept as a CSV per challenge spec).

### 6. Deploy the orchestration DAG

```python
# From a Snowflake notebook / SiS / worksheet with a live Snowpark session:
from scripts.orchestration_dag import deploy_dag, run_dag, drop_dag

deploy_dag(session)        # creates notebooks + tasks (suspended)
# run_dag(session)         # ad-hoc trigger
```

Or via SQL (already wired up in this workspace):

```sql
EXECUTE TASK EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.EY_WATER_QUALITY_PIPELINE;          -- ad-hoc
ALTER TASK EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.LANDSAT_EXTRACTION RESUME;            -- enable schedule
ALTER TASK EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.TERRACLIMATE_EXTRACTION RESUME;
ALTER TASK EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.BENCHMARK_MODEL_AND_INFERENCE RESUME;
ALTER TASK EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.EY_WATER_QUALITY_PIPELINE RESUME;
```

> The tasks are **suspended by default** to avoid accidental long-running notebook runs.

Visualize the DAG in **Snowsight → Monitoring → Task History → Graph view** (select `EY_WATER_QUALITY_PIPELINE`).

---

## Inference from SQL

Once `benchmark_model_notebook_snowflake.ipynb` has been run once, the registered models are callable directly from SQL:

```sql
SELECT
    LATITUDE,
    LONGITUDE,
    SAMPLE_DATE,
    EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.WATER_QUALITY_TOTAL_ALKALINITY!PREDICT(
        SWIR22, NDMI, MNDWI, PET
    )                                AS PREDICTED_TOTAL_ALKALINITY
FROM EY_AI_DATA_CHALLENGE.FEATURE_STORE.LANDSAT_FEATURES_VALIDATION L
JOIN EY_AI_DATA_CHALLENGE.FEATURE_STORE.TERRACLIMATE_FEATURES_VALIDATION T
  USING (LATITUDE, LONGITUDE, SAMPLE_DATE);
```

---

## Reproducibility

| Step                | Idempotent? | Notes                                           |
| ------------------- | ----------- | ----------------------------------------------- |
| `feature_store_setup.sql`   | Yes (`IF NOT EXISTS`) | Safe to re-run.                |
| `load_feature_csvs.sql`     | Yes (`TRUNCATE` + `COPY INTO`) | Reloads from CSV.       |
| `model_registry_setup.sql`  | Yes  | Schema-level only.                                  |
| Extraction notebooks        | Yes (`overwrite=True` on `write_pandas`) | Re-runs replace contents. |
| `benchmark_model_notebook…` | Yes  | Each run logs a new model **version** in the registry. |
| `orchestration_dag.py`      | Yes (`mode="orreplace"` / `CREATE OR REPLACE`) | Re-deploy at will. |

---

## Step-By-Step Guide (original)

For prerequisites, setup, and the foundational walk-through, see the [Developer Guide](https://www.snowflake.com/en/developers/guides/ey-ai-and-data-challenge/).

To learn more about ML development in Snowflake, follow ["Getting Started with Machine Learning Development in Snowflake"](https://www.snowflake.com/en/developers/guides/intro-to-machine-learning-with-snowpark-ml-for-python/#0).

---

## Copyright

The contents of this repo are Copyright 2026 EY, except the contents of `/scripts/` which are Copyright 2026 Snowflake Inc., released under the Apache 2.0 License.
