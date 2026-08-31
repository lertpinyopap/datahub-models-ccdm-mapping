# Reference Data Specification

This file records the working conventions for reference data in this repository.

## Scope

- The source of truth is the TMS spec YAML under `specs/`.
- CSV inputs live under `data/reference_data/`.
- Generated dbt projects under `tmp/generated/` are runtime artifacts only and must not be committed.

## File Naming

- CORE CSV files use `REFERENCE.CORE.<TABLE_NAME>.csv`.
- MAPPING CSV files use `REFERENCE.MAPPING.<TABLE_NAME>.csv`.
- CORE specs use `specs/reference_data/core/CORE_<TABLE_NAME>.yaml`.
- MAPPING specs use `specs/reference_data/mapping/MAPPING_<TABLE_NAME>.yaml`.
- Table and column names are uppercase with underscore.

## CSV Header Rules

- Header names must be uppercase with underscore.
- Do not use spaces in headers.
- Example:

```text
CHANGE_CONTROL,SOURCE_SYSTEM,SOURCE_CODE,SOURCE_DESCRIPTION,TARGET_SYSTEM,TARGET_CODE,TARGET_DESCRIPTION
```

## Date Format Rules

- For reference data, `VALID_FROM_DATETIME` and `VALID_TO_DATETIME` must use `%Y-%m-%d`.
- Example values:
  `1900-01-01`
  `9999-12-31`
- Do not use `DD/MM/YYYY` in this repo.

## CORE Reference Rules

- CORE specs extend `REFERENCE_CORE_SCD2_MANUAL`.
- CORE CSV files are treated as source-provided history.
- CORE CSV files must include these managed history columns:
  `IS_CURRENT_FLAG`
  `IS_DELETED_FLAG`
  `VALID_FROM_DATETIME`
  `VALID_TO_DATETIME`
- In the abstract CORE spec:
  - `VALID_FROM_DATETIME` is parsed with format `%Y-%m-%d` and `time_if_missing: start_of_day`
  - `VALID_TO_DATETIME` is parsed with format `%Y-%m-%d` and `time_if_missing: end_of_day`
- `IS_CURRENT_FLAG` and `IS_DELETED_FLAG` must contain only `Y` or `N`.
- If source data legitimately has blank values for a business attribute, the concrete spec must mark that field `nullable: true`.

## MAPPING Reference Rules

- MAPPING specs extend `REFERENCE_MAPPING_SCD2_AUTO`.
- MAPPING CSV files represent the latest full snapshot.
- MAPPING files must contain exactly 7 headers, in this order:
  `CHANGE_CONTROL`
  `SOURCE_SYSTEM`
  `SOURCE_CODE`
  `SOURCE_DESCRIPTION`
  `TARGET_SYSTEM`
  `TARGET_CODE`
  `TARGET_DESCRIPTION`
- MAPPING source Excel should be fixed first if a header is wrong; do not rely on CSV export normalization as the source-of-truth correction.
- MAPPING source Excel should not contain trailing blank header columns.
- MAPPING files must not contain fully blank data rows. Empty trailing rows in Excel should be removed from the `Mapping` sheet before export.
- `TARGET_SYSTEM` in the CSV stores the unprefixed logical target such as `REFERENCE.CORE.COUNTRY`.
- At load time, `TARGET_SYSTEM` is transformed with `reference_macros.prefix_target_system`.
- Default mapping business key is:
  `SOURCE_SYSTEM`
  `SOURCE_CODE`

## Schema and Load Expectations

- Raw seed tables load into `INTERMEDIATE`.
- CORE target tables load into `CORE`.
- MAPPING target tables load into `MAPPING`.
- Local TMS runtime should be installed under `libs/tms-env`.
- Local dbt runtime is expected under `.venv/bin/dbt`.

## Runtime Variables

- `TMS_BIN` should point to `libs/tms-env/bin/tms`.
- `DBT_EXECUTABLE_PATH` should point to `.venv/bin/dbt` for local runs.
- `ENV_PREFIX` is used to prefix target-system values at runtime.
- `OVERRIDE_DB` can be passed to direct the load into a specific Snowflake database.
- `tms_job_schema` is used for staging schema control, typically `INTERMEDIATE`.

## Load Behavior

- Use `--full-refresh` when replacing an older non-TMS target table shape with the TMS-generated shape.
- After the target has the correct TMS-managed structure, normal incremental runs can be used.
- MAPPING loads use SCD2 auto behavior with full-snapshot delete detection.
- CORE loads use manual SCD2 behavior based on the history supplied in the CSV.

## Source-To-Target SCD2 Derived Rules

- Source-to-target specs can use `change_type: scd2_derived` when the source provides business-effective dates but not final SCD2 control columns.
- `scd2_derived` generates `IS_CURRENT_FLAG`, `IS_DELETED_FLAG`, `VALID_FROM_DATETIME`, `VALID_TO_DATETIME`, `BUSINESS_DATA_HASH`, and audit columns. These generated metadata fields should not be declared in `target.fields`.
- Prefer `scd.valid_from_datetime.source_column` when the source query already projects the effective start as a named column.
- `scd.valid_from_datetime.expression` is still supported for backward compatibility and for inline SQL expressions, for example `coalesce(UPDATED_DATETIME, CREATED_DATETIME)`.
- Example using the preferred source-column style:

```yaml
source:
  format: table
  query: |
    select
      ACCOUNT_ID,
      coalesce(OPENED_AT, cast('1901-01-01' as timestamp_tz)) as SOURCE_EFFECTIVE_FROM_DATETIME
    from RAW.ACCOUNT

control_data:
  change_type: scd2_derived
  scd:
    valid_from_datetime:
      source_column: SOURCE_EFFECTIVE_FROM_DATETIME
```

- `VALID_TO_DATETIME` is derived from the next version for the same business key, using the configured offset. Use `offset.unit: nanosecond` and `value: -1` unless a scenario explicitly needs second precision.
- Use `derivation_scope: affected_keys`, `validation_scope: affected_window`, and `window_strategy: previous_and_next` for incremental loads that should recalculate only changed business-key windows.
- Use `scd.deduplicate.order_by` when multiple source rows can have the same business key and effective datetime. The ordering column must be available in the generated source/target field set.
- V2/V10 historical loads should use source effective dates to keep older V2 records non-current. If V2 and V10 need independent current rows, include `SOURCE_SYSTEM` in the business key.
- Detailed examples are kept in `SCD2_DERIVED.md`.

## Data Classification Tags

- TMS supports optional Snowflake tags at target-table and target-column level.
- Tags classify raw business data for downstream masking/governance. They do not control generated key/hash behavior.
- Example:

```yaml
target:
  id: CARD_CUSTOMER
  schema: CORE
  tags:
    DATA_CLASSIFICATION: PII
  fields:
    - id: EMAIL_ADDRESS
      source:
        column: EMAIL_ADDRESS
      data_type: varchar(1024)
      nullable: false
      tags:
        DATA_CLASSIFICATION: PII
        DATA_CATEGORY: IDENTIFIER
```

## Validation Expectations

- Every new spec must pass `tms parse`.
- CSV headers must match the concrete spec column names exactly.
- Nullability in the concrete spec must match the actual CSV content.
- If a validation error occurs, prefer fixing the spec when the source data is valid by design; prefer fixing the CSV when the source data is malformed.
