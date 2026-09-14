# SCD2 Derived

`scd2_derived` is for source-to-target models where the source system provides
business-effective dates, but does not provide final SCD2 control columns.

TMS derives these target columns:

- `IS_CURRENT_FLAG`
- `IS_DELETED_FLAG`
- `VALID_FROM_DATETIME`
- `VALID_TO_DATETIME`
- `BUSINESS_DATA_HASH`
- audit columns

Use this when the source has dates such as `UPDATED_DATETIME`,
`CREATED_DATETIME`, `DATE_LAST_MAINT`, `EFFECTIVE_FROM_DATETIME`, or another
timestamp that should drive target history.

## Bronze, Silver, Gold

Think about `scd2_derived` in three layers:

- Bronze is raw source data. It can be one source table or a join across many
  source tables.
- Silver is the source query output used by TMS. It should produce clean target
  business columns plus source-effective date inputs.
- Gold is the final target table. TMS adds SCD2 metadata and maintains validity
  windows.

Example:

```text
Bronze source
  RAW.CUSTOMER
  RAW.CUSTOMER_ACCOUNT

Silver source query row
  CUSTOMER_ID = C001
  ACCOUNT_ID = A100
  CUSTOMER_STATUS_CODE = ACTIVE
  CUSTOMER_NAME = Ada Example
  CREATED_DATETIME = 2023-01-01
  UPDATED_DATETIME = 2024-06-25

Gold target row
  CUSTOMER_ID = C001
  ACCOUNT_ID = A100
  CUSTOMER_STATUS_CODE = ACTIVE
  CUSTOMER_NAME = Ada Example
  VALID_FROM_DATETIME = 2024-06-25
  VALID_TO_DATETIME = 9999-12-31 23:59:59
  IS_CURRENT_FLAG = Y
  IS_DELETED_FLAG = N
```

## Minimum YAML Shape

```yaml
control_data:
  materialisation_type: table
  change_type: scd2_derived
  failure_mode: fail_load
  staging_schema: INTERMEDIATE

  business_key:
    fields:
      - CUSTOMER_ID
      - ACCOUNT_ID

  business_data_hash:
    business_data_hash_mode: include
    fields:
      - CUSTOMER_STATUS_CODE
      - CUSTOMER_NAME
      - DATE_OF_BIRTH
      - EMAIL_ADDRESS
      - CREATED_DATETIME
      - UPDATED_DATETIME

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
        - CUSTOMER_ID
        - ACCOUNT_ID
        - VALID_FROM_DATETIME
      order_by:
        - column: UPDATED_DATETIME
          direction: desc
          nulls: last
```

## Option Reference

`change_type: scd2_derived`

TMS generates SCD2 metadata from source-effective fields. This is different from
`scd2_auto`, which uses load time as `VALID_FROM_DATETIME`, and different from
`scd2_manual`, where the source already supplies final SCD2 control columns.

`business_key.fields`

The identity of the thing being historised. Choose the smallest set of fields
that uniquely identifies one logical target entity.

```yaml
business_key:
  fields:
    - CUSTOMER_ID
    - ACCOUNT_ID
```

`business_data_hash.fields`

The business columns that should create a new version when they change. Do not
include generated SCD2 columns or audit columns.

```yaml
business_data_hash:
  business_data_hash_mode: include
  fields:
    - CUSTOMER_STATUS_CODE
    - CUSTOMER_NAME
    - EMAIL_ADDRESS
    - UPDATED_DATETIME
```

`valid_from_datetime.expression`

The SQL expression used to derive `VALID_FROM_DATETIME`.

```yaml
valid_from_datetime:
  expression: coalesce(UPDATED_DATETIME, CREATED_DATETIME)
```

If `UPDATED_DATETIME` exists, it starts the target version. If it is null,
`CREATED_DATETIME` starts the version.

`valid_to_datetime.mode: next_valid_from`

The end of each version is calculated from the next version for the same
business key.

`valid_to_datetime.offset`

The gap between one version ending and the next version starting.

```yaml
offset:
  unit: nanosecond
  value: -1
```

Example:

```text
Version A VALID_FROM_DATETIME = 2024-06-25 00:00:00.000000000
Version B VALID_FROM_DATETIME = 2025-01-15 00:00:00.000000000

Version A VALID_TO_DATETIME = 2025-01-14 23:59:59.999999999
Version B VALID_TO_DATETIME = 9999-12-31 23:59:59
```

`current_flag.mode: latest_per_business_key`

The latest version by `VALID_FROM_DATETIME` for each business key gets
`IS_CURRENT_FLAG = Y`. Older versions get `N`.

`deleted_flag.mode: fixed`

For derived SCD2, the source query normally returns active source records.
Missing-from-source deletion is not part of this mode. Use a fixed delete flag:

```yaml
deleted_flag:
  mode: fixed
  value: "N"
```

`derivation_scope: affected_keys`

TMS rebuilds windows only for business keys present in the current source query.
This avoids recalculating the full target table every run.

`validation_scope: affected_window`

TMS validates only the rebuilt window for changed keys. This assumes old
untouched target history was already valid when loaded.

`window_strategy: previous_and_next`

TMS considers adjacent previous and next versions when recalculating an affected
window. This matters when inserting a source-effective row between two existing
versions.

`deduplicate`

Defines what to keep when the source query produces more than one row for the
same business key and effective date.

```yaml
deduplicate:
  partition_by:
    - CUSTOMER_ID
    - ACCOUNT_ID
    - VALID_FROM_DATETIME
  order_by:
    - column: UPDATED_DATETIME
      direction: desc
      nulls: last
```

## Example 1: Initial Derived Version

Silver input:

```text
CUSTOMER_ID = C001
ACCOUNT_ID = A100
CUSTOMER_NAME = Ada Example
CREATED_DATETIME = 2023-01-01
UPDATED_DATETIME = 2024-06-25
```

Gold result:

```text
CUSTOMER_ID = C001
ACCOUNT_ID = A100
CUSTOMER_NAME = Ada Example
VALID_FROM_DATETIME = 2024-06-25
VALID_TO_DATETIME = 9999-12-31 23:59:59
IS_CURRENT_FLAG = Y
IS_DELETED_FLAG = N
```

Why: `VALID_FROM_DATETIME` comes from `UPDATED_DATETIME`, and there is no later
version yet.

## Example 2: Rerun With Same Source Data

Existing gold row:

```text
CUSTOMER_ID = C001
ACCOUNT_ID = A100
CUSTOMER_NAME = Ada Example
VALID_FROM_DATETIME = 2024-06-25
IS_CURRENT_FLAG = Y
```

Incoming silver row:

```text
CUSTOMER_ID = C001
ACCOUNT_ID = A100
CUSTOMER_NAME = Ada Example
UPDATED_DATETIME = 2024-06-25
```

Expected result: no new version.

Why: the same business key, same `VALID_FROM_DATETIME`, same business hash, and
same delete flag already exist.

## Example 3: Forward Change

Existing gold row:

```text
CUSTOMER_NAME = Ada Example
VALID_FROM_DATETIME = 2024-06-25
VALID_TO_DATETIME = 9999-12-31 23:59:59
IS_CURRENT_FLAG = Y
```

Incoming silver row:

```text
CUSTOMER_NAME = Ada Example Updated
UPDATED_DATETIME = 2025-01-15
```

Expected gold result:

```text
CUSTOMER_NAME = Ada Example
VALID_FROM_DATETIME = 2024-06-25
VALID_TO_DATETIME = 2025-01-14 23:59:59.999999999
IS_CURRENT_FLAG = N

CUSTOMER_NAME = Ada Example Updated
VALID_FROM_DATETIME = 2025-01-15
VALID_TO_DATETIME = 9999-12-31 23:59:59
IS_CURRENT_FLAG = Y
```

Why: the new source-effective date starts a later version. TMS closes the old
row one nanosecond before the new row starts.

## Example 4: Historical Backfill Between Versions

Existing gold rows:

```text
CUSTOMER_STATUS_CODE = PROSPECT
VALID_FROM_DATETIME = 2023-01-01
VALID_TO_DATETIME = 2024-06-24 23:59:59.999999999

CUSTOMER_STATUS_CODE = ACTIVE
VALID_FROM_DATETIME = 2024-06-25
VALID_TO_DATETIME = 9999-12-31 23:59:59
```

