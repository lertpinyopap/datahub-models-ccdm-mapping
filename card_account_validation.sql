Replace `SAS_MIGRATION_WORKSPACE` if your Card Account target uses a different database.

Initial-load reconciliation — should return **zero rows**:

```sql
with card_customer as (
    select
        customer_id,
        card_customer_business_key
    from SAS_MIGRATION_WORKSPACE.CORE.CARD_CUSTOMER
    qualify row_number() over (
        partition by customer_id
        order by audit_last_changed_datetime desc nulls last,
                 audit_created_datetime desc nulls last
    ) = 1
),
expected_accounts as (
    select
        c.card_customer_business_key,
        cast(a.ambs_acct as varchar) as agreement_id
    from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT as a
    inner join card_customer as c
        on c.customer_id = a.ambs_cust_nbr
    where a.ambs_curr_code is null
       or lpad(cast(a.ambs_curr_code as varchar), 3, '0') <> '000'
)
select
    e.card_customer_business_key,
    e.agreement_id
from expected_accounts as e
left join SAS_MIGRATION_WORKSPACE.CORE.CARD_ACCOUNT as ca
    on ca.card_customer_business_key = e.card_customer_business_key
   and ca.agreement_id = e.agreement_id
   and ca.is_current_flag = 'Y'
where ca.agreement_id is null
order by 1, 2;
```

SCD2 integrity check — should return **zero rows**:

```sql
with history as (
    select
        card_customer_business_key,
        agreement_id,
        valid_from_datetime,
        valid_to_datetime,
        is_current_flag,
        lead(valid_from_datetime) over (
            partition by card_customer_business_key, agreement_id
            order by valid_from_datetime
        ) as next_valid_from_datetime
    from SAS_MIGRATION_WORKSPACE.CORE.CARD_ACCOUNT
)
select *
from history
where valid_to_datetime <= valid_from_datetime
   or (
        next_valid_from_datetime is not null
        and valid_to_datetime <> dateadd(nanosecond, -1, next_valid_from_datetime)
      )
   or (
        is_current_flag = 'Y'
        and valid_to_datetime < cast('9999-12-30' as timestamp_ltz)
      );
```

Before an incremental run, capture its watermark:

```sql
select
    pipeline_name,
    source_relation,
    last_source_timestamp,
    updated_at,
    updated_by
from SAS_MIGRATION_WORKSPACE.METADATA.TMS_BOOKMARK
where pipeline_name = 'CARD_ACCOUNT_INCREMENTAL'
  and source_relation =
      'DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT';
```

Use that `LAST_SOURCE_TIMESTAMP` as `from_ts` in this incremental validation. Set `to_ts` to the source maximum recorded before the run. It should return only rows successfully represented in Card Account; `MISSING_CARD_ACCOUNT` or `MISSING_PRODUCT_MAPPING` need investigation.

```sql
set from_ts = '2026-09-14 00:00:00';
set to_ts   = '2026-09-14 12:00:00';

with changed_source as (
    select
        a.ambs_cust_nbr as customer_id,
        cast(a.ambs_acct as varchar) as agreement_id,
        cast(a.ambs_org as varchar) || cast(a.ambs_logo as varchar) as product_source_code,
        a.airflow_dag_time
    from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT as a
    where a.airflow_dag_time > $from_ts
      and a.airflow_dag_time <= $to_ts
      and (
          a.ambs_curr_code is null
          or lpad(cast(a.ambs_curr_code as varchar), 3, '0') <> '000'
      )
),
card_customer as (
    select customer_id, card_customer_business_key
    from SAS_MIGRATION_WORKSPACE.CORE.CARD_CUSTOMER
    qualify row_number() over (
        partition by customer_id
        order by audit_last_changed_datetime desc nulls last,
                 audit_created_datetime desc nulls last
    ) = 1
),
product_mapping as (
    select
        mapping.source_code,
        product.product_key
    from NONPROD_REFERENCE.MAPPING.PRODUCT as mapping
    left join NONPROD_REFERENCE.CORE.PRODUCT as product
        on product.product_code = mapping.target_code
       and coalesce(trim(product.is_deleted_flag), 'N') <> 'Y'
    where mapping.source_system = 'V10'
      and coalesce(trim(mapping.is_deleted_flag), 'N') <> 'Y'
)
select
    s.customer_id,
    s.agreement_id,
    s.product_source_code,
    s.airflow_dag_time,
    case
        when c.card_customer_business_key is null then 'MISSING_CARD_CUSTOMER'
        when pm.product_key is null then 'MISSING_PRODUCT_MAPPING'
        when ca.agreement_id is null then 'MISSING_CARD_ACCOUNT'
        else 'LOADED'
    end as validation_status
from changed_source as s
left join card_customer as c
    on c.customer_id = s.customer_id
left join product_mapping as pm
    on pm.source_code = s.product_source_code
left join SAS_MIGRATION_WORKSPACE.CORE.CARD_ACCOUNT as ca
    on ca.card_customer_business_key = c.card_customer_business_key
   and ca.agreement_id = s.agreement_id
   and ca.is_current_flag = 'Y'
order by validation_status, s.airflow_dag_time, s.agreement_id;
```

