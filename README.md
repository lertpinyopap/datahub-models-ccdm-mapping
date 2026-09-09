# datahub-models-ccdm-mapping

Reference data loading is now managed through the Type Materialisation Specification (TMS) tool from:

- `https://github.com/LatitudeFinancial/datahub-type-materialisation-specification`

This repository is no longer a handwritten dbt project. The YAML specs in this repo are the source of truth, and dbt artifacts are generated ephemerally by `tms generate-dbt`.

Do not add checked-in dbt model files, seed configs, or per-reference `schema.yml` files for each reference table. A reference table should be added by creating a TMS spec and its source data file; the generated dbt project stays under `tmp/generated/` at runtime.

Two SCD2 patterns are prepared:

- `CORE` specs can load source-provided history by using a source effective timestamp field and letting TMS generate the managed `valid_from_datetime` and `valid_to_datetime` columns.
- `MAPPING` specs treat the CSV as the current full snapshot and use `missing_from_source` delete detection plus an explicit load-effective timestamp.

## Repo Layout

- `specs/abstract/`
  Shared abstract TMS specs for reference-data patterns.
- `specs/reference_data/`
  Concrete TMS specs for individual reference datasets.
- `data/reference_data/`
  CSV inputs used by `source.load_method: dbt_seed`.
- `macros/`
  Local Python macro objects referenced by TMS specs.
- `datahub-tms-pipeline/`
  Shared git submodule containing the Airflow DAG entrypoint, local runner, and
  TMS loader helper.
- `datahub-type-materialisation-specification/`
  Optional local git submodule containing the TMS source used to build a local
  `TMS_BIN` runtime for development.
- `dags/config/`
  Environment-specific TMS job configs published by the shared TMS pipeline module.
- `config/dbt/`
  Example dbt profile template for the required `datahub_type_materialisation` profile.

## Git Submodules

This repo uses shared repositories as git submodules:

- `datahub-tms-pipeline`: shared Airflow DAG and deployment logic.
- `datahub-type-materialisation-specification`: TMS source used to build the
  local `tms` executable for development.

Add the pipeline module to a fresh checkout with:

```bash
git submodule add -b features/tms-pipeline https://github.com/LatitudeFinancial/datahub-tms-pipeline.git datahub-tms-pipeline
git submodule update --init --recursive
```

Add the TMS source module with:

```bash
git submodule add -b dev https://github.com/LatitudeFinancial/datahub-type-materialisation-specification.git datahub-type-materialisation-specification
git submodule update --init --recursive
```

If `.gitmodules` already exists but `git submodule status` shows a missing
submodule, register the missing path with the relevant `git submodule add`
command above.

For the current feature branch, use:

- `datahub-tms-pipeline`: `features/tms-pipeline`
- `datahub-type-materialisation-specification`: `features/python1.12`

After cloning this repo later, initialize all submodules with:

```bash
git submodule update --init --recursive
```

To update a submodule to the latest committed version from its configured
branch:

```bash
git submodule update --remote datahub-tms-pipeline
git submodule update --remote datahub-type-materialisation-specification
```

Commit the submodule pointer update in this repo after testing.

## Local TMS Runtime

For local testing, build the TMS runtime from the TMS source submodule and place
the generated runtime under this repo's ignored `libs/` folder.

Install Python 3.12 first, then create and activate a local virtual environment
from this repo root:

```bash
brew install python@3.12
python3.12 --version
python3.12 -m venv .venv
source .venv/bin/activate

```bash
pip install dbt-snowflake==1.11.6
dbt --version
```

If your shell does not resolve `python3.12`, add Homebrew's Python 3.12 path to
`PATH`.

With the virtual environment activated:

```bash
bash datahub-type-materialisation-specification/scripts/build_tms_package.sh \
  --install-venv "$PWD/libs/tms-env" \
  --archive "$PWD/libs/tms-env.tar.gz"
```

The build script installs the TMS runtime directly into `libs/tms-env` and also
copies the required schema JSON files into that runtime.

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
```

Verify:

```bash
"$TMS_BIN" --help
```

The `libs/` folder is local runtime output and should not be committed.

If you only need the wheel artifact for Airflow installation, use the `.whl`
created under `datahub-type-materialisation-specification/dist/`. If you need a
portable local runtime for this repo, build it directly into `libs/tms-env` as
shown above so the executable paths stay inside this repo.

## First Working Slice

This scaffold currently includes example specs for:

- `CORE.COUNTRY`
- `MAPPING.COUNTRY`

Use them as the template for the remaining reference datasets.

## Runtime Flow

The intended execution flow is:

1. `tms parse`
2. `tms generate-dbt`
3. `tms dbt-build`

The generated dbt project is ephemeral and should not be committed.

TMS reads the final destination from each spec's `target` block:

```yaml
target:
  schema: MAPPING
  table_name: CURRENCY
```

`table_name` is consumed by `tms generate-dbt` when it writes the final model alias. The runner also reads `target.schema` from the selected TMS spec and applies it to the generated source helper view so raw seed tables can stay in `source.seed.schema` while helper and final models stay in the target schema.

If a destination table already exists from a previous implementation and does not contain TMS-generated SCD2 columns such as `BUSINESS_DATA_HASH`, run the first TMS load with `--full-refresh`. After the table has the TMS-owned shape, use normal incremental runs.

Current validation status in this repo:

- `specs/reference_data/core/CORE_COUNTRY.yaml`: `tms parse` passes
- `specs/reference_data/mapping/MAPPING_COUNTRY.yaml`: `tms parse` passes
- `datahub-tms-pipeline/dags/local_run_tms_loader.py`: shared local developer helper for manual testing
- Remaining external prerequisite: a dbt profile named `datahub_type_materialisation`

The local runner lives in the shared `datahub-tms-pipeline` module and calls the
same `tms_loader.py` helper used by Airflow. Run it from this repo root so the
default `--project-root` is this consumer repo.

## Local Example

Run all tasks from the local job config:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --job-config dags/config/tms_jobs.local.json \
  --keep-generated-project \
  --target dev
```

Run one task from the job config:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --job-config dags/config/tms_jobs.local.json \
  --job datahub-models-ccdm-mapping-reference_loader \
  --task load_core \
  --keep-generated-project \
  --target dev \
  --dbt-vars '{"database":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_","tms_job_schema":"INTERMEDIATE"}'
```

If you run the shared script from outside this repo, pass the consumer repo root
explicitly:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python ../datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --project-root . \
  --job-config dags/config/tms_jobs.local.json \
  --target dev \
  --keep-generated-project \
  --dbt-vars '{"database":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_","tms_job_schema":"INTERMEDIATE"}'
```

## Repo Tests

This repo includes local-only Python unit tests for the sample reference lookup
macros. They are kept outside dbt's `tests/` path, so they do not run in dbt
or Airflow.

Install `pytest` in this repo virtual environment:

```bash
.venv/bin/python -m pip install pytest
```

Run all local unit tests:

```bash
python -m pytest
```

Run only the reference lookup macro tests:

```bash
x
```

`unittest` is still available if you want the built-in runner:

```bash
python -m unittest unit_tests.test_reference_lookup_macros
```

Preview one example lookup against Snowflake without materializing a model.
By default, the reference macro lookups against <ENV_PREFIX)REFERENCE database.

```bash
dbt show \
  --project-dir . \
  --target dev \
  --vars '{"ENV_PREFIX":"NONPROD_"}' \
  --output json \
  --inline "$(cat unit_tests/examples/reference_lookup/sample_reference_lookup_mapping_country.sql)"
```

To run all example reference models lookup
```bash
for sql_file in unit_tests/examples/reference_lookup/*.sql; do
  echo "=== $sql_file ==="
    dbt show \
    --project-dir . \
    --target dev \
    --vars '{"ENV_PREFIX":"NONPROD_"}' \
    --output json \
    --inline "$(cat "$sql_file")"
done
```

The tests live in:

- `unit_tests/test_reference_lookup_macros.py`

They verify:

- `reference_lookup_mapping` contains mapping-to-core resolution logic
- `reference_lookup_core` contains current effective core-row lookup logic
- example SQL under `unit_tests/examples/reference_lookup/` use the macros consistently

The job config uses `target: MWAA` because it is the Airflow runtime target.
For local testing, pass `--target dev` unless your local
`datahub_type_materialisation` dbt profile also defines a target named `MWAA`.

Run one spec directly:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/reference_data/core/CORE_COUNTRY.yaml \
  --target dev \
  --keep-generated-project 
  --dbt-vars '{"database":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_","tms_job_schema":"INTERMEDIATE"}'
```

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/reference_data/mapping/MAPPING_COUNTRY.yaml \
  --target dev \
  --keep-generated-project 
  --dbt-vars '{"database":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_", "tms_job_schema":"INTERMEDIATE"}'
```

First migration load for an existing table shape:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/reference_data/mapping/MAPPING_COUNTRY.yaml \
  --target dev \
  --keep-generated-project
  --full-refresh \
  --dbt-vars '{"database":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_", "tms_job_schema":"INTERMEDIATE"}'
```

Run a source-to-target mapping spec locally:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/ccdm/card_customer/CARD_CUSTOMER.yaml \
  --target dev \
  --keep-generated-project
  --dbt-vars '{"database":"SAS_MIGRATION_WORKSPACE", "ENV_PREFIX":"NONPROD_"}'
```

## Airflow

Airflow should use the shared DAG entrypoint from `datahub-tms-pipeline/dags/dags_tms_entrypoint.py`.

Terraform in the shared `datahub-tms-pipeline` module publishes the entrypoint and shared helper to MWAA as:

```text
dags/<tms_project_name>/<tms_project_name>.py
dags/<tms_project_name>/tms_loader.py
```

The entrypoint calls the shared `tms_loader.py` helper. Local developer testing should use `datahub-tms-pipeline/dags/local_run_tms_loader.py`.

The DAG is driven by `dags/config/tms_jobs.<env>.json` and the shared `datahub-tms-pipeline` module:

- top-level `profile_args` holds connection-style overrides such as the exact Snowflake `database`
- top-level `conn_id` holds the Airflow/Snowflake connection id
- top-level `schedule` accepts a cron expression, `"once"`, or `null`/`"manual"` for manual-only execution
- top-level `vars` holds dbt vars such as `ENV_PREFIX` and `tms_job_schema`
- `vars.database`, when provided, is the exact physical output database name; the loader does not prepend `ENV_PREFIX`
- use `ENV_PREFIX` separately inside specs or macros for source database names and target-system values that intentionally need an environment prefix
- each `task_groups[].group_id` becomes one Airflow `TaskGroup`
- each `task_groups[].tasks[]` item runs one TMS spec through the shared TMS loader
- `task_groups[].tasks[].depends_on` controls ordering, such as `load_core` before `load_mapping`
- task-level `profile_args` and `vars` can override the top-level defaults
- at runtime, the DAG resolves `database` from `vars.database`, then `profile_args.database`, without adding `ENV_PREFIX`
- reference lookup macros use `<ENV_PREFIX>REFERENCE`; this is independent of the target database selected by `database`
- pass `reference_database='OTHER_DB'` to a lookup macro only when a specific lookup database is required
- `TMS_BIN` defaults to the Airflow-installed runtime at `/usr/local/airflow/python3-virtualenv/tms-env/bin/tms`

Example:

```json
{
  "conn_id": "snowflake_connection",
  "profile_args": {
    "database": "NONPROD_REFERENCE",
    "schema": "INTERMEDIATE",
    "warehouse": "WH_NONPROD_SVC_DATA_AIRFLOW_LOAD_LIGHT",
    "role": "",
    "client_session_keep_alive": true,
    "threads": 1
  },
  "vars": {
    "ENV_PREFIX": "NONPROD_",
    "tms_job_schema": "INTERMEDIATE"
  },
  "jobs": [
    {
      "dag_id": "datahub-models-ccdm-mapping-reference_loader",
      "target": "test",
      "tags": ["reference-data", "tms"],
      "schedule": "once",
      "task_groups": [
        {
          "group_id": "reference_country",
          "tasks": [
            {
              "task_id": "load_core",
              "spec": "specs/reference_data/core/CORE_COUNTRY.yaml"
            },
            {
              "task_id": "load_mapping",
              "spec": "specs/reference_data/mapping/MAPPING_COUNTRY.yaml",
              "depends_on": ["load_core"]
            }
          ]
        }
      ]
    }
  ]
}
```

To register multiple Airflow DAGs from the same `tms_jobs.<env>.json`, add more entries to the top-level `jobs` array. Top-level `vars`, `profile_args`, and `conn_id` are shared. DAG-level fields such as `target`, `tags`, and `schedule` live inside each job.

```json
{
  "conn_id": "snowflake_connection",
  "vars": {
    "ENV_PREFIX": "NONPROD_",
    "tms_job_schema": "INTERMEDIATE"
  },
  "profile_args": {
    "database": "NONPROD_REFERENCE",
    "schema": "INTERMEDIATE",
    "warehouse": "WH_NONPROD_SVC_DATA_AIRFLOW_LOAD_LIGHT",
    "role": "",
    "client_session_keep_alive": true,
    "threads": 1
  },
  "jobs": [
    {
      "dag_id": "datahub-models-ccdm-mapping-reference_loader",
      "target": "test",
      "tags": ["reference-data", "tms"],
      "schedule": "once",
      "task_groups": [
        {
          "group_id": "country",
          "tasks": [
            {
              "task_id": "load_core",
              "spec": "specs/reference_data/core/CORE_COUNTRY.yaml"
            }
          ]
        }
      ]
    },
    {
      "dag_id": "reference_mapping_loader",
      "target": "test",
      "tags": ["reference-data", "tms"],
      "schedule": "0 6 * * *",
      "task_groups": [
        {
          "group_id": "country",
          "tasks": [
            {
              "task_id": "load_mapping",
              "spec": "specs/reference_data/mapping/MAPPING_COUNTRY.yaml"
            }
          ]
        }
      ]
    }
  ]
}
```

During CI deployment, this repo only deploys the DAG/config through Terraform and syncs the consumer repository files to MWAA S3 with `make tms-repo-sync`.

Build and install the TMS runtime from the TMS source repository, as shown in
the local `TMS_BIN` setup above. This repo consumes the built runtime but does
not build TMS itself during deployment.

`datahub-tms-pipeline` is expected to be available from the git submodule before the pipeline runs `make`. The shared pipeline does not build or upload TMS runtime artifacts.

The TMS executable should already be installed in the Airflow runtime and exposed through:

```bash
TMS_BIN=/usr/local/airflow/python3-virtualenv/tms-env/bin/tms
```

Before running the DAG:

- `TMS_BIN` must point to the installed TMS executable
- the `datahub_type_materialisation` dbt profile must exist
- the Airflow worker must have access to Snowflake credentials used by dbt
- the Airflow runtime must expose any dbt/Snowflake secrets required by the chosen target

Use [config/dbt/profiles.yml.example](config/dbt/profiles.yml.example) as the starting template for the operator-managed dbt profile.

The repo should not define its own Airflow DAG file. Keep only `dags/config/tms_jobs.<env>.json` here, and let the shared module own the DAG Python.
