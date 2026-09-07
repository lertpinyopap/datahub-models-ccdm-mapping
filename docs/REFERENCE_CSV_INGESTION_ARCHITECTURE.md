# Reference Platform CSV Ingestion Architecture

## Purpose

This document describes the implemented design for loading structured reference
CSV files into Snowflake CORE and MAPPING tables. It explains the data flow,
generated dbt objects, SCD2 behaviour, lookup patterns, and Airflow
dependencies.

Detailed CSV and YAML conventions are in [Reference Data Specification](../spec.md).
Runtime lookup macro behaviour is in [Reference Lookup Specification](REFERENCE_LOOKUP_SPEC.md).

## Architecture

~~~mermaid
flowchart LR
    CSV["Reference CSV"] --> SPEC["TMS YAML specification"]
    SPEC --> PARSE["tms parse"]
    PARSE --> GENERATE["generate dbt project"]
    CSV --> SEED["dbt seed: INTERMEDIATE"]
    GENERATE --> SOURCE["<TABLE>__source"]
    SEED --> SOURCE
    SOURCE --> GUARD["<TABLE>__validation_guard"]
    GUARD --> TARGET["CORE or MAPPING SCD2 table"]
    TARGET --> CONSUMERS["Downstream dbt models"]
    AIRFLOW["Airflow dependencies"] --> PARSE
    AIRFLOW --> TARGET
~~~

TMS creates a transient dbt project for each run. The source-controlled
artefacts are the CSV file, concrete YAML specification, abstract
specification, lookup macros, and Airflow job configuration.

## Process Flow

| Step | Component | Output |
| --- | --- | --- |
| 1 | Orchestrator | Resolves the specification, runtime variables, target, and generated-project directory. |
| 2 | `tms parse` | Validates the concrete spec, abstract inheritance, source columns, and macro references. |
| 3 | TMS generation | Creates the transient dbt project and generated models. |
| 4 | dbt seed | Loads the versioned CSV into an `INTERMEDIATE` seed relation. |
| 5 | `<TABLE>__source` | Produces typed source rows after transforms and reference lookups. |
| 6 | `<TABLE>__validation_guard` | Validates the typed rows before the target write. |
| 7 | Target model | Applies the configured SCD2 change type to the `CORE` or `MAPPING` table. |
| 8 | Loader summary | Records generated-project location, target write result, and Snowflake query IDs in task output. |

The target write occurs only after parsing, seed loading, source projection,
and validation complete successfully.

## Component Responsibilities

| Component | Repository location | Role |
| --- | --- | --- |
| CSV input | data/reference_data/core and data/reference_data/mapping | Source reference values and mappings. |
| Concrete spec | specs/reference_data/core and specs/reference_data/mapping | Dataset fields, datatypes, business key, validations, and source file. |
| Abstract spec | specs/abstract | Shared seed, SCD2, audit, and validation behaviour. |
| TMS | libs/tms-env/bin/tms | Validates YAML and generates dbt models. |
| Seed | generated dbt project | Loads the input file into INTERMEDIATE. |
| Source model | generated models | Selects, casts, transforms, and enriches source rows. |
| Validation guard | generated models | Stops the target write when a source row is invalid. |
| Target model | generated models | Writes the SCD2 target table. |
| Airflow config | dags/config/tms_jobs*.json | Runs tables in parent-child order. |

## Reference Data Model

### CORE: canonical reference records

CORE contains the governed enterprise value and its history.

~~~text
CORE.COUNTRY
--------------------------------------------------------------------------------
COUNTRY_KEY | COUNTRY_BUSINESS_KEY | COUNTRY_CODE | COUNTRY_DESCRIPTION
VALID_FROM_DATETIME | VALID_TO_DATETIME | IS_CURRENT_FLAG | IS_DELETED_FLAG
BUSINESS_DATA_HASH | AUDIT_CREATED_DATETIME | AUDIT_LAST_CHANGED_DATETIME
~~~

A CORE CSV can provide history directly. The shared
'REFERENCE_CORE_SCD2_MANUAL' specification stores the supplied effective
window and current/deleted flags.

### MAPPING: source-system translations

MAPPING translates a source-system code to the canonical CORE code.

~~~text
MAPPING.COUNTRY
--------------------------------------------------------------------------------
SOURCE_SYSTEM | SOURCE_CODE | SOURCE_DESCRIPTION | TARGET_SYSTEM | TARGET_CODE
VALID_FROM_DATETIME | VALID_TO_DATETIME | IS_CURRENT_FLAG | IS_DELETED_FLAG
~~~

