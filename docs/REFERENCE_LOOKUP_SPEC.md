# Reference Lookup Specification

This document describes the reusable dbt reference lookup macros used in this
repo.

The main objective is to accept a source code plus mapping type, resolve the
governed Core business value through the mapping table, and then return the
current effective Core record.

Two runtime dbt macros support that pattern:

- `reference_lookup_mapping`
- `reference_lookup_core`

`reference_lookup_mapping` is the main cross-system translation macro.
`reference_lookup_core` is the companion macro for direct Core-to-Core lookups
where the incoming value is already a Core business code.

## Macro Summary

### `reference_lookup_mapping`

Use this when the incoming code comes from a source system and must first be
translated through `MAPPING.<TYPE>`.

Input pattern:

```text
source_system + source_code + mapping type
```

Resolution pattern:

```text
source_system + source_code
  -> MAPPING.<TYPE>.TARGET_CODE
  -> CORE.<TYPE>.<TYPE>_CODE
  -> current effective CORE.<TYPE> row
```

Runtime macro:

- `../macros/reference_lookup_mapping.sql`

TMS bridge macro:

- `../macros/reference_lookup_mapping_macros.py`

### `reference_lookup_core`

Use this when the incoming value is already the Core business code and no
mapping table lookup is required.

Input pattern:

```text
core business code + reference type
```

Resolution pattern:

```text
source_code
  -> CORE.<TYPE>.<TYPE>_CODE
  -> current effective CORE.<TYPE> row
```

Runtime macro:

- `../macros/reference_lookup_core.sql`

TMS bridge macro:

- `../macros/reference_lookup_core_macros.py`

## Supported Behavior

Both macros support:

- source value resolution
- effective-dated lookup using `VALID_FROM_DATETIME` and `VALID_TO_DATETIME`
- current record prioritisation using `IS_CURRENT_FLAG`
- deleted-record exclusion using `IS_DELETED_FLAG`
- returning the full Core row through `ref.*`
- returning a chosen value column through `output_column`

Both macros default the effective timestamp to:

```sql
current_timestamp()
```

This can be overridden with `as_of_date_expr`.

## Example Data Shape

Core reference data stores the canonical record.

Example:

```text
CORE.COUNTRY
COUNTRY_KEY | COUNTRY_CODE | COUNTRY_DESCRIPTION | IS_CURRENT_FLAG
abc123      | AU           | Australia           | Y
```

Mapping reference data stores translation from source-system values to Core
business codes.

Example:

```text
MAPPING.COUNTRY
SOURCE_SYSTEM | SOURCE_CODE | TARGET_CODE
V10           | AUS         | AU
VN            | AU          | AU
```

Mapping files do not store generated Core keys. They store `TARGET_CODE`, which
is then resolved to the current Core row at runtime.

## Usage Examples

### Mapping Lookup Example

Use `reference_lookup_mapping` when the incoming code is a source-system value.

```sql
select
    src.source_system,
    src.source_code,
    ref.*
from (
    select 'V10' as source_system, 'AUS' as source_code
) as src
{{ reference_lookup_mapping(
    reference_type='COUNTRY',
    source_system='V10',
    ref_alias='ref',
    output_column='COUNTRY_KEY',
    source_code_expression='src.source_code'
) }}
```

Expected resolution:

```text
V10 + AUS -> TARGET_CODE AU -> current CORE.COUNTRY row
```

### Direct Core Lookup Example

Use `reference_lookup_core` when the incoming value is already the Core code.

```sql
select
    src.source_code,
    ref.*
from (
    select 'AU' as source_code
) as src
{{ reference_lookup_core(
    reference_type='COUNTRY',
    ref_alias='ref',
    output_column='COUNTRY_KEY',
    source_code_expression='src.source_code'
) }}
```

Expected resolution:

```text
AU -> current CORE.COUNTRY row
```

## Example SQL In This Repo

These example SQL files demonstrate direct macro usage for local unit tests:

Core lookup examples:

- `../unit_tests/examples/reference_lookup/sample_reference_lookup_core_country.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_core_currency.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_core_financial_institution.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_core_brand.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_core_product.sql`

Mapping lookup examples:

- `../unit_tests/examples/reference_lookup/sample_reference_lookup_mapping_country.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_mapping_currency.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_mapping_financial_institution.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_mapping_brand.sql`
- `../unit_tests/examples/reference_lookup/sample_reference_lookup_mapping_product.sql`

Mapping examples return the test input `source_system`, the test input
`source_code`, and `ref.*` from the resolved current Core record. Core examples
return the test input `source_code` and `ref.*`; Core lookups do not require a
source-system value.

## Local Unit Tests

Local-only unit tests validate that the example SQL files use the macros
consistently.

Test file:

- `../unit_tests/test_reference_lookup_macros.py`

Run locally:

```bash
python -m pytest
```

These tests are intentionally not in dbt's `tests/` folder, so they do not run
in dbt or Airflow.

## Implementation Coverage

The repository implements the lookup objective as follows:

- Macro successfully resolves source values:
  `reference_lookup_mapping`
- Effective dating supported:
  `VALID_FROM_DATETIME` / `VALID_TO_DATETIME` filters plus `as_of_date_expr`
- Current record retrieval supported:
  `IS_CURRENT_FLAG` ordering and `row_number() = 1`
- Standard documentation completed:
  this file, example SQL files, and README unit-test instructions

## Usage Rules

`reference_lookup_mapping` is used for source-system translation.

`reference_lookup_core` is used when the incoming value already matches the
Core business code and the current Core record or a selected Core key is needed.
