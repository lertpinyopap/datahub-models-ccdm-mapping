{{
  config(
    materialized='incremental',
    schema=var('target_schema', 'MAPPING') | upper,
    alias='ADDRESS_TYPE',
    incremental_strategy='delete+insert',
    unique_key=['ADDRESS_TYPE_BUSINESS_KEY'],
    on_schema_change='fail',
  )
}}

{% if execute and is_incremental() and var('tms_log_scd2_duplicate_hash_metrics', false) and not var('tms_unit_test', false) %}
{% set tms_scd2_duplicate_hash_log_sql %}
with source_rows as (
    select * from {{ ref('ADDRESS_TYPE__source') }}
),
validation_rows as (
    select
        *,
        coalesce(case when SOURCE_SYSTEM is not null and length(SOURCE_SYSTEM) > 50 then 'field `SOURCE_SYSTEM` exceeds data_type `varchar(50)`' end, case when SOURCE_CODE is not null and length(SOURCE_CODE) > 50 then 'field `SOURCE_CODE` exceeds data_type `varchar(50)`' end, case when SOURCE_DESCRIPTION is not null and length(SOURCE_DESCRIPTION) > 255 then 'field `SOURCE_DESCRIPTION` exceeds data_type `varchar(255)`' end, case when {{ prefix_target_system('TARGET_SYSTEM') }} is not null and length({{ prefix_target_system('TARGET_SYSTEM') }}) > 255 then 'field `TARGET_SYSTEM` exceeds data_type `varchar(255)`' end, case when TARGET_CODE is not null and length(TARGET_CODE) > 50 then 'field `TARGET_CODE` exceeds data_type `varchar(50)`' end, case when TARGET_DESCRIPTION is not null and length(TARGET_DESCRIPTION) > 255 then 'field `TARGET_DESCRIPTION` exceeds data_type `varchar(255)`' end, case when AUDIT_CREATED_SOURCE is null then 'field `AUDIT_CREATED_SOURCE` is null but not nullable' end, case when AUDIT_CREATED_SOURCE is not null and length(AUDIT_CREATED_SOURCE) > 16777216 then 'field `AUDIT_CREATED_SOURCE` exceeds data_type `varchar(16777216)`' end, case when AUDIT_LAST_CHANGED_SOURCE is null then 'field `AUDIT_LAST_CHANGED_SOURCE` is null but not nullable' end, case when AUDIT_LAST_CHANGED_SOURCE is not null and length(AUDIT_LAST_CHANGED_SOURCE) > 16777216 then 'field `AUDIT_LAST_CHANGED_SOURCE` exceeds data_type `varchar(16777216)`' end) as FAILURE_DETAILS
    from source_rows
),
valid_rows as (
    select validation_rows.*
    from validation_rows
    cross join {{ ref('ADDRESS_TYPE__validation_guard') }} as validation_guard
    where validation_rows.FAILURE_DETAILS is null
      and validation_guard.VALIDATION_FAILURE_GUARD = 0
),
typed_rows as (
    select
    cast(SOURCE_SYSTEM as varchar(50)) as SOURCE_SYSTEM,
    cast(SOURCE_CODE as varchar(50)) as SOURCE_CODE,
    cast(SOURCE_DESCRIPTION as varchar(255)) as SOURCE_DESCRIPTION,
    cast({{ prefix_target_system('TARGET_SYSTEM') }} as varchar(255)) as TARGET_SYSTEM,
    cast(TARGET_CODE as varchar(50)) as TARGET_CODE,
    cast(TARGET_DESCRIPTION as varchar(255)) as TARGET_DESCRIPTION,
    cast(AUDIT_CREATED_SOURCE as varchar(16777216)) as AUDIT_CREATED_SOURCE,
    cast(AUDIT_LAST_CHANGED_SOURCE as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
    cast(uuid_string() as varchar(36)) as ADDRESS_TYPE_KEY,
    cast(sha2(concat_ws('|', coalesce(cast(cast(SOURCE_SYSTEM as varchar(50)) as varchar), ''), coalesce(cast(cast(SOURCE_CODE as varchar(50)) as varchar), '')), 256) as varchar) as ADDRESS_TYPE_BUSINESS_KEY,
    cast('{{ var("insert_time") }}' as timestamp_tz) as TMS_VALID_FROM_DATETIME_CANDIDATE,
    cast(sha2(concat_ws('|', coalesce(cast(cast(SOURCE_SYSTEM as varchar(50)) as varchar), ''), coalesce(cast(cast(SOURCE_CODE as varchar(50)) as varchar), ''), coalesce(cast(cast(SOURCE_DESCRIPTION as varchar(255)) as varchar), ''), coalesce(cast(cast({{ prefix_target_system('TARGET_SYSTEM') }} as varchar(255)) as varchar), ''), coalesce(cast(cast(TARGET_CODE as varchar(50)) as varchar), ''), coalesce(cast(cast(TARGET_DESCRIPTION as varchar(255)) as varchar), '')), 256) as varchar(64)) as BUSINESS_DATA_HASH,
    'N' as TMS_IS_DELETED_FLAG_CANDIDATE,
    cast(null as timestamp_tz) as TMS_EXISTING_VALID_TO_DATETIME,
    cast(null as varchar(1)) as TMS_EXISTING_IS_CURRENT_FLAG,
    'N' as TMS_IS_EXISTING_TARGET_ROW,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_CREATED_DATETIME,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_LAST_CHANGED_DATETIME,
    cast('{{ var("audit_data_process_key", ((env_var("AIRFLOW_CTX_DAG_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_TASK_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_DAG_RUN_ID", env_var("AIRFLOW_CTX_RUN_ID", ""))) if env_var("AIRFLOW_CTX_DAG_ID", "") else invocation_id)) }}' as varchar(256)) as AUDIT_DATA_PROCESS_KEY
    from valid_rows
),
incoming_key_rows as (
    select distinct
        ADDRESS_TYPE_BUSINESS_KEY
    from typed_rows
),
existing_target_rows as (
    select
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        IS_CURRENT_FLAG,
        IS_DELETED_FLAG,
        VALID_FROM_DATETIME,
        VALID_TO_DATETIME,
        BUSINESS_DATA_HASH,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME,
        AUDIT_DATA_PROCESS_KEY
    from {{ this }} as existing_target
    where exists (
        select 1
        from incoming_key_rows as incoming_key
        where existing_target.ADDRESS_TYPE_BUSINESS_KEY = incoming_key.ADDRESS_TYPE_BUSINESS_KEY
    )
),
current_target_rows as (
    select *
    from existing_target_rows
    where IS_CURRENT_FLAG = 'Y'
),
current_duplicate_rows as (
    select typed_rows.*
    from typed_rows
    where exists (
        select 1
        from current_target_rows as current_target
        where typed_rows.ADDRESS_TYPE_BUSINESS_KEY = current_target.ADDRESS_TYPE_BUSINESS_KEY
          and current_target.BUSINESS_DATA_HASH = typed_rows.BUSINESS_DATA_HASH
          and coalesce(current_target.IS_DELETED_FLAG, 'N') = typed_rows.TMS_IS_DELETED_FLAG_CANDIDATE
          and typed_rows.TMS_VALID_FROM_DATETIME_CANDIDATE >= current_target.VALID_FROM_DATETIME
    )
),
source_change_rows as (
    select *
    from typed_rows
    where not exists (
        select 1
        from current_target_rows as current_target
        where typed_rows.ADDRESS_TYPE_BUSINESS_KEY = current_target.ADDRESS_TYPE_BUSINESS_KEY
          and current_target.BUSINESS_DATA_HASH = typed_rows.BUSINESS_DATA_HASH
          and coalesce(current_target.IS_DELETED_FLAG, 'N') = typed_rows.TMS_IS_DELETED_FLAG_CANDIDATE
          and typed_rows.TMS_VALID_FROM_DATETIME_CANDIDATE >= current_target.VALID_FROM_DATETIME
    )
),
synthetic_delete_rows as (
    select
        cast(null as varchar(50)) as SOURCE_SYSTEM,
        cast(null as varchar(50)) as SOURCE_CODE,
        cast(null as varchar(255)) as SOURCE_DESCRIPTION,
        cast(null as varchar(255)) as TARGET_SYSTEM,
        cast(null as varchar(50)) as TARGET_CODE,
        cast(null as varchar(255)) as TARGET_DESCRIPTION,
        cast(null as varchar(16777216)) as AUDIT_CREATED_SOURCE,
        cast(null as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
        cast(null as varchar(36)) as ADDRESS_TYPE_KEY,
        cast(null as varchar) as ADDRESS_TYPE_BUSINESS_KEY,
        cast(null as timestamp_tz) as TMS_VALID_FROM_DATETIME_CANDIDATE,
        cast(null as varchar(64)) as BUSINESS_DATA_HASH,
        cast(null as varchar(1)) as TMS_IS_DELETED_FLAG_CANDIDATE,
        cast(null as timestamp_tz) as TMS_EXISTING_VALID_TO_DATETIME,
        cast(null as varchar(1)) as TMS_EXISTING_IS_CURRENT_FLAG,
        cast(null as varchar(1)) as TMS_IS_EXISTING_TARGET_ROW,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_CREATED_DATETIME,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_LAST_CHANGED_DATETIME,
    cast('{{ var("audit_data_process_key", ((env_var("AIRFLOW_CTX_DAG_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_TASK_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_DAG_RUN_ID", env_var("AIRFLOW_CTX_RUN_ID", ""))) if env_var("AIRFLOW_CTX_DAG_ID", "") else invocation_id)) }}' as varchar(256)) as AUDIT_DATA_PROCESS_KEY
    where 1 = 0
),
change_rows as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from source_change_rows
    union all
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from synthetic_delete_rows
),
affected_key_rows as (
    select distinct
        ADDRESS_TYPE_BUSINESS_KEY
    from change_rows
),
affected_existing_rows as (
    select
        existing_target.SOURCE_SYSTEM as SOURCE_SYSTEM,
        existing_target.SOURCE_CODE as SOURCE_CODE,
        existing_target.SOURCE_DESCRIPTION as SOURCE_DESCRIPTION,
        existing_target.TARGET_SYSTEM as TARGET_SYSTEM,
        existing_target.TARGET_CODE as TARGET_CODE,
        existing_target.TARGET_DESCRIPTION as TARGET_DESCRIPTION,
        existing_target.AUDIT_CREATED_SOURCE as AUDIT_CREATED_SOURCE,
        existing_target.AUDIT_LAST_CHANGED_SOURCE as AUDIT_LAST_CHANGED_SOURCE,
        existing_target.ADDRESS_TYPE_KEY as ADDRESS_TYPE_KEY,
        existing_target.ADDRESS_TYPE_BUSINESS_KEY as ADDRESS_TYPE_BUSINESS_KEY,
        existing_target.VALID_FROM_DATETIME as TMS_VALID_FROM_DATETIME_CANDIDATE,
        existing_target.BUSINESS_DATA_HASH as BUSINESS_DATA_HASH,
        existing_target.IS_DELETED_FLAG as TMS_IS_DELETED_FLAG_CANDIDATE,
        existing_target.VALID_TO_DATETIME as TMS_EXISTING_VALID_TO_DATETIME,
        existing_target.IS_CURRENT_FLAG as TMS_EXISTING_IS_CURRENT_FLAG,
        'Y' as TMS_IS_EXISTING_TARGET_ROW,
        existing_target.AUDIT_DATA_PROCESS_KEY as AUDIT_DATA_PROCESS_KEY,
        existing_target.AUDIT_CREATED_DATETIME as AUDIT_CREATED_DATETIME,
        existing_target.AUDIT_LAST_CHANGED_DATETIME as AUDIT_LAST_CHANGED_DATETIME
    from existing_target_rows as existing_target
    where exists (
        select 1
        from affected_key_rows as affected_key
        where existing_target.ADDRESS_TYPE_BUSINESS_KEY = affected_key.ADDRESS_TYPE_BUSINESS_KEY
    )
),
version_row_candidates as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from affected_existing_rows
    union all
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from change_rows
),
version_rows as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from (
        select
            *,
            row_number() over (
                partition by ADDRESS_TYPE_BUSINESS_KEY, TMS_VALID_FROM_DATETIME_CANDIDATE
                order by case when TMS_IS_EXISTING_TARGET_ROW = 'N' then 0 else 1 end
            ) as TMS_VERSION_ROW_NUMBER
        from version_row_candidates
    )
    where TMS_VERSION_ROW_NUMBER = 1
),
duplicate_boundary_rows as (
    select
        *,
        lag(BUSINESS_DATA_HASH) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_BUSINESS_DATA_HASH,
        lag(TMS_IS_DELETED_FLAG_CANDIDATE) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_IS_DELETED_FLAG,
        lag(TMS_IS_EXISTING_TARGET_ROW) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_IS_EXISTING_TARGET_ROW,
        lag(BUSINESS_DATA_HASH, 2) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_2_BUSINESS_DATA_HASH,
        lag(TMS_IS_DELETED_FLAG_CANDIDATE, 2) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_2_IS_DELETED_FLAG,
        lead(BUSINESS_DATA_HASH) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_NEXT_BUSINESS_DATA_HASH,
        lead(TMS_IS_DELETED_FLAG_CANDIDATE) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_NEXT_IS_DELETED_FLAG
    from version_rows
),
current_duplicate_counts as (
    select count(*) as CURRENT_DUPLICATE_SKIP_COUNT
    from current_duplicate_rows
),
duplicate_boundary_counts as (
    select
        coalesce(sum(case when TMS_IS_EXISTING_TARGET_ROW = 'N' and (TMS_PREVIOUS_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_IS_DELETED_FLAG, 'N') or TMS_NEXT_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_NEXT_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_NEXT_IS_DELETED_FLAG, 'N')) then 1 else 0 end), 0) as HISTORICAL_DUPLICATE_SKIP_COUNT,
        coalesce(sum(case when ((TMS_IS_EXISTING_TARGET_ROW = 'N' and TMS_PREVIOUS_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_IS_DELETED_FLAG, 'N')) or (TMS_IS_EXISTING_TARGET_ROW = 'Y' and TMS_PREVIOUS_IS_EXISTING_TARGET_ROW = 'N' and TMS_PREVIOUS_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_IS_DELETED_FLAG, 'N') and not (TMS_PREVIOUS_2_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_2_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_2_IS_DELETED_FLAG, 'N')))) then 1 else 0 end), 0) as HISTORICAL_BOUNDARY_UPDATE_COUNT,
        coalesce(sum(case when TMS_IS_EXISTING_TARGET_ROW = 'Y' and TMS_PREVIOUS_IS_EXISTING_TARGET_ROW = 'Y' and TMS_PREVIOUS_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_IS_DELETED_FLAG, 'N') then 1 else 0 end), 0) as CONTIGUOUS_DUPLICATE_HASH_COUNT
    from duplicate_boundary_rows
)
select
    current_duplicate_counts.CURRENT_DUPLICATE_SKIP_COUNT,
    duplicate_boundary_counts.HISTORICAL_DUPLICATE_SKIP_COUNT,
    duplicate_boundary_counts.HISTORICAL_BOUNDARY_UPDATE_COUNT,
    duplicate_boundary_counts.CONTIGUOUS_DUPLICATE_HASH_COUNT