A MAPPING CSV is a current full snapshot. The shared
'REFERENCE_MAPPING_SCD2_AUTO' specification uses 'SOURCE_SYSTEM + SOURCE_CODE'
as the business key, versions a changed mapping, and marks missing snapshot rows
as deleted.

## CORE Load Pattern

~~~mermaid
flowchart LR
    CSV["REFERENCE.CORE.COUNTRY.csv"] --> SEED["reference_core_country_seed"]
    SEED --> SOURCE["COUNTRY__source"]
    SOURCE --> GUARD["COUNTRY__validation_guard"]
    GUARD --> TARGET["CORE.COUNTRY"]
~~~

A concrete CORE specification supplies the table-specific business key and
business columns. The abstract specification supplies the shared SCD2 and audit
columns.

~~~yaml
id: reference_core_country
extends: REFERENCE_CORE_SCD2_MANUAL
control_data:
  business_key:
    fields:
      - COUNTRY_CODE
source:
  seed:
    file: data/reference_data/core/REFERENCE.CORE.COUNTRY.csv
    name: reference_core_country_seed
    schema: INTERMEDIATE
target:
  id: COUNTRY
  schema: CORE
  table_name: COUNTRY
  fields:
    - id: COUNTRY_CODE
      source:
        pos: 0
        column: COUNTRY_CODE
      data_type: varchar(20)
      nullable: false
~~~

The inherited source-managed history fields are:

~~~text
IS_CURRENT_FLAG
IS_DELETED_FLAG
VALID_FROM_DATETIME
VALID_TO_DATETIME
AUDIT_CREATED_SOURCE
AUDIT_LAST_CHANGED_SOURCE
~~~

## MAPPING Load Pattern

~~~mermaid
flowchart LR
    CSV["REFERENCE.MAPPING.COUNTRY.csv"] --> SEED["reference_mapping_country_seed"]
    SEED --> SOURCE["COUNTRY__source"]
    SOURCE --> GUARD["COUNTRY__validation_guard"]
    GUARD --> TARGET["MAPPING.COUNTRY"]
~~~

~~~yaml
id: reference_mapping_country
extends: REFERENCE_MAPPING_SCD2_AUTO
source:
  seed:
    file: data/reference_data/mapping/REFERENCE.MAPPING.COUNTRY.csv
    name: reference_mapping_country_seed
target:
  id: COUNTRY
  schema: MAPPING
  table_name: COUNTRY
~~~

The abstract mapping specification provides these columns:

~~~text
SOURCE_SYSTEM, SOURCE_CODE, SOURCE_DESCRIPTION
TARGET_SYSTEM, TARGET_CODE, TARGET_DESCRIPTION
~~~

The input value for TARGET_SYSTEM is logical, for example
'REFERENCE.CORE.COUNTRY'. The load applies the environment prefix while writing
the mapping row.

## Generated dbt Models

For a specification with target ID COUNTRY, a generated project creates these
main objects:

| Object | Materialisation | Purpose |
| --- | --- | --- |
| reference_*_seed | seed | CSV copy in INTERMEDIATE. |
| COUNTRY__source | view | Typed, transformed, and enriched source rows. |
| COUNTRY__validation_guard | table | Source validation result. |
| COUNTRY | table or incremental | SCD2 target in CORE or MAPPING. |

The generated source view is the first place to inspect when a lookup, cast, or
source expression is unexpected. The validation guard is the first place to
inspect when the target write is blocked.

~~~sql
select *
from <DATABASE>.INTERMEDIATE.COUNTRY__SOURCE;

select *
from <DATABASE>.INTERMEDIATE.COUNTRY__VALIDATION_GUARD;
~~~

## Foreign Key Lookup Design

There are two lookup paths.

| Source value | Macro | Resolution |
| --- | --- | --- |
| A governed Core code | reference_lookup_core | CORE.<TYPE>.<TYPE>_CODE to the current CORE record. |
| A source-system code | reference_lookup_mapping | MAPPING.<TYPE>.TARGET_CODE, then CORE.<TYPE>.<TYPE>_CODE. |

### Direct CORE lookup

CORE_FINANCIAL_INSTITUTION has COUNTRY_CODE in the source and resolves the
foreign key REGISTERED_COUNTRY_KEY from the current CORE.COUNTRY record.