After the incremental run, confirm the bookmark advanced to the source watermark with the bookmark query above.









Use this to validate each account’s historical SCD2 timeline after the historical load. Replace `YOUR_DATABASE`.

```sql
with history as (
    select
        CARD_CUSTOMER_BUSINESS_KEY,
        AGREEMENT_ID,
        CARD_ACCOUNT_KEY,
        VALID_FROM_DATETIME,
        VALID_TO_DATETIME,
        IS_CURRENT_FLAG,
        lag(VALID_TO_DATETIME) over (
            partition by CARD_CUSTOMER_BUSINESS_KEY, AGREEMENT_ID
            order by VALID_FROM_DATETIME
        ) as PREVIOUS_VALID_TO_DATETIME,
        lead(VALID_FROM_DATETIME) over (
            partition by CARD_CUSTOMER_BUSINESS_KEY, AGREEMENT_ID
            order by VALID_FROM_DATETIME
        ) as NEXT_VALID_FROM_DATETIME
    from YOUR_DATABASE.CORE.CARD_ACCOUNT
)
select
    CARD_CUSTOMER_BUSINESS_KEY,
    AGREEMENT_ID,
    CARD_ACCOUNT_KEY,
    VALID_FROM_DATETIME,
    VALID_TO_DATETIME,
    IS_CURRENT_FLAG,
    case
        when VALID_TO_DATETIME < VALID_FROM_DATETIME
            then 'INVALID_RANGE'
        when PREVIOUS_VALID_TO_DATETIME > VALID_FROM_DATETIME
            then 'OVERLAPPING_VERSION'
        when IS_CURRENT_FLAG = 'Y' and VALID_TO_DATETIME is not null
            then 'CURRENT_ROW_HAS_END_DATE'
        when IS_CURRENT_FLAG = 'N' and VALID_TO_DATETIME is null
            then 'HISTORICAL_ROW_HAS_NO_END_DATE'
    end as ISSUE
from history
where VALID_TO_DATETIME < VALID_FROM_DATETIME
   or PREVIOUS_VALID_TO_DATETIME > VALID_FROM_DATETIME
   or (IS_CURRENT_FLAG = 'Y' and VALID_TO_DATETIME is not null)
   or (IS_CURRENT_FLAG = 'N' and VALID_TO_DATETIME is null)
order by CARD_CUSTOMER_BUSINESS_KEY, AGREEMENT_ID, VALID_FROM_DATETIME;
```

A successful result should return zero rows.

To inspect the version history for one account:

```sql
select
    CARD_CUSTOMER_BUSINESS_KEY,
    AGREEMENT_ID,
    CARD_ACCOUNT_KEY,
    VALID_FROM_DATETIME,
    VALID_TO_DATETIME,
    IS_CURRENT_FLAG,
    PRODUCT_KEY,
    CREDIT_LIMIT_AMOUNT,
    CASH_LIMIT_AMOUNT,
    CLOSURE_REQUEST_DATE,
    IS_ACTIVE_IN_SOURCE_FLAG
from YOUR_DATABASE.CORE.CARD_ACCOUNT
where AGREEMENT_ID = '<ACCOUNT_NUMBER>'
order by VALID_FROM_DATETIME;
```



select
    AMBS_CUST_NBR,
    AMBS_ACCT,
    AMBS_DATE_OPENED,
    AMBS_DATE_LAST_MAINT,
    AIRFLOW_DAG_TIME,
    AMBS_CRLIM as CREDIT_LIMIT_AMOUNT,
    AMBS_CASH_CRLIM as CASH_LIMIT_AMOUNT,
    AMBS_DATE_CLOSED,
    AMBS_CURR_CODE
from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT
where AMBS_CUST_NBR = '<CUSTOMER_ID>'
  and AMBS_ACCT = '0005039468177827600'
order by
    AMBS_DATE_LAST_MAINT,
    AIRFLOW_DAG_TIME;