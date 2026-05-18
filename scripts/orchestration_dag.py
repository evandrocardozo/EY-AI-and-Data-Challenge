"""Orchestration DAG for the 2026 EY AI & Data Challenge.

Builds a Snowflake Task DAG that runs the three notebooks in dependency order:

    LANDSAT_EXTRACTION  ----+
                            +--->  BENCHMARK_MODEL_AND_INFERENCE
    TERRACLIMATE_EXTRACTION-+

The two extraction notebooks run in parallel as roots; the benchmark notebook
runs after both finish.

How it works
------------
1. Each workspace `.ipynb` file is (re)created as a Snowflake **NOTEBOOK**
   object in `EY_AI_DATA_CHALLENGE.MODEL_REGISTRY` so it can be executed
   server-side via `EXECUTE NOTEBOOK ...()`.
2. A DAG is defined with `snowflake.core.task.dagv1` and deployed under
   `EY_AI_DATA_CHALLENGE.MODEL_REGISTRY`.
3. Each `DAGTask` runs the corresponding `EXECUTE NOTEBOOK` SQL command.
4. The DAG is scheduled (default: manual / paused) — trigger with
   `dag_op.run(dag)` or `EXECUTE TASK` on the root task.

Usage
-----
    # From a Snowsight worksheet / notebook with an active Snowpark session:
    from scripts.orchestration_dag import deploy_dag
    deploy_dag(session)

    # Or run on demand:
    from scripts.orchestration_dag import run_dag
    run_dag(session)

Requires
--------
    pip install snowflake snowflake-snowpark-python snowflake.core

Pre-requisites
--------------
* `scripts/feature_store_setup.sql`     has been executed.
* `scripts/load_feature_csvs.sql`       has been executed (initial load).
* `scripts/model_registry_setup.sql`    has been executed.
* A warehouse the executing role can use (default: `COMPUTE_WH`).
"""

from __future__ import annotations

from datetime import timedelta
from typing import Optional

from snowflake.core import Root
from snowflake.core.task import StoredProcedureCall  # noqa: F401  (re-exported for convenience)
from snowflake.core.task.dagv1 import DAG, DAGOperation, DAGTask


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DATABASE = "EY_AI_DATA_CHALLENGE"
SCHEMA = "MODEL_REGISTRY"
WAREHOUSE = "COMPUTE_WH"
DAG_NAME = "EY_WATER_QUALITY_PIPELINE"

# Workspace stage that hosts the .ipynb files. Adjust if you move them.
WORKSPACE_STAGE = (
    'snow://workspace/USER$.PUBLIC."EY-AI-and-Data-Challenge"/versions/live'
)

# Each entry: (snowflake notebook object name, workspace path to .ipynb)
NOTEBOOKS = {
    "NB_LANDSAT_EXTRACTION": "notebooks/LANDSAT_DATA_EXTRACTION_NOTEBOOK_SNOWFLAKE.ipynb",
    "NB_TERRACLIMATE_EXTRACTION": "notebooks/TERRACLIMATE_DATA_EXTRACTION_NOTEBOOK_SNOWFLAKE.ipynb",
    "NB_BENCHMARK_MODEL": "notebooks/benchmark_model_notebook_snowflake.ipynb",
}


# ---------------------------------------------------------------------------
# Notebook registration
# ---------------------------------------------------------------------------

def _ensure_notebook_objects(session) -> None:
    """Create / replace each workspace `.ipynb` as a Snowflake NOTEBOOK object."""
    session.sql(f"USE DATABASE {DATABASE}").collect()
    session.sql(f"USE SCHEMA {DATABASE}.{SCHEMA}").collect()

    for nb_name, nb_path in NOTEBOOKS.items():
        ddl = f"""
        CREATE OR REPLACE NOTEBOOK {DATABASE}.{SCHEMA}.{nb_name}
            FROM '{WORKSPACE_STAGE}'
            MAIN_FILE = '{nb_path}'
            QUERY_WAREHOUSE = {WAREHOUSE}
        """
        session.sql(ddl).collect()
        # ALTER ... ADD LIVE VERSION is required before EXECUTE NOTEBOOK works
        session.sql(
            f"ALTER NOTEBOOK {DATABASE}.{SCHEMA}.{nb_name} ADD LIVE VERSION FROM LAST"
        ).collect()
        print(f"Registered notebook: {DATABASE}.{SCHEMA}.{nb_name}")


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------

