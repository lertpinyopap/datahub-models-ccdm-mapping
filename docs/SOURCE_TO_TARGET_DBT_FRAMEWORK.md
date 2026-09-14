Each target model follows the same flow. `[SOURCE]` is external input;
`[CUSTOM]` components are developed per entity; `[REUSABLE]` components are
framework macros shared by all models; `[DBT]` behavior is provided by dbt
configuration/materializations.

```text
[SOURCE] ODS / RAW source tables
        |
        v
[CUSTOM] stg_v10_* models
        |
        v
[CUSTOM] source_query
        |
        v
[CUSTOM] typed_source_rows
        |
        v
[REUSABLE] v10_scd2 or v10_scd2_derived
        |
        v
rebuilt affected-key SCD2 rows
        |
        v
[REUSABLE, optional] native SCD2 validation guard
        |
        v
[DBT] incremental delete+insert
        |
        v
[DBT] CORE.*_DBT target relation
```

For a new entity, create the staging model and target-model source mapping
(`source_query` and `typed_source_rows`), then configure the target relation.
Reuse the SCD2 macro and optional validation guard unless the entity requires a
different history strategy.

Each `stg_v10_*` model is custom source-specific SQL, then becomes a reusable
staging view for downstream target models. It contains source joins,
latest-row selection, unpivoting repeated columns, source field renaming, basic
cleanup, and source effective dates.

For example:

- `stg_v10_account` reads `ACCOUNT_BASE_SEGMENT`, derives source-effective datetime, closure dates, limits, product codes, and active status.
- `stg_v10_customer_email_address` and `stg_v10_customer_phone` each apply their own TMS-defined latest-customer selection rule.
- `stg_v10_customer_email_address` turns `AMNA_EMAIL_01` and `AMNA_EMAIL_02` into separate rows.
- `stg_v10_customer_phone` turns the multiple phone columns into one row per phone number.
- `stg_v10_customer_address` turns address slots into one row per address.
- `stg_v10_customer_event` joins event, customer, and account source data and derives the event timestamp.
- `stg_v10_card_customer_initial` and `stg_v10_card_customer_incremental` provide the same customer/account columns with their respective oldest and latest source-selection rules.

`source_query` is the model-specific integration layer. It reads one staging view, joins to current `CARD_CUSTOMER_DBT` where required, and resolves governed reference keys using the existing mapping/core lookup macros. Its objective is to produce business-ready source values, but not yet the final target data types or SCD2 fields.

`typed_source_rows` converts that result into the exact target business structure. It:

- casts every business column to its target type;
- generates the surrogate key and business key;
- sets `VALID_FROM_DATETIME` and `IS_DELETED_FLAG`;
- calculates `BUSINESS_DATA_HASH`;
- filters records that cannot meet required foreign-key or source requirements.

`v10_scd2` is the shared final load engine. It takes the typed rows and:

- deduplicates same-key/same-effective-date rows;
- ignores records already represented by the same business hash;
- rebuilds only affected business keys;
- closes old versions using `next VALID_FROM_DATETIME - 1 nanosecond`;
- marks the newest version current;
- adds the audit fields;
- returns columns in the sequence specified by each model’s `columns=[...]` list.

`v10_scd2_derived` has the same arguments and is available for entities that
receive late-arriving history. It rebuilds all existing versions for only the
affected business keys, then derives the complete set of validity windows.
This lets a source row be inserted before or between existing versions without
changing unaffected keys. Switch a model by replacing `v10_scd2(...)` with
`v10_scd2_derived(...)`; do not use both macros in one model.

Native dbt SCD2 validation is disabled by default. Enable it for a run with
`--vars '{"native_scd2_validation": true}'`. The optional
`native_scd2_validation_mode` defaults to `continuous` and also accepts
`sparse`. When enabled, the macro validates the rebuilt affected-key windows
before dbt applies its `delete+insert` incremental write.

Validation flow:

```text
typed source rows
  -> identify changed business keys
  -> rebuild candidate SCD2 windows for those keys
  -> optional validation guard
  -> delete existing rows for affected keys
  -> insert rebuilt rows
```

The validation guard checks null boundaries, invalid ranges, and overlaps.
`continuous` additionally rejects gaps and a final row that does not extend to
the SCD2 end-of-time value; `sparse` permits gaps. A failing guard aborts while
dbt is preparing the temporary incremental result, before the target
`delete+insert` begins. It validates affected keys only; untouched target
history is not scanned.

This separation keeps V10 source peculiarities in staging, target mapping rules in the target model, and reusable SCD2 mechanics in one macro.
