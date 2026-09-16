Use `SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT` below; replace database if needed.

Check duplicate SCD2 version identities:

```sql
select
  payment_instrument_id,
  valid_from_datetime,
  count(*) as row_count
from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT
group by 1, 2
having count(*) > 1
order by 1, 2;
```

Check validity windows for overlaps, gaps, invalid ranges, and an incorrect open-ended row:

```sql
with versions as (
  select
    payment_instrument_id,
    payment_instrument_key,
    valid_from_datetime,
    valid_to_datetime,
    is_current_flag,
    lead(valid_from_datetime) over (
      partition by payment_instrument_id
      order by valid_from_datetime
    ) as next_valid_from_datetime
  from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT
)
select *
from versions
where valid_from_datetime is null
   or valid_to_datetime is null
   or valid_to_datetime <= valid_from_datetime
   or next_valid_from_datetime <= valid_to_datetime
   or (
     next_valid_from_datetime is not null
     and next_valid_from_datetime <> dateadd(nanosecond, 1, valid_to_datetime)
   )
   or (
     next_valid_from_datetime is null
     and valid_to_datetime <> cast('9999-12-31T23:59:59Z' as timestamp_ntz)
   )
order by payment_instrument_id, valid_from_datetime;
```

Check exactly one current version per payment instrument:

```sql
select
  payment_instrument_id,
  count(*) as version_count,
  count_if(is_current_flag = 'Y') as current_version_count
from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT
group by 1
having count_if(is_current_flag = 'Y') <> 1
order by payment_instrument_id;
```

Inspect a particular instrument’s history:

```sql
select
  payment_instrument_id,
  payment_instrument_key,
  payment_instrument_business_key,
  payment_instrument_type_key,
  card_status_key,
  card_fraud_status_key,
  business_data_hash,
  valid_from_datetime,
  valid_to_datetime,
  is_current_flag,
  is_deleted_flag
from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT
where payment_instrument_id = '<PAYMENT_INSTRUMENT_ID>'
order by valid_from_datetime;
```








Use this to validate the raw source value through the same normalization and lookup used by the spec:

```sql
with source_codes as (
  select
    case
      when trim(e.amed_digital_card_type) in ('D', 'T', 'E', 'V')
        then trim(e.amed_digital_card_type)
      else 'PHYS'
    end as lookup_source_code,
    count(*) as source_row_count
  from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.EMBOSSER_RECORD e
  where e.amed_card_nbr is not null
    and trim(e.amed_card_nbr) <> ''
  group by 1
)
select
  s.lookup_source_code,
  s.source_row_count,
  m.target_code,
  c.payment_instrument_type_key,
  case
    when c.payment_instrument_type_key is null then 'MISSING'
    else 'MATCHED'
  end as lookup_status
from source_codes s
left join NONPROD_REFERENCE.MAPPING.PAYMENT_INSTRUMENT_TYPE m
  on m.source_system = 'V10'
 and m.source_code = s.lookup_source_code
 and m.is_current_flag = 'Y'
 and coalesce(m.is_deleted_flag, 'N') <> 'Y'
left join NONPROD_REFERENCE.CORE.PAYMENT_INSTRUMENT_TYPE c
  on c.payment_instrument_type_code = m.target_code
 and c.is_current_flag = 'Y'
 and coalesce(c.is_deleted_flag, 'N') <> 'Y'
order by s.source_row_count desc;
```

To show the actual source records that still fail the lookup:

```sql
with resolved_source as (
  select
    e.amed_card_nbr as payment_instrument_id,
    e.amed_digital_card_type,
    case
      when trim(e.amed_digital_card_type) in ('D', 'T', 'E', 'V')
        then trim(e.amed_digital_card_type)
      else 'PHYS'
    end as lookup_source_code
  from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.EMBOSSER_RECORD e
  where e.amed_card_nbr is not null
    and trim(e.amed_card_nbr) <> ''
)
select
  s.payment_instrument_id,
  s.amed_digital_card_type,
  s.lookup_source_code,
  m.target_code,
  c.payment_instrument_type_key
from resolved_source s
left join NONPROD_REFERENCE.MAPPING.PAYMENT_INSTRUMENT_TYPE m
  on m.source_system = 'V10'
 and m.source_code = s.lookup_source_code
 and m.is_current_flag = 'Y'
 and coalesce(m.is_deleted_flag, 'N') <> 'Y'
left join NONPROD_REFERENCE.CORE.PAYMENT_INSTRUMENT_TYPE c
  on c.payment_instrument_type_code = m.target_code
 and c.is_current_flag = 'Y'
 and coalesce(c.is_deleted_flag, 'N') <> 'Y'
where c.payment_instrument_type_key is null
order by s.lookup_source_code, s.payment_instrument_id
limit 100;
```