def _build_dag() -> DAG:
    """Define the pipeline DAG.

    Layout:
        landsat_extract  \\
                          --> benchmark_model
        terraclimate_extract /
    """
    dag = DAG(
        name=DAG_NAME,
        schedule=timedelta(days=1),  # default cadence; remove or change as needed
        warehouse=WAREHOUSE,
        comment=(
            "EY AI & Data Challenge: extracts Landsat & TerraClimate features, "
            "then trains the benchmark model and writes predictions."
        ),
    )

    landsat = DAGTask(
        name="LANDSAT_EXTRACTION",
        definition=f"EXECUTE NOTEBOOK {DATABASE}.{SCHEMA}.NB_LANDSAT_EXTRACTION()",
        warehouse=WAREHOUSE,
    )
    terraclimate = DAGTask(
        name="TERRACLIMATE_EXTRACTION",
        definition=f"EXECUTE NOTEBOOK {DATABASE}.{SCHEMA}.NB_TERRACLIMATE_EXTRACTION()",
        warehouse=WAREHOUSE,
    )
    benchmark = DAGTask(
        name="BENCHMARK_MODEL_AND_INFERENCE",
        definition=f"EXECUTE NOTEBOOK {DATABASE}.{SCHEMA}.NB_BENCHMARK_MODEL()",
        warehouse=WAREHOUSE,
    )

    # Wire dependencies: extraction tasks are roots, benchmark is downstream of both.
    dag.add_task(landsat)
    dag.add_task(terraclimate)
    dag.add_task(benchmark)
    benchmark.add_predecessors([landsat, terraclimate])

    return dag


# ---------------------------------------------------------------------------
# Public entry points
# ---------------------------------------------------------------------------

def deploy_dag(session, *, paused: bool = True) -> None:
    """Register notebooks, deploy the DAG, and (optionally) leave it paused.

    Parameters
    ----------
    session : Snowpark Session
        Active Snowpark session with privileges to create notebooks/tasks in
        EY_AI_DATA_CHALLENGE.MODEL_REGISTRY.
    paused : bool, default True
        If True, the DAG is created but not started. Use `run_dag(session)` to
        trigger it on demand, or `ALTER TASK ... RESUME` to enable the schedule.
    """
    _ensure_notebook_objects(session)

    root = Root(session)
    schema = root.databases[DATABASE].schemas[SCHEMA]

    dag = _build_dag()
    dag_op = DAGOperation(schema)
    dag_op.deploy(dag, mode="orreplace")
    print(f"Deployed DAG {DATABASE}.{SCHEMA}.{DAG_NAME}")

    if not paused:
        dag_op.resume(dag)
        print(f"Resumed DAG {DAG_NAME}")


def run_dag(session) -> None:
    """Trigger a single immediate run of the DAG (does not require a schedule)."""
    root = Root(session)
    schema = root.databases[DATABASE].schemas[SCHEMA]
    dag = _build_dag()
    DAGOperation(schema).run(dag)
    print(f"Triggered ad-hoc run of DAG {DAG_NAME}")


def drop_dag(session) -> None:
    """Tear down the DAG (e.g. for re-deployment)."""
    root = Root(session)
    schema = root.databases[DATABASE].schemas[SCHEMA]
    dag = _build_dag()
    DAGOperation(schema).drop(dag)
    print(f"Dropped DAG {DAG_NAME}")


# ---------------------------------------------------------------------------
# CLI helper
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # When executed in a Snowflake Notebook / SiS / Worksheet, an implicit
    # `session` is available. When run elsewhere, build one yourself.
    try:
        session  # type: ignore[name-defined]
    except NameError:
        from snowflake.snowpark import Session

        # Falls back to ~/.snowflake/connections.toml or env vars
        session = Session.builder.getOrCreate()

    deploy_dag(session, paused=True)