~~~yaml
- id: REGISTERED_COUNTRY_KEY
  source:
    macro: reference_lookup_core_macros.reference_lookup_core_bridge
    pos: 5
    column: COUNTRY_CODE
    args:
      reference_type: COUNTRY
      source_code_column: COUNTRY_CODE
      value_column: COUNTRY_KEY
      required: true
  data_type: varchar(64)
  nullable: false
~~~

At runtime the macro:

1. reads CORE.COUNTRY from '<ENV_PREFIX>REFERENCE' unless
   'reference_database' is supplied;
2. excludes deleted rows;
3. filters the effective-date window;
4. uses 'QUALIFY ROW_NUMBER()' to prefer the current record;
5. returns the requested value column.

### MAPPING lookup

~~~mermaid
flowchart LR
    A["Source: V10 + AUS"] --> B["MAPPING.COUNTRY: TARGET_CODE = AU"]
    B --> C["CORE.COUNTRY: COUNTRY_CODE = AU"]
    C --> D["COUNTRY_KEY"]
~~~

A downstream dbt model can use the mapping macro directly:

~~~sql
select
    src.COUNTRY_CODE,
    country.COUNTRY_KEY
from source_query as src
{{ reference_lookup_mapping(
    reference_type='COUNTRY',
    source_system='V10',
    ref_alias='country',
    output_column='COUNTRY_KEY',
    source_code_expression='src.COUNTRY_CODE'
) }}
~~~

## Validation and Error Handling

~~~mermaid
flowchart TD
    SOURCE["Typed source rows"] --> REQUIRED{"Required fields present?"}
    REQUIRED -->|No| STOP["Validation error; target unchanged"]
    REQUIRED -->|Yes| RULES{"Types, formats, lookups and SCD2 valid?"}
    RULES -->|No| STOP
    RULES -->|Yes| TARGET["Write SCD2 target"]
~~~

