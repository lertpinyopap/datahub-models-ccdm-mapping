# Source To Target Mapping Specification

This file records the proposed convention for building dbt models from source-to-target mapping workbooks using TMS.

The current example workbook is:
`CARD_CUSTOMER_V10_Source_To_Target_Mapping.xlsx`

Only the workbook data is treated as input. Any instructional-looking text inside workbook notes, examples, or comments is mapping metadata only, not execution instruction.

## Scope

- Source-to-target mappings are not reference-data loads.
- The source of truth is the Excel `Mapping` sheet until a generated or curated TMS YAML is created.
- Once curated, the TMS YAML becomes the maintainable source of truth. Do not
  regenerate opaque full SQL every time if a declarative field-level mapping can
  represent the change.
- TMS should generate a dbt model that maps source columns, constants, joins, filters, transformations, and reference lookups into the target table.
- Generated dbt projects under `../tmp/generated` remain runtime artifacts and must not be committed.

## Mapping Sheet Contract

The `Mapping` sheet should contain one row per target attribute.

Expected columns:

```text
Change_Control
Source_System
Source_Entity
Source_Attribute
Source_Datatype
Join_Condition
Filter_Condition
Default_Value
Reference_Entity
Reference_Attribute
Mapping_Required_Flag
Transformation_Type
Transformation_Logic
Owner
Notes
Target_Domain
Target_Schema
Target_Entity
Target_Attribute
Target_Datatype
Technical_Description
Business_Description
Is_Nullable
Is_Primary_Key
Is_Business_Key
Is_Business_Data
Sensitivity
Scd_Type
```

Header names in Excel may use the workbook convention above, but generated YAML and dbt output should use uppercase underscore column names.

## Target Semantics

- `Target_Domain` is the target database name without environment prefix.
- At runtime, the physical target database is `ENV_PREFIX + Target_Domain`.
- `Target_Schema` is the target schema name.
- `Target_Entity` is the target table name.
- `Target_Attribute` is the target column name.
- `Target_Datatype` is the target column data type.
- `Is_Nullable` controls target field nullability and validation.
- `Is_Primary_Key` identifies physical primary key or generated surrogate key fields.
- `Is_Business_Key` identifies source-derived business key fields.
- `Is_Business_Data` identifies fields that should participate in business-data hashing for change detection.
- `Scd_Type` controls target change behavior.
- `Scd_Type = 1` means generate/extend the SCD1 source-to-target abstract spec.
- `Scd_Type = 2` normally means generate/extend the manual SCD2 source-to-target abstract spec when the source query supplies SCD2 control columns.
- Use the automatic SCD2 source-to-target abstract only when TMS should generate validity windows from load/change detection instead of taking them from source.
- For source systems like VISION where the source provides effective-date inputs
  but not final SCD2 control columns, represent the derivation in YAML using
  `change_type: scd2_derived`.

Current TMS mapping of these flags:

- `Is_Nullable` maps to each target field's `nullable` property.
- `Is_Primary_Key` maps to the generated surrogate key when the primary key field follows the TMS target-key convention, for example `CREDIT_CARD_CUSTOMER_KEY`.
- `Is_Business_Key` maps to `control_data.business_key.fields`.
- `Is_Business_Data` maps to `control_data.business_data_hash.fields`.
- Literal `Default_Value` values map to standalone `field.source.default_value`.
- `Default_Value` values that reference another target field, such as `CUSTOMER_ID`, map to standalone `field.source.default_from_field`.
- Null literal outputs that should always stay null map to `field.source.fixed_value: null`.

Target database naming should be generated as:

```jinja
{{ var("ENV_PREFIX", "") }}{{ target_domain }}
```

For example, `Target_Domain = PAY` and `ENV_PREFIX = NONPROD_` should target `NONPROD_PAY`.

Reference lookups should declare the runtime database prefix directly in YAML,
for example `reference_entity: '{{ var("ENV_PREFIX", "") }}REFERENCE.CORE.CUSTOMER_STATUS'`.
This keeps environment behavior visible in the spec instead of hiding it inside
TMS generator logic.

