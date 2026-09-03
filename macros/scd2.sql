{% macro v10_scd2(columns, business_key_columns, dedup_partition_columns, dedup_order_by, model_name) %}
source_deduped_rows as (
    select *
    from typed_source_rows
    qualify row_number() over (
        partition by {{ dedup_partition_columns | join(', ') }}
        order by {{ dedup_order_by }}
    ) = 1
),
source_change_rows as (
    select source_deduped_rows.*
    from source_deduped_rows
    {% if is_incremental() %}
    where not exists (
        select 1 from {{ this }} as existing_target
        where {% for key in business_key_columns %}existing_target.{{ key }} = source_deduped_rows.{{ key }}{% if not loop.last %} and {% endif %}{% endfor %}
          and existing_target.VALID_FROM_DATETIME = source_deduped_rows.VALID_FROM_DATETIME
          and existing_target.BUSINESS_DATA_HASH = source_deduped_rows.BUSINESS_DATA_HASH
          and coalesce(existing_target.IS_DELETED_FLAG, 'N') = source_deduped_rows.IS_DELETED_FLAG
    )
      and not exists (
        select 1 from {{ this }} as current_target
        where {% for key in business_key_columns %}current_target.{{ key }} = source_deduped_rows.{{ key }}{% if not loop.last %} and {% endif %}{% endfor %}
          and current_target.IS_CURRENT_FLAG = 'Y'
          and current_target.BUSINESS_DATA_HASH = source_deduped_rows.BUSINESS_DATA_HASH
          and coalesce(current_target.IS_DELETED_FLAG, 'N') = source_deduped_rows.IS_DELETED_FLAG
          and source_deduped_rows.VALID_FROM_DATETIME >= current_target.VALID_FROM_DATETIME
    )
    {% endif %}
),
affected_business_keys as (
    select distinct {{ business_key_columns | join(', ') }} from source_change_rows
),
combined_rows as (
    {% if is_incremental() %}
    select
        {% for column in columns %}existing_target.{{ column }},{% endfor %}
        existing_target.IS_CURRENT_FLAG,
        existing_target.IS_DELETED_FLAG,
        existing_target.VALID_FROM_DATETIME,
        existing_target.VALID_TO_DATETIME,
        existing_target.BUSINESS_DATA_HASH,
        existing_target.AUDIT_CREATED_SOURCE,
        existing_target.AUDIT_LAST_CHANGED_SOURCE,
        existing_target.AUDIT_CREATED_DATETIME,
        existing_target.AUDIT_LAST_CHANGED_DATETIME,
        existing_target.AUDIT_DATA_PROCESS_KEY,
        1 as SOURCE_PRIORITY
    from {{ this }} as existing_target
    inner join affected_business_keys as affected
        on {% for key in business_key_columns %}affected.{{ key }} = existing_target.{{ key }}{% if not loop.last %} and {% endif %}{% endfor %}
    union all
    {% endif %}
    select
        {% for column in columns %}source_change_rows.{{ column }},{% endfor %}
        cast('N' as varchar(1)) as IS_CURRENT_FLAG,
        source_change_rows.IS_DELETED_FLAG,
        source_change_rows.VALID_FROM_DATETIME,
        cast(null as timestamp_tz) as VALID_TO_DATETIME,
        source_change_rows.BUSINESS_DATA_HASH,
        cast('dbt.{{ model_name }}' as varchar(16777216)) as AUDIT_CREATED_SOURCE,
        cast('dbt.{{ model_name }}' as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
        cast(current_timestamp() as timestamp_tz) as AUDIT_CREATED_DATETIME,
        cast(current_timestamp() as timestamp_tz) as AUDIT_LAST_CHANGED_DATETIME,
        cast('{{ invocation_id }}' as varchar(64)) as AUDIT_DATA_PROCESS_KEY,
        0 as SOURCE_PRIORITY
    from source_change_rows
),
version_rows as (
    select * from combined_rows
    qualify row_number() over (
        partition by {{ business_key_columns | join(', ') }}, VALID_FROM_DATETIME
        order by SOURCE_PRIORITY, BUSINESS_DATA_HASH desc
    ) = 1
),
collapsed_rows as (
    select * from (
        select version_rows.*,
            lag(BUSINESS_DATA_HASH) over (partition by {{ business_key_columns | join(', ') }} order by VALID_FROM_DATETIME, SOURCE_PRIORITY) as PREVIOUS_HASH,
            lag(IS_DELETED_FLAG) over (partition by {{ business_key_columns | join(', ') }} order by VALID_FROM_DATETIME, SOURCE_PRIORITY) as PREVIOUS_DELETED_FLAG
        from version_rows
    ) where PREVIOUS_HASH is null
       or BUSINESS_DATA_HASH <> PREVIOUS_HASH
       or coalesce(IS_DELETED_FLAG, 'N') <> coalesce(PREVIOUS_DELETED_FLAG, 'N')
),
final_rows as (
    select
        {% for column in columns %}{{ column }},{% endfor %}
        cast(case when lead(VALID_FROM_DATETIME) over (partition by {{ business_key_columns | join(', ') }} order by VALID_FROM_DATETIME) is null then 'Y' else 'N' end as varchar(1)) as IS_CURRENT_FLAG,
        IS_DELETED_FLAG,
        VALID_FROM_DATETIME,
        coalesce(dateadd(nanosecond, -1, lead(VALID_FROM_DATETIME) over (partition by {{ business_key_columns | join(', ') }} order by VALID_FROM_DATETIME)), cast('9999-12-31 23:59:59 +00:00' as timestamp_tz)) as VALID_TO_DATETIME,
        BUSINESS_DATA_HASH,
        AUDIT_CREATED_SOURCE,
        case when SOURCE_PRIORITY = 1 then AUDIT_LAST_CHANGED_SOURCE else cast('dbt.{{ model_name }}' as varchar(16777216)) end as AUDIT_LAST_CHANGED_SOURCE,
        AUDIT_CREATED_DATETIME,
        case when SOURCE_PRIORITY = 1 then AUDIT_LAST_CHANGED_DATETIME else cast(current_timestamp() as timestamp_tz) end as AUDIT_LAST_CHANGED_DATETIME,
        case when SOURCE_PRIORITY = 1 then AUDIT_DATA_PROCESS_KEY else cast('{{ invocation_id }}' as varchar(64)) end as AUDIT_DATA_PROCESS_KEY
    from collapsed_rows
)
{{ native_scd2_validation_ctes('final_rows', business_key_columns) }}
select
    *
from final_rows
{{ native_scd2_validation_guard_join() }}
{% endmacro %}