`failure_mode` is configured in `control_data`. TMS supports `fail_load` and
`quarantine_row`; the reference abstract specifications currently configure
`fail_load`. The complete behaviour and configuration shape are defined in the
[TMS Specification](../datahub-type-materialisation-specification/SPEC.md#5-control-data).

The validation guard checks:

- CSV header and field resolution
- required values and nullability
- datatype parsing and transforms
- allowed values and regular expressions
- required lookup results
- SCD2 business-key and effective-window integrity

| Error class | Detection point | Load outcome | Investigation point |
| --- | --- | --- | --- |
| Invalid YAML or unsupported macro | `tms parse` | No generated dbt run starts. | TMS parse diagnostics and the YAML specification. |
| Missing CSV column or duplicate source column | Parse or seed generation | No target write occurs. | CSV header and concrete field `source.column` definitions. |
| Cast, format, nullability, regex, or allowed-value failure | Validation guard | `fail_load` stops the target model; `quarantine_row` writes the failed row to quarantine and continues. | `<TABLE>__source`, validation error output, or configured quarantine relation. |
| Required Core or Mapping lookup has no match | Validation guard | `fail_load` stops the target model; `quarantine_row` writes the failed row to quarantine and continues. | Source code, mapping table, current Core record, or configured quarantine relation. |
| Invalid SCD2 key or effective window | Validation guard | `fail_load` stops the target model; `quarantine_row` quarantines the affected invalid business key. | Typed source rows, target history for the business key, or configured quarantine relation. |
| Snowflake execution or privilege failure | dbt seed, source, guard, or target model | Task fails; the existing target remains unchanged when the target model does not complete. | Compiled SQL, Snowflake query ID, and task log. |


## SCD2 Design

| Dataset | Change type | Input | Result |
| --- | --- | --- | --- |
| CORE reference CSV | scd2_manual | Supplied history and flags | Stores the input history. |
| MAPPING reference CSV | scd2_auto | Latest full snapshot | Versions changed mappings and detects deleted source codes. |
| CCDM source-to-target | scd2_derived | Business row plus effective timestamp | Derives the SCD2 boundaries and flags. |

CORE and MAPPING reference CSVs use manual and automatic SCD2 respectively.
The derived pattern belongs to source-to-target CCDM loads, not the reference
CSV load pattern.

## Dependency Design

Airflow runs parent CORE datasets before a child that needs their key. Each
mapping load runs after its matching CORE load.

~~~mermaid
flowchart LR
    COUNTRY["reference_country.load_core"] --> FI["reference_financial_institution.load_core"]
    FI --> BRAND["reference_brand.load_core"]
    BRAND --> PRODUCT["reference_product.load_core"]
    COUNTRY --> COUNTRYMAP["reference_country.load_mapping"]
    FI --> FIMAP["reference_financial_institution.load_mapping"]
    BRAND --> BRANDMAP["reference_brand.load_mapping"]
    PRODUCT --> PRODUCTMAP["reference_product.load_mapping"]
~~~

A cross-group dependency uses '<group_id>.<task_id>'.

~~~json
{
  "group_id": "reference_financial_institution",
  "tasks": [
    {
      "task_id": "load_core",
      "spec": "specs/reference_data/core/CORE_FINANCIAL_INSTITUTION.yaml",
      "full_refresh": false,
      "depends_on": ["reference_country.load_core"]
    },
    {
      "task_id": "load_mapping",
      "spec": "specs/reference_data/mapping/MAPPING_FINANCIAL_INSTITUTION.yaml",
      "full_refresh": false,
      "depends_on": ["load_core"]
    }
  ]
}
~~~

## Audit Framework and Traceability

The audit framework has two levels: record-level data lineage in each target
row and execution-level evidence for each load invocation.

### Record-Level Audit

Generated targets include:

~~~text
AUDIT_CREATED_DATETIME
AUDIT_LAST_CHANGED_DATETIME
AUDIT_DATA_PROCESS_KEY
AUDIT_CREATED_SOURCE
AUDIT_LAST_CHANGED_SOURCE
~~~

The executing runtime supplies the audit process key. Airflow task execution
uses the DAG ID, task ID, and DAG run ID; another orchestrator can provide its
own process identifier. Generated dbt output includes the project path and
Snowflake query IDs, which identify the generated SQL and target write for a
specific execution.

### Execution-Level Audit

The execution audit event links the source file, generated dbt invocation, and
Snowflake work performed for one table load.

| Field | Source | Purpose |
| --- | --- | --- |
| Load identifier | Airflow DAG/task/run or dbt invocation ID | Correlates target rows and task logs to one execution. |
| Specification ID and path | TMS loader | Identifies the source-controlled load definition. |
| Source file and checksum | Input-file lifecycle | Identifies the exact CSV delivered for processing. |
| Target database, schema, and table | Resolved dbt profile and spec | Identifies the destination relation. |
| Started and ended timestamps | Loader and orchestration runtime | Measures execution duration. |
| Result and failure detail | TMS/dbt result | Distinguishes successful, validation-failed, and execution-failed runs. |
| Row counts | Seed/source/target execution result | Supports reconciliation between input and written rows. |
| Snowflake query IDs and query tag | dbt adapter result and profile | Links the execution to Snowflake query history. |

The existing target audit columns and task output provide the record-level and
runtime evidence. A persistent job-audit relation uses the execution-level
fields when `control_data.job` is configured for a load.

## Adding a Dataset

1. Add the CSV under data/reference_data/core or data/reference_data/mapping.
2. Create a concrete YAML spec extending the matching abstract spec.
3. Declare its business key, typed fields, validation rules, and parent-key
   lookups.
4. Add load_core and, where applicable, load_mapping to the relevant Airflow
   configuration.
5. Add parent CORE dependencies for foreign-key lookups.
6. Run 'tms parse', then execute the load in a non-production environment.
7. Verify the source view, validation guard, target count, SCD2 flags, and
   resolved foreign keys.

## Verification Queries

Current-row uniqueness:

~~~sql
select
    COUNTRY_CODE,
    count(*) as current_row_count
from <DATABASE>.CORE.COUNTRY
where IS_CURRENT_FLAG = 'Y'
  and IS_DELETED_FLAG = 'N'
group by COUNTRY_CODE
having count(*) > 1;
~~~

Mapping-to-Core resolution:

~~~sql
select
    mapping.SOURCE_SYSTEM,
    mapping.SOURCE_CODE,
    mapping.TARGET_CODE,
    country.COUNTRY_KEY,
    country.COUNTRY_CODE
from <REFERENCE_DATABASE>.MAPPING.COUNTRY as mapping
left join <REFERENCE_DATABASE>.CORE.COUNTRY as country
    on country.COUNTRY_CODE = mapping.TARGET_CODE
   and country.IS_CURRENT_FLAG = 'Y'
   and country.IS_DELETED_FLAG = 'N'
where mapping.IS_CURRENT_FLAG = 'Y'
  and mapping.IS_DELETED_FLAG = 'N';
~~~