With the current TMS generator, prefer setting the dbt job/profile database to the resolved physical database, such as `NONPROD_PAY`. A TMS library update is recommended before relying on `target.database: '{{ var("ENV_PREFIX", "") }}PAY'`, because generated dbt model config currently renders database values as quoted strings.

## Source Semantics

- `Source_System` identifies the upstream platform, such as `V10`.
- `Source_Entity` identifies the source relation or logical source path, such as `RAW.VISION.CUSTOMER`.
- `Source_Attribute` identifies one or more source columns used by the mapping.
- `Source_Datatype` records the source data type for validation and documentation.
- `Join_Condition` contributes to the generated source `from` and `join` clauses.
- `Filter_Condition` contributes to the generated source `where` clause.
- `Default_Value` is used when the target value is generated, constant, or copied from another target/source field.

The source query should provide the base source rowset only: source tables,
joins, filters, and simple aliases needed by multiple fields. Field-specific
defaults, copied values, transformations, and reference lookups should stay in
`target.fields[]` so future maintainers can update YAML directly without
reverse-engineering generated SQL.

## Field Expression Precedence

For each target attribute, the generated select expression should use this precedence:

1. `Default_Value`
2. `Transformation_Logic`
3. Reference lookup using `Reference_Entity`, `Reference_Attribute`, and `Mapping_Required_Flag`
4. Direct source column from `Source_Entity.Source_Attribute`

If both `Default_Value` and `Transformation_Logic` are populated, the row should fail validation unless the spec explicitly allows that combination.

## Defaults

`Default_Value` should support these patterns:

- `Sequence`: generate a deterministic surrogate key value according to the TMS target-key convention.
- A target or source attribute name, such as `CUSTOMER_ID`: copy that attribute's value.
- A literal value: render as a quoted SQL literal unless typed otherwise by the generated spec.
- A SQL expression: allowed only when explicitly marked or generated from a trusted workbook rule.

For current TMS-compatible YAML, literal defaults are applied with standalone `source.default_value`. For example, `Default_Value = 'AMID'` becomes `source.default_value: "AMID"` without requiring a dummy source query column. Null outputs that should always be null use `source.fixed_value: null`. Defaults that copy another target field are applied with standalone `source.default_from_field`; for example, `Default_Value = CUSTOMER_ID` becomes `source.default_from_field: CUSTOMER_ID` without requiring a dummy source column.

Use `fixed_value` when the target field is intentionally constant for every row.
For example, an always-null field should be expressed as:

```yaml
- id: EXTERNAL_ID
  source:
    fixed_value: null
```

Use `default_value` when the field has a fallback value. With a `column`, it
means "use the source column first, then this default when the source is null or
blank." Without a `column`, it means "generate this literal value." For example:

```yaml
- id: EXTERNAL_IDENTIFICATION_TYPE
  source:
    default_value: "AMID"
```

Avoid adding dummy columns such as `cast(null as varchar(...))` to
`source.query` only to satisfy target fields. Generated constants, copied
fields, and always-null values should live in `target.fields[].source`.

## Transformations

`Transformation_Type` describes how `Transformation_Logic` should be interpreted.

Recommended supported values:

- `Direct`: map the source attribute directly.
- `Expression`: use `Transformation_Logic` as the target SQL expression.
- `Lookup`: derive a reference code or key through a reference table.
- `Default`: use `Default_Value`.
- `Hash`: generate a hash from business key or business data fields.
- `Sequence`: generate a surrogate key.

`Transformation_Logic` should be SQL-safe and should not include the final `AS Target_Attribute`; the generator should own aliases. Existing workbook values that include `AS <column>` should be normalized before generation.

## Reference Lookup Semantics

Rows with `Reference_Entity`, `Reference_Attribute`, or `Mapping_Required_Flag = Y` describe a dependency on reference data.

Recommended behavior:

- `Reference_Type` is the logical reference set, for example `CUSTOMER_STATUS`, `CURRENCY`, or `COUNTRY`.
- TMS should not own a special declarative `lookup:` block for source-to-target mappings.
- Use the generic field-level `source.macro` mechanism with args, so the consumer repo owns the lookup SQL while TMS only knows how to call a macro.
- The field-level `source.macro` should call `reference_macros.reference_lookup`.
- The lookup flow, when needed outside TMS, is source value -> mapping table `SOURCE_SYSTEM` + `SOURCE_CODE` -> mapping table `TARGET_CODE` -> code/core table `<REFERENCE_TYPE>_CODE` -> code/core table `<REFERENCE_TYPE>_KEY`.
- The output should select the resolved code/core surrogate key when the target attribute ends with `_KEY`.
- For a source value already exposed as a column by the source query, use
  `source_code_column`. TMS resolves this column internally; the spec should not
  need to mention the generated `source_query` alias.
- Use `source_code_expression` only when the lookup input must be derived from
  multiple source columns, such as a `case` expression.

Example:

```yaml
- id: CUSTOMER_STATUS_KEY
  source:
    macro: reference_macros.reference_lookup
    args:
      reference_type: CUSTOMER_STATUS
      source_system: V10
      source_code_expression: |
        case
          when source_query.AMNA_ADD_STATUS != 99 then 'PROF'
          when source_query.AMNA_STATUS = 0 then 'ENAB'
          when source_query.AMNA_STATUS = 1 then 'DISA'
          when source_query.AMNA_STATUS = 2 then 'DELE'
          else 'DQMapping'
        end
      required: true
  data_type: varchar(64)
  nullable: false
```

`Mapping_Required_Flag` maps to `source.args.required`.

For a direct source column, prefer the declarative form:

```yaml
source:
  macro: reference_macros.reference_lookup
  args:
    reference_type: CUSTOMER_CONTACT_PREFERENCE_TYPE
    source_system: V10
    source_code_column: CUSTOMER_CONTACT_PREFERENCE_TYPE_CODE
    required: true
```

The macro internally reads `source_query.CUSTOMER_CONTACT_PREFERENCE_TYPE_CODE`;
that implementation detail does not need to appear in the specification.

- `Mapping_Required_Flag = Y`: generate `required: true`. Missing lookup matches should return `null`, and the generated field should normally be `nullable: false` so TMS validation fails the load or quarantines the row according to `failure_mode`.
- `Mapping_Required_Flag = N`: missing lookup matches may remain `null`, and the generated field should normally be `nullable: true` unless the target contract explicitly requires a value.
- If `Mapping_Required_Flag` conflicts with `Is_Nullable`, prefer the stricter target contract and flag the row for review in generated documentation.

Reference mappings normally follow this repo's naming convention:

```text
reference_type: CUSTOMER_STATUS
mapping table: <reference database>.MAPPING.CUSTOMER_STATUS
code/core table: <reference database>.CORE.CUSTOMER_STATUS
code/core code column: CUSTOMER_STATUS_CODE
code/core key column: CUSTOMER_STATUS_KEY
```

Use `dbt show` against small full-reference lookup models, such as
`full_reference_lookup_currency`, to verify lookup behavior without embedding
the mapping SQL into TMS core generator logic.

## Suggested TMS Shape

Create a source-to-target abstract spec for shared behavior:

```yaml
id: source_to_target_scd1
description: Shared SCD1 source-to-target table mapping pattern.
control_data:
  materialisation_type: table
  change_type: scd1
  failure_mode: fail_load
  staging_schema: INTERMEDIATE
source:
  format: table
target:
  schema: CORE
```

For workbooks where `Scd_Type = 2` and the source provides SCD2 control values,
extend the manual SCD2 abstract:

```yaml
id: source_to_target_scd2_manual
description: Shared manual SCD2 source-to-target table mapping pattern.
control_data:
  materialisation_type: table
  change_type: scd2_manual
  failure_mode: fail_load
  staging_schema: INTERMEDIATE
  scd:
    update_mode: upsert
    update_key:
      fields:
        - VALID_FROM_DATETIME
source:
  format: table
target:
  schema: CORE
```

Manual SCD2 source queries must expose these columns so TMS can validate and
load them:

```text
IS_CURRENT_FLAG
IS_DELETED_FLAG
VALID_FROM_DATETIME
VALID_TO_DATETIME
```

For cases where TMS should derive SCD2 windows automatically, extend the
automatic SCD2 abstract:

```yaml
id: source_to_target_scd2_auto
description: Shared automatic SCD2 source-to-target table mapping pattern.
control_data:
  materialisation_type: table
  change_type: scd2_auto
  failure_mode: fail_load
  staging_schema: INTERMEDIATE
  scd:
    insert_time: '{{ var("insert_time") }}'
    scd2_auto_from_sot: true
    scd2_validation: continuous
source:
  format: table
target:
  schema: CORE
```

Source-derived SCD2 shape:

Use `change_type: scd2_derived` inside each concrete VISION/card style mapping
where the source provides effective-date inputs but not final SCD2 columns. Do
not create a shared abstract until more than one table proves the same config can
be reused.

```yaml
id: source_to_target_scd2_derived
description: Future source-to-target pattern where TMS derives SCD2 control columns from source effective-date inputs.
control_data:
  materialisation_type: table
  change_type: scd2_derived
  failure_mode: fail_load
  staging_schema: INTERMEDIATE
  business_key:
    fields:
      - APPLICATION_NUMBER
      - CUSTOMER_ID
  business_data_hash:
    business_data_hash_mode: include
    fields:
      - CUSTOMER_STATUS_KEY
      - APPLICATION_NUMBER
      - CLV_ID
      - TITLE
      - FIRST_NAME
      - MIDDLE_NAME
      - SURNAME
      - DATE_OF_BIRTH
      - EXTERNAL_ID
      - EXTERNAL_IDENTIFICATION_TYPE
      - CREATED_DATETIME
      - UPDATED_DATETIME
      - IS_ACTIVE_IN_SOURCE_FLAG
  scd:
    derivation_scope: affected_keys
    validation_scope: affected_window
    window_strategy: previous_and_next
    valid_from_datetime:
      expression: coalesce(UPDATED_DATETIME, CREATED_DATETIME)
    valid_to_datetime:
      mode: next_valid_from
      offset:
        unit: nanosecond
        value: -1
      end_of_time: "9999-12-31 23:59:59 +00:00"
    current_flag:
      mode: latest_per_business_key
    deleted_flag:
      mode: fixed
      value: "N"
    deduplicate:
      partition_by:
        - APPLICATION_NUMBER
        - CUSTOMER_ID
        - VALID_FROM_DATETIME
      order_by:
        - column: UPDATED_DATETIME
          direction: desc
          nulls: last
        - column: APPLICATION_NUMBER
          direction: desc
          nulls: last
source:
  format: table
target:
  schema: CORE
```

`derivation_scope: affected_keys` means TMS only rebuilds SCD2 windows for
business keys present in the current source query. `validation_scope:
affected_window` means validation is run against those rebuilt windows, not the
entire historical target table. `window_strategy: previous_and_next` documents
that the derived window must consider the adjacent previous and next versions for
the affected key.

In this future shape, the source query should only expose business/source
columns such as `UPDATED_DATETIME` and `CREATED_DATETIME`. TMS would generate:

```text
VALID_FROM_DATETIME = coalesce(UPDATED_DATETIME, CREATED_DATETIME)
VALID_TO_DATETIME = next VALID_FROM_DATETIME - 1 nanosecond
IS_CURRENT_FLAG = Y for the latest row per business key, otherwise N
IS_DELETED_FLAG = N unless configured otherwise
```

Create a concrete spec per target entity:

```yaml
id: card_customer
extends: source_to_target_scd1
description: Maps V10 customer source data into PAY.CORE.CREDIT_CARD_CUSTOMER.
control_data:
  business_key:
    fields:
      - CUSTOMER_ID
  business_data_hash:
    mode: include
    fields:
      - CUSTOMER_STATUS_KEY
      - APPLICATION_NUMBER
      - CLV_ID
      - TITLE
source:
  format: table
  query: |
    select
      C.AMNA_ADD_STATUS,
      C.AMNA_STATUS,
      C.AMNA_ACCT as CUSTOMER_ID,
      ABS.AMBS_APS_ACCT as APPLICATION_NUMBER,
      ...
    from RAW.VISION.CUSTOMER as C
    join RAW.VISION.CUSTOMER_ACCOUNT as CA
      on C.AMNA_ACCT = CA.AMBX_NA_ACCT
     and C.AMNA_ORG = try_to_number(CA.AMBX_NA_ORG)
    join RAW.VISION.ACCOUNT_BASE_SEGMENT as ABS
      on CA.AMBX_BS_ACCT = ABS.AMBS_ACCT
     and CA.AMBX_BS_ORG = ABS.AMBS_ORG
target:
  id: CREDIT_CARD_CUSTOMER
  # Current-compatible path: set the dbt job database to ENV_PREFIX + PAY.
  # Future TMS enhancement: support dynamic target.database from Target_Domain.
  schema: CORE
  fields:
    - id: CREDIT_CARD_CUSTOMER_KEY
      data_type: varchar(64)
      nullable: false
      generation:
        type: surrogate_key

    - id: CUSTOMER_ID
      source:
        column: AMNA_ACCT
      data_type: varchar(20)
      nullable: false

    - id: CUSTOMER_STATUS_KEY
      source:
        macro: reference_macros.reference_lookup
        args:
          reference_type: CUSTOMER_STATUS
          source_system: V10
          source_code_expression: |
            case
              when source_query.AMNA_ADD_STATUS != 99 then 'PROF'
              when source_query.AMNA_STATUS = 0 then 'ENAB'
              when source_query.AMNA_STATUS = 1 then 'DISA'
              when source_query.AMNA_STATUS = 2 then 'DELE'
              else 'DQMapping'
            end
      data_type: varchar(64)
      nullable: false
```

Repo-specific mapping lookup derivation should use field-level
`source.macro`. This keeps TMS generic while centralising mapping behavior in
`macros/reference_macros.py`.

The `database` and `generation` blocks may require TMS schema and generator
support if they are not already implemented.

## Workbook-To-Spec Generation Rules

- Group rows by `Target_Domain`, `Target_Schema`, and `Target_Entity`.
- Create one generated TMS spec per target entity.
- Create one target field per `Target_Attribute`.
- Convert `Target_Datatype` to the dbt/Snowflake type exactly unless a type normalization rule exists.
- If real source data exceeds the workbook `Target_Datatype`, update the workbook first where possible. A spec may temporarily widen the generated type to keep validation aligned with observed data, but the mismatch must be reviewed with data modelling.
- Convert boolean fields from Excel booleans or `Y`/`N` text into YAML booleans.
- Consolidate repeated source joins into a single base source query.
- Generate source-system reference lookups as field-level
  `target.fields[].source.macro: reference_macros.reference_lookup`.
- Convert `Mapping_Required_Flag` to `source.args.required` for
  `reference_macros.reference_lookup`.
- Apply `Filter_Condition` once at source CTE level when it applies to the full target entity.
- Record `Owner`, `Notes`, `Technical_Description`, `Business_Description`, and `Sensitivity` as metadata where TMS supports metadata; otherwise keep them in generated documentation.
- Fail validation when a target field has no `Source_Attribute`, `Default_Value`, `Transformation_Logic`, or lookup rule unless it is an allowed generated metadata field.

## Validation Expectations

- The workbook `Mapping` sheet must not contain fully blank data rows.
- Target fields must be unique within each target entity.
- A generated target model must have exactly one target entity.
- All rows for the same `Target_Entity` should use the same `Scd_Type`; mixed values should fail generation and be reviewed.
- `Target_Domain`, `Target_Schema`, `Target_Entity`, `Target_Attribute`, and `Target_Datatype` are mandatory.
- `Source_System` should be populated for all source-derived fields.
- `Reference_Entity` and `Reference_Attribute` must both be populated when `Mapping_Required_Flag = Y`.
- Lookup rows must define either `Transformation_Logic` or `Source_Attribute` to produce the lookup value.
- `Is_Primary_Key = true` and `Is_Business_Key = true` should be reviewed carefully; generated surrogate keys should not also be business keys.

## Open Design Items

- Whether TMS should read Excel directly or require an extracted mapping CSV/YAML intermediate.
- Whether `Target_Domain` should become a first-class TMS `target.database` property.
- Whether row-level `Join_Condition` should remain free-form SQL or move to structured join metadata.