from current_duplicate_counts
cross join duplicate_boundary_counts
{% endset %}
{% set tms_scd2_duplicate_hash_log_result = run_query(tms_scd2_duplicate_hash_log_sql) %}
{% if tms_scd2_duplicate_hash_log_result is not none and (tms_scd2_duplicate_hash_log_result.rows | length) > 0 %}
{% set tms_current_duplicate_skip_count = tms_scd2_duplicate_hash_log_result.columns[0].values()[0] | int %}
{% set tms_historical_duplicate_skip_count = tms_scd2_duplicate_hash_log_result.columns[1].values()[0] | int %}
{% set tms_historical_boundary_update_count = tms_scd2_duplicate_hash_log_result.columns[2].values()[0] | int %}
{% set tms_contiguous_duplicate_hash_count = tms_scd2_duplicate_hash_log_result.columns[3].values()[0] | int %}
{% if tms_current_duplicate_skip_count > 0 %}{{ log('SCD2 duplicate hash handling: current duplicate rows skipped=' ~ tms_current_duplicate_skip_count, info=true) }}{% endif %}
{% if tms_historical_boundary_update_count > 0 %}{{ log('SCD2 duplicate hash handling: historical duplicate boundaries updated=' ~ tms_historical_boundary_update_count, info=true) }}{% endif %}
{% if tms_contiguous_duplicate_hash_count > 0 %}{{ log('SCD2 duplicate hash handling: contiguous duplicate hash windows detected=' ~ tms_contiguous_duplicate_hash_count, info=true) }}{% endif %}
{% endif %}
{% endif %}

{% if execute and not var('tms_unit_test', false) %}
{% set tms_validation_failure_sql %}
select
    VALIDATION_FAILURE_COUNT,
    VALIDATION_FAILURE_DETAILS
from {{ ref('ADDRESS_TYPE__validation_guard') }}
where VALIDATION_FAILURE_GUARD <> 0
limit 1
{% endset %}
{% set tms_validation_failure_result = run_query(tms_validation_failure_sql) %}
{% if tms_validation_failure_result is not none and (tms_validation_failure_result.rows | length) > 0 %}
{% set tms_validation_failure_count = tms_validation_failure_result.columns[0].values()[0] | int %}
{% set tms_validation_failure_details = tms_validation_failure_result.columns[1].values()[0] %}
{{ exceptions.raise_compiler_error('TYPE_MATERIALISATION_VALIDATION_FAILED: ' ~ tms_validation_failure_count ~ ' validation row(s) failed. First failure: ' ~ tms_validation_failure_details) }}
{% endif %}
{% endif %}

with source_rows as (
    select * from {{ ref('ADDRESS_TYPE__source') }}
),
validation_rows as (
    select
        *,
        coalesce(case when SOURCE_SYSTEM is not null and length(SOURCE_SYSTEM) > 50 then 'field `SOURCE_SYSTEM` exceeds data_type `varchar(50)`' end, case when SOURCE_CODE is not null and length(SOURCE_CODE) > 50 then 'field `SOURCE_CODE` exceeds data_type `varchar(50)`' end, case when SOURCE_DESCRIPTION is not null and length(SOURCE_DESCRIPTION) > 255 then 'field `SOURCE_DESCRIPTION` exceeds data_type `varchar(255)`' end, case when {{ prefix_target_system('TARGET_SYSTEM') }} is not null and length({{ prefix_target_system('TARGET_SYSTEM') }}) > 255 then 'field `TARGET_SYSTEM` exceeds data_type `varchar(255)`' end, case when TARGET_CODE is not null and length(TARGET_CODE) > 50 then 'field `TARGET_CODE` exceeds data_type `varchar(50)`' end, case when TARGET_DESCRIPTION is not null and length(TARGET_DESCRIPTION) > 255 then 'field `TARGET_DESCRIPTION` exceeds data_type `varchar(255)`' end, case when AUDIT_CREATED_SOURCE is null then 'field `AUDIT_CREATED_SOURCE` is null but not nullable' end, case when AUDIT_CREATED_SOURCE is not null and length(AUDIT_CREATED_SOURCE) > 16777216 then 'field `AUDIT_CREATED_SOURCE` exceeds data_type `varchar(16777216)`' end, case when AUDIT_LAST_CHANGED_SOURCE is null then 'field `AUDIT_LAST_CHANGED_SOURCE` is null but not nullable' end, case when AUDIT_LAST_CHANGED_SOURCE is not null and length(AUDIT_LAST_CHANGED_SOURCE) > 16777216 then 'field `AUDIT_LAST_CHANGED_SOURCE` exceeds data_type `varchar(16777216)`' end) as FAILURE_DETAILS
    from source_rows
),
valid_rows as (
    select validation_rows.*
    from validation_rows
    cross join {{ ref('ADDRESS_TYPE__validation_guard') }} as validation_guard
    where validation_rows.FAILURE_DETAILS is null
      and validation_guard.VALIDATION_FAILURE_GUARD = 0
),
typed_rows as (
    select
    cast(SOURCE_SYSTEM as varchar(50)) as SOURCE_SYSTEM,
    cast(SOURCE_CODE as varchar(50)) as SOURCE_CODE,
    cast(SOURCE_DESCRIPTION as varchar(255)) as SOURCE_DESCRIPTION,
    cast({{ prefix_target_system('TARGET_SYSTEM') }} as varchar(255)) as TARGET_SYSTEM,
    cast(TARGET_CODE as varchar(50)) as TARGET_CODE,
    cast(TARGET_DESCRIPTION as varchar(255)) as TARGET_DESCRIPTION,
    cast(AUDIT_CREATED_SOURCE as varchar(16777216)) as AUDIT_CREATED_SOURCE,
    cast(AUDIT_LAST_CHANGED_SOURCE as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
    cast(uuid_string() as varchar(36)) as ADDRESS_TYPE_KEY,
    cast(sha2(concat_ws('|', coalesce(cast(cast(SOURCE_SYSTEM as varchar(50)) as varchar), ''), coalesce(cast(cast(SOURCE_CODE as varchar(50)) as varchar), '')), 256) as varchar) as ADDRESS_TYPE_BUSINESS_KEY,
    cast('{{ var("insert_time") }}' as timestamp_tz) as TMS_VALID_FROM_DATETIME_CANDIDATE,
    cast(sha2(concat_ws('|', coalesce(cast(cast(SOURCE_SYSTEM as varchar(50)) as varchar), ''), coalesce(cast(cast(SOURCE_CODE as varchar(50)) as varchar), ''), coalesce(cast(cast(SOURCE_DESCRIPTION as varchar(255)) as varchar), ''), coalesce(cast(cast({{ prefix_target_system('TARGET_SYSTEM') }} as varchar(255)) as varchar), ''), coalesce(cast(cast(TARGET_CODE as varchar(50)) as varchar), ''), coalesce(cast(cast(TARGET_DESCRIPTION as varchar(255)) as varchar), '')), 256) as varchar(64)) as BUSINESS_DATA_HASH,
    'N' as TMS_IS_DELETED_FLAG_CANDIDATE,
    cast(null as timestamp_tz) as TMS_EXISTING_VALID_TO_DATETIME,
    cast(null as varchar(1)) as TMS_EXISTING_IS_CURRENT_FLAG,
    'N' as TMS_IS_EXISTING_TARGET_ROW,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_CREATED_DATETIME,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_LAST_CHANGED_DATETIME,
    cast('{{ var("audit_data_process_key", ((env_var("AIRFLOW_CTX_DAG_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_TASK_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_DAG_RUN_ID", env_var("AIRFLOW_CTX_RUN_ID", ""))) if env_var("AIRFLOW_CTX_DAG_ID", "") else invocation_id)) }}' as varchar(256)) as AUDIT_DATA_PROCESS_KEY
    from valid_rows
),
incoming_key_rows as (
    select distinct
        ADDRESS_TYPE_BUSINESS_KEY
    from typed_rows
),
{% if is_incremental() %}
existing_target_rows as (
    select
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        IS_CURRENT_FLAG,
        IS_DELETED_FLAG,
        VALID_FROM_DATETIME,
        VALID_TO_DATETIME,
        BUSINESS_DATA_HASH,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME,
        AUDIT_DATA_PROCESS_KEY
    from {{ this }}
),
{% else %}
existing_target_rows as (
    select
        cast(null as varchar(36)) as ADDRESS_TYPE_KEY,
        cast(null as varchar) as ADDRESS_TYPE_BUSINESS_KEY,
        cast(null as varchar(50)) as SOURCE_SYSTEM,
        cast(null as varchar(50)) as SOURCE_CODE,
        cast(null as varchar(255)) as SOURCE_DESCRIPTION,
        cast(null as varchar(255)) as TARGET_SYSTEM,
        cast(null as varchar(50)) as TARGET_CODE,
        cast(null as varchar(255)) as TARGET_DESCRIPTION,
        cast(null as varchar(1)) as IS_CURRENT_FLAG,
        cast(null as varchar(1)) as IS_DELETED_FLAG,
        cast(null as timestamp_ltz) as VALID_FROM_DATETIME,
        cast(null as timestamp_ltz) as VALID_TO_DATETIME,
        cast(null as varchar(64)) as BUSINESS_DATA_HASH,
        cast(null as varchar(16777216)) as AUDIT_CREATED_SOURCE,
        cast(null as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
        cast(null as timestamp_ltz) as AUDIT_CREATED_DATETIME,
        cast(null as timestamp_ltz) as AUDIT_LAST_CHANGED_DATETIME,
        cast(null as varchar(256)) as AUDIT_DATA_PROCESS_KEY
    where 1 = 0
),
{% endif %}
current_target_rows as (
    select *
    from existing_target_rows
    where IS_CURRENT_FLAG = 'Y'
),
source_change_rows as (
    select *
    from typed_rows
    where not exists (
        select 1
        from current_target_rows as current_target
        where typed_rows.ADDRESS_TYPE_BUSINESS_KEY = current_target.ADDRESS_TYPE_BUSINESS_KEY
          and current_target.BUSINESS_DATA_HASH = typed_rows.BUSINESS_DATA_HASH
          and coalesce(current_target.IS_DELETED_FLAG, 'N') = typed_rows.TMS_IS_DELETED_FLAG_CANDIDATE
          and typed_rows.TMS_VALID_FROM_DATETIME_CANDIDATE >= current_target.VALID_FROM_DATETIME
    )
),
synthetic_delete_rows as (
    select
        cast(null as varchar(50)) as SOURCE_SYSTEM,
        cast(null as varchar(50)) as SOURCE_CODE,
        cast(null as varchar(255)) as SOURCE_DESCRIPTION,
        cast(null as varchar(255)) as TARGET_SYSTEM,
        cast(null as varchar(50)) as TARGET_CODE,
        cast(null as varchar(255)) as TARGET_DESCRIPTION,
        cast(null as varchar(16777216)) as AUDIT_CREATED_SOURCE,
        cast(null as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
        cast(null as varchar(36)) as ADDRESS_TYPE_KEY,
        cast(null as varchar) as ADDRESS_TYPE_BUSINESS_KEY,
        cast(null as timestamp_tz) as TMS_VALID_FROM_DATETIME_CANDIDATE,
        cast(null as varchar(64)) as BUSINESS_DATA_HASH,
        cast(null as varchar(1)) as TMS_IS_DELETED_FLAG_CANDIDATE,
        cast(null as timestamp_tz) as TMS_EXISTING_VALID_TO_DATETIME,
        cast(null as varchar(1)) as TMS_EXISTING_IS_CURRENT_FLAG,
        cast(null as varchar(1)) as TMS_IS_EXISTING_TARGET_ROW,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_CREATED_DATETIME,
    cast(current_timestamp() as timestamp_ltz) as AUDIT_LAST_CHANGED_DATETIME,
    cast('{{ var("audit_data_process_key", ((env_var("AIRFLOW_CTX_DAG_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_TASK_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_DAG_RUN_ID", env_var("AIRFLOW_CTX_RUN_ID", ""))) if env_var("AIRFLOW_CTX_DAG_ID", "") else invocation_id)) }}' as varchar(256)) as AUDIT_DATA_PROCESS_KEY
    where 1 = 0
),
change_rows as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from source_change_rows
    union all
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from synthetic_delete_rows
),
affected_key_rows as (
    select distinct
        ADDRESS_TYPE_BUSINESS_KEY
    from change_rows
),
affected_existing_rows as (
    select
        existing_target.SOURCE_SYSTEM as SOURCE_SYSTEM,
        existing_target.SOURCE_CODE as SOURCE_CODE,
        existing_target.SOURCE_DESCRIPTION as SOURCE_DESCRIPTION,
        existing_target.TARGET_SYSTEM as TARGET_SYSTEM,
        existing_target.TARGET_CODE as TARGET_CODE,
        existing_target.TARGET_DESCRIPTION as TARGET_DESCRIPTION,
        existing_target.AUDIT_CREATED_SOURCE as AUDIT_CREATED_SOURCE,
        existing_target.AUDIT_LAST_CHANGED_SOURCE as AUDIT_LAST_CHANGED_SOURCE,
        existing_target.ADDRESS_TYPE_KEY as ADDRESS_TYPE_KEY,
        existing_target.ADDRESS_TYPE_BUSINESS_KEY as ADDRESS_TYPE_BUSINESS_KEY,
        existing_target.VALID_FROM_DATETIME as TMS_VALID_FROM_DATETIME_CANDIDATE,
        existing_target.BUSINESS_DATA_HASH as BUSINESS_DATA_HASH,
        existing_target.IS_DELETED_FLAG as TMS_IS_DELETED_FLAG_CANDIDATE,
        existing_target.VALID_TO_DATETIME as TMS_EXISTING_VALID_TO_DATETIME,
        existing_target.IS_CURRENT_FLAG as TMS_EXISTING_IS_CURRENT_FLAG,
        'Y' as TMS_IS_EXISTING_TARGET_ROW,
        existing_target.AUDIT_DATA_PROCESS_KEY as AUDIT_DATA_PROCESS_KEY,
        existing_target.AUDIT_CREATED_DATETIME as AUDIT_CREATED_DATETIME,
        existing_target.AUDIT_LAST_CHANGED_DATETIME as AUDIT_LAST_CHANGED_DATETIME
    from existing_target_rows as existing_target
    where exists (
        select 1
        from affected_key_rows as affected_key
        where existing_target.ADDRESS_TYPE_BUSINESS_KEY = affected_key.ADDRESS_TYPE_BUSINESS_KEY
    )
),
version_row_candidates as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from affected_existing_rows
    union all
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from change_rows
),
version_rows as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from (
        select
            *,
            row_number() over (
                partition by ADDRESS_TYPE_BUSINESS_KEY, TMS_VALID_FROM_DATETIME_CANDIDATE
                order by case when TMS_IS_EXISTING_TARGET_ROW = 'N' then 0 else 1 end
            ) as TMS_VERSION_ROW_NUMBER
        from version_row_candidates
    )
    where TMS_VERSION_ROW_NUMBER = 1
),
duplicate_boundary_rows as (
    select
        *,
        lag(BUSINESS_DATA_HASH) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_BUSINESS_DATA_HASH,
        lag(TMS_IS_DELETED_FLAG_CANDIDATE) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_IS_DELETED_FLAG,
        lag(TMS_IS_EXISTING_TARGET_ROW) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_IS_EXISTING_TARGET_ROW,
        lag(BUSINESS_DATA_HASH, 2) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_2_BUSINESS_DATA_HASH,
        lag(TMS_IS_DELETED_FLAG_CANDIDATE, 2) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_PREVIOUS_2_IS_DELETED_FLAG,
        lead(BUSINESS_DATA_HASH) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_NEXT_BUSINESS_DATA_HASH,
        lead(TMS_IS_DELETED_FLAG_CANDIDATE) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) as TMS_NEXT_IS_DELETED_FLAG
    from version_rows
),
deduplicated_version_rows as (
    select
        SOURCE_SYSTEM,
        SOURCE_CODE,
        SOURCE_DESCRIPTION,
        TARGET_SYSTEM,
        TARGET_CODE,
        TARGET_DESCRIPTION,
        AUDIT_CREATED_SOURCE,
        AUDIT_LAST_CHANGED_SOURCE,
        ADDRESS_TYPE_KEY,
        ADDRESS_TYPE_BUSINESS_KEY,
        TMS_VALID_FROM_DATETIME_CANDIDATE,
        BUSINESS_DATA_HASH,
        TMS_IS_DELETED_FLAG_CANDIDATE,
        TMS_EXISTING_VALID_TO_DATETIME,
        TMS_EXISTING_IS_CURRENT_FLAG,
        TMS_IS_EXISTING_TARGET_ROW,
        AUDIT_DATA_PROCESS_KEY,
        AUDIT_CREATED_DATETIME,
        AUDIT_LAST_CHANGED_DATETIME
    from duplicate_boundary_rows
    where not ((TMS_IS_EXISTING_TARGET_ROW = 'N' and TMS_PREVIOUS_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_IS_DELETED_FLAG, 'N')) or (TMS_IS_EXISTING_TARGET_ROW = 'Y' and TMS_PREVIOUS_IS_EXISTING_TARGET_ROW = 'N' and TMS_PREVIOUS_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_IS_DELETED_FLAG, 'N') and not (TMS_PREVIOUS_2_BUSINESS_DATA_HASH is not null and BUSINESS_DATA_HASH = TMS_PREVIOUS_2_BUSINESS_DATA_HASH and coalesce(TMS_IS_DELETED_FLAG_CANDIDATE, 'N') = coalesce(TMS_PREVIOUS_2_IS_DELETED_FLAG, 'N'))))
),
valid_from_rows as (
    select
        *,
        case
            when row_number() over (partition by ADDRESS_TYPE_BUSINESS_KEY order by TMS_VALID_FROM_DATETIME_CANDIDATE) = 1
            then cast('0001-01-01T00:00:00Z' as timestamp_tz)
            else TMS_VALID_FROM_DATETIME_CANDIDATE
        end as VALID_FROM_DATETIME
    from deduplicated_version_rows
),
windowed_rows as (
    select
        *,
        coalesce(dateadd(nanosecond, -1, lead(VALID_FROM_DATETIME) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by VALID_FROM_DATETIME)), cast('9999-12-31T23:59:59Z' as timestamp_tz)) as VALID_TO_DATETIME
    from valid_from_rows
),
flagged_rows as (
    select
        *,
        case
            when VALID_TO_DATETIME = cast('9999-12-31T23:59:59Z' as timestamp_tz)
            then 'Y'
            else 'N'
        end as IS_CURRENT_FLAG,
        TMS_IS_DELETED_FLAG_CANDIDATE as IS_DELETED_FLAG
    from windowed_rows
),
post_load_validation_rows as (
    select
        ADDRESS_TYPE_BUSINESS_KEY,
        VALID_FROM_DATETIME,
        VALID_TO_DATETIME
    from flagged_rows
    union all
    select
        existing_target.ADDRESS_TYPE_BUSINESS_KEY,
        existing_target.VALID_FROM_DATETIME,
        existing_target.VALID_TO_DATETIME
    from existing_target_rows as existing_target
    where not exists (
        select 1
        from affected_key_rows as affected_key
        where existing_target.ADDRESS_TYPE_BUSINESS_KEY = affected_key.ADDRESS_TYPE_BUSINESS_KEY
    )
),
scd2_validation_windowed_rows as (
    select
        *,
        lead(VALID_FROM_DATETIME) over (partition by ADDRESS_TYPE_BUSINESS_KEY order by VALID_FROM_DATETIME) as TMS_NEXT_VALID_FROM_DATETIME
    from post_load_validation_rows
),
scd2_invalid_validity_rows as (
    select *
    from scd2_validation_windowed_rows
    -- Accept near-end-of-time values so timezone normalisation of 9999-12-31 timestamps does not falsely reject open-ended rows.
    where (VALID_FROM_DATETIME is null)
       or (VALID_TO_DATETIME is null)
       or (VALID_TO_DATETIME <= VALID_FROM_DATETIME)
       or (TMS_NEXT_VALID_FROM_DATETIME <= VALID_TO_DATETIME)
       or (TMS_NEXT_VALID_FROM_DATETIME is not null and TMS_NEXT_VALID_FROM_DATETIME <> dateadd(nanosecond, 1, VALID_TO_DATETIME))
       or (TMS_NEXT_VALID_FROM_DATETIME is null and VALID_TO_DATETIME < cast('9999-12-30 00:00:00' as timestamp_tz))
),
scd2_validation_failure_count as (
    select count(*) as SCD2_VALIDATION_FAILURE_COUNT
    from scd2_invalid_validity_rows
),
scd2_validation_guard as (
    select
        case
            when SCD2_VALIDATION_FAILURE_COUNT = 0 then 0
            -- Deliberately fail the model rather than allowing a validation failure to replace the target with zero rows.
            else 1 / case when SCD2_VALIDATION_FAILURE_COUNT > 0 then 0 else 1 end
        end as SCD2_VALIDATION_GUARD
    from scd2_validation_failure_count
)

select
    ADDRESS_TYPE_KEY,
    ADDRESS_TYPE_BUSINESS_KEY,
    SOURCE_SYSTEM,
    SOURCE_CODE,
    SOURCE_DESCRIPTION,
    TARGET_SYSTEM,
    TARGET_CODE,
    TARGET_DESCRIPTION,
    IS_CURRENT_FLAG,
    IS_DELETED_FLAG,
    VALID_FROM_DATETIME,
    VALID_TO_DATETIME,
    BUSINESS_DATA_HASH,
    AUDIT_CREATED_SOURCE,
    AUDIT_LAST_CHANGED_SOURCE,
    AUDIT_CREATED_DATETIME,
    case
        when TMS_IS_EXISTING_TARGET_ROW = 'Y' then AUDIT_LAST_CHANGED_DATETIME
        else cast(current_timestamp() as timestamp_ltz)
    end as AUDIT_LAST_CHANGED_DATETIME,
    case
        when TMS_IS_EXISTING_TARGET_ROW = 'Y' then AUDIT_DATA_PROCESS_KEY
        else cast('{{ var("audit_data_process_key", ((env_var("AIRFLOW_CTX_DAG_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_TASK_ID", "") ~ ":" ~ env_var("AIRFLOW_CTX_DAG_RUN_ID", env_var("AIRFLOW_CTX_RUN_ID", ""))) if env_var("AIRFLOW_CTX_DAG_ID", "") else invocation_id)) }}' as varchar(256))
    end as AUDIT_DATA_PROCESS_KEY
from flagged_rows
cross join scd2_validation_guard
where scd2_validation_guard.SCD2_VALIDATION_GUARD = 0