Incoming silver row:

```text
CUSTOMER_STATUS_CODE = PENDING
UPDATED_DATETIME = 2024-01-01
```

Expected gold result:

```text
CUSTOMER_STATUS_CODE = PROSPECT
VALID_FROM_DATETIME = 2023-01-01
VALID_TO_DATETIME = 2023-12-31 23:59:59.999999999

CUSTOMER_STATUS_CODE = PENDING
VALID_FROM_DATETIME = 2024-01-01
VALID_TO_DATETIME = 2024-06-24 23:59:59.999999999

CUSTOMER_STATUS_CODE = ACTIVE
VALID_FROM_DATETIME = 2024-06-25
VALID_TO_DATETIME = 9999-12-31 23:59:59
```

Why: `window_strategy: previous_and_next` means TMS recalculates the local
window around the inserted effective date.

## Example 5: Same Effective Date Correction

Existing gold row:

```text
EMAIL_ADDRESS = old@example.com
VALID_FROM_DATETIME = 2024-06-25
```

Incoming silver row:

```text
EMAIL_ADDRESS = corrected@example.com
UPDATED_DATETIME = 2024-06-25
```

Expected result: the `2024-06-25` version is replaced for the same business key
and same valid-from date.

Why: `scd2_derived` compares incoming data to the existing version with the same
business key and same `VALID_FROM_DATETIME`. If the business hash changed, the
version is corrected.

## Example 6: Multiple Source Rows For Same Effective Date

Incoming silver rows:

```text
CUSTOMER_ID = C001
ACCOUNT_ID = A100
UPDATED_DATETIME = 2024-06-25
CUSTOMER_NAME = Ada Old

CUSTOMER_ID = C001
ACCOUNT_ID = A100
UPDATED_DATETIME = 2024-06-25
CUSTOMER_NAME = Ada New
```

With this config:

```yaml
deduplicate:
  partition_by:
    - CUSTOMER_ID
    - ACCOUNT_ID
    - VALID_FROM_DATETIME
  order_by:
    - column: UPDATED_DATETIME
      direction: desc
      nulls: last
```

Expected result: TMS keeps one row for that business key and effective date.

If two rows are still tied after the configured ordering, add another
deterministic `order_by` column.

## Example 7: Null Updated Date

Incoming silver row:

```text
CUSTOMER_ID = C001
ACCOUNT_ID = A100
CUSTOMER_NAME = Ada Example
CREATED_DATETIME = 2023-01-01
UPDATED_DATETIME = null
```

With this config:

```yaml
valid_from_datetime:
  expression: coalesce(UPDATED_DATETIME, CREATED_DATETIME)
```

Expected result:

```text
VALID_FROM_DATETIME = 2023-01-01
```

Why: `UPDATED_DATETIME` is null, so the fallback `CREATED_DATETIME` is used.

## Performance Notes

`scd2_derived` is designed to avoid full-history recalculation on every run:

- Incoming source rows identify affected business keys.
- TMS pulls existing target rows for only those keys.
- TMS unions incoming rows with existing rows for those keys.
- TMS recalculates valid-from and valid-to windows for that affected set.
- TMS validates the affected window.
- dbt `delete+insert` replaces rows for the affected business keys.

This is useful for large customer, account, balance, transaction summary, or
card models where only a subset of keys changes daily.

## Validation Query Pattern

Use this shape after a test run:

```sql
select
    CUSTOMER_ID,
    ACCOUNT_ID,
    CUSTOMER_STATUS_CODE,
    CUSTOMER_NAME,
    VALID_FROM_DATETIME,
    VALID_TO_DATETIME,
    IS_CURRENT_FLAG,
    IS_DELETED_FLAG,
    BUSINESS_DATA_HASH
from <database>.<schema>.<target_table>
where CUSTOMER_ID = 'C001'
  and ACCOUNT_ID = 'A100'
order by VALID_FROM_DATETIME;
```

## When Not To Use scd2_derived

Do not use `scd2_derived` when:

- The source already provides final SCD2 columns. Use `scd2_manual`.
- You want load-time-driven SCD2 snapshots. Use `scd2_auto`.
- The source does not have a reliable effective-date input.
- The source query cannot produce a stable business key.