Use this to compare the historical source versions with the SCD2 target versions. It follows the same card/account joins and snapshot deduplication as the historical spec.

```sql
with source_rows as (
  select
    e.amed_card_nbr as payment_instrument_id,
    coalesce(
      cast(e.amed_card_activated_date as timestamp_ntz),
      cast('1900-01-01' as timestamp_ntz)
    ) as valid_from_datetime,
    e.airflow_dag_time as source_snapshot_datetime,
    e.amed_card_activated_date as activation_date,
    cast(e.amed_date_opened as timestamp_ntz) as card_created_datetime,
    e.amed_date_expire as expiration_date,
    e.amed_xfr_card_nbr as old_payment_instrument_id,
    e.amed_digital_card_type,
    e.amed_status,
    e.amed_add_status
  from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.EMBOSSER_RECORD e
  inner join (
    select distinct
      ambs_acct,
      ambs_org
    from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT
  ) a
    on e.amed_post_to_acct = a.ambs_acct
   and e.amed_org = a.ambs_org
  where e.amed_card_nbr is not null
    and trim(e.amed_card_nbr) <> ''
),

source_versions as (
  select *
  from source_rows
  qualify row_number() over (
    partition by payment_instrument_id, valid_from_datetime
    order by source_snapshot_datetime desc nulls last
  ) = 1
),

target_versions as (
  select
    payment_instrument_id,
    payment_instrument_key,
    valid_from_datetime,
    valid_to_datetime,
    is_current_flag,
    activation_date,
    card_created_datetime,
    expiration_date,
    old_payment_instrument_id
  from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT
)

select
  coalesce(s.payment_instrument_id, t.payment_instrument_id) as payment_instrument_id,
  coalesce(s.valid_from_datetime, t.valid_from_datetime) as valid_from_datetime,
  s.source_snapshot_datetime,
  t.payment_instrument_key,
  t.valid_to_datetime,
  t.is_current_flag,
  case
    when s.payment_instrument_id is null then 'TARGET_ONLY'
    when t.payment_instrument_id is null then 'SOURCE_ONLY'
    when s.activation_date is distinct from t.activation_date then 'ACTIVATION_DATE_DIFFERENT'
    when s.card_created_datetime is distinct from t.card_created_datetime then 'CARD_CREATED_DATETIME_DIFFERENT'
    when s.expiration_date is distinct from t.expiration_date then 'EXPIRATION_DATE_DIFFERENT'
    when s.old_payment_instrument_id is distinct from t.old_payment_instrument_id then 'OLD_PAYMENT_INSTRUMENT_ID_DIFFERENT'
    else 'MATCHED'
  end as comparison_status,
  s.amed_digital_card_type,
  s.amed_add_status,
  s.amed_status
from source_versions s
full outer join target_versions t
  on s.payment_instrument_id = t.payment_instrument_id
 and s.valid_from_datetime = t.valid_from_datetime
where s.payment_instrument_id is null
   or t.payment_instrument_id is null
   or s.activation_date is distinct from t.activation_date
   or s.card_created_datetime is distinct from t.card_created_datetime
   or s.expiration_date is distinct from t.expiration_date
   or s.old_payment_instrument_id is distinct from t.old_payment_instrument_id
order by payment_instrument_id, valid_from_datetime;
```

For a simple source-versus-target version-count reconciliation:

```sql
with source_versions as (
  select
    e.amed_card_nbr as payment_instrument_id,
    coalesce(
      cast(e.amed_card_activated_date as timestamp_ntz),
      cast('1900-01-01' as timestamp_ntz)
    ) as valid_from_datetime
  from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.EMBOSSER_RECORD e
  where e.amed_card_nbr is not null
    and trim(e.amed_card_nbr) <> ''
  qualify row_number() over (
    partition by
      e.amed_card_nbr,
      coalesce(cast(e.amed_card_activated_date as timestamp_ntz), cast('1900-01-01' as timestamp_ntz))
    order by e.airflow_dag_time desc nulls last
  ) = 1
)
select
  (select count(*) from source_versions) as source_scd2_versions,
  (select count(*) from SAS_MIGRATION_WORKSPACE.CORE.CARD_PAYMENT_INSTRUMENT) as target_scd2_versions;
```