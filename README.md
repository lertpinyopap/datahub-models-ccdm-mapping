# datahub-models-reference-data

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
- `scripts/`
  Thin Python runner used by Airflow and local operators.
- `dags/config/`
  Environment-specific TMS job configs published by the shared TMS pipeline module.
- `config/dbt/`
  Example dbt profile template for the required `datahub_type_materialisation` profile.

## Git Submodule

This repo uses `datahub-tms-pipeline` as a git submodule for shared Airflow DAG
and deployment logic.

Add it to a fresh checkout with:

```bash
git submodule add -b features/tms-pipeline https://github.com/LatitudeFinancial/datahub-tms-pipeline.git datahub-tms-pipeline
git submodule update --init --recursive
```

If `.gitmodules` already exists but `git submodule status` shows nothing,
register the submodule path with:

```bash
git submodule add -b features/tms-pipeline https://github.com/LatitudeFinancial/datahub-tms-pipeline.git datahub-tms-pipeline
```

After cloning this repo later, initialize the submodule with:

```bash
git submodule update --init --recursive
```

To update the submodule to the latest committed version from its configured
branch:

```bash
git submodule update --remote datahub-tms-pipeline
```

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

## Local TMS Runtime

For local testing, build the TMS runtime from the TMS source repo and place the
runtime under this repo's `libs/` folder.

From this repo:

```bash
git clone https://github.com/LatitudeFinancial/datahub-type-materialisation-specification.git ../datahub-type-materialisation-specification
cd ../datahub-type-materialisation-specification
git checkout features/tms-pipeline
bash scripts/build_tms_package.sh
```

Then install the built runtime into this repo:

```bash
cd ../datahub-models-reference-data
mkdir -p libs
rm -rf libs/tms-env
tar -xzf ../datahub-type-materialisation-specification/dist/tms-env.tar.gz -C libs
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
```

Verify:

```bash
"$TMS_BIN" --help
```

The `libs/` folder is local runtime output and should not be committed.

The local runner lives in the shared `datahub-tms-pipeline` module and calls the
same `tms_loader.py` helper used by Airflow. Run it from this repo root so the
default `--project-root` is this consumer repo.

## Local Example

Run all tasks from the local job config:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --job-config dags/config/tms_jobs.dev.json \
  --target dev
```

Run one task from the job config:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --job-config dags/config/tms_jobs.dev.json \
  --job reference_country_loader \
  --task load_core \
  --target dev
```

If you run the shared script from outside this repo, pass the consumer repo root
explicitly:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python ../datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --project-root . \
  --job-config dags/config/tms_jobs.dev.json \
  --target dev
```

The job config uses `target: MWAA` because it is the Airflow runtime target.
For local testing, pass `--target dev` unless your local
`datahub_type_materialisation` dbt profile also defines a target named `MWAA`.

Run one spec directly:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/reference_data/core/CORE_COUNTRY.yaml \
  --target dev \
  --dbt-vars '{"OVERRIDE_DB":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_","tms_job_schema":"INTERMEDIATE"}'
```

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/reference_data/mapping/MAPPING_COUNTRY.yaml \
  --target dev \
  --dbt-vars '{"OVERRIDE_DB":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_", "tms_job_schema":"INTERMEDIATE"}'
```

First migration load for an existing table shape:

```bash
export TMS_BIN="$PWD/libs/tms-env/bin/tms"
python datahub-tms-pipeline/dags/local_run_tms_loader.py \
  --spec specs/reference_data/mapping/MAPPING_COUNTRY.yaml \
  --target dev \
  --full-refresh \
  --dbt-vars '{"OVERRIDE_DB":"SAS_MIGRATION_WORKSPACE","ENV_PREFIX":"NONPROD_", "tms_job_schema":"INTERMEDIATE"}'
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
- each `task_groups[].group_id` becomes one Airflow `TaskGroup`
- each `task_groups[].tasks[]` item runs one TMS spec through the shared TMS loader
- `task_groups[].tasks[].depends_on` controls ordering, such as `load_core` before `load_mapping`
- task-level `profile_args` and `vars` can override the top-level defaults
- at runtime, the DAG resolves `OVERRIDE_DB` from `profile_args.database` without adding `ENV_PREFIX`
- if the Airflow environment already provides `OVERRIDE_DB`, that explicit value wins
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
      "dag_id": "reference_data_loader",
      "target": "MWAA",
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
      "dag_id": "reference_core_loader",
      "target": "MWAA",
      "tags": ["reference-data", "tms"],
      "schedule": "once",
      "task_groups": [
        {
          "group_id": "country",
          "tasks": [
            {
              "task_id": "load_core_country",
              "spec": "specs/reference_data/core/CORE_COUNTRY.yaml"
            }
          ]
        }
      ]
    },
    {
      "dag_id": "reference_mapping_loader",
      "target": "MWAA",
      "tags": ["reference-data", "tms"],
      "schedule": "0 6 * * *",
      "task_groups": [
        {
          "group_id": "country",
          "tasks": [
            {
              "task_id": "load_mapping_country",
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
