{#
  Source-derived SCD2 for late-arriving history.

  The calling model must define typed_source_rows. This macro only rewrites
  business keys that have an incoming version not already in the target. It
  combines all history for those keys with the incoming rows before deriving
  the new validity windows, so a backfill can be inserted before or between
  existing versions.
#}
{% macro v10_scd2_derived(columns, business_key_columns, dedup_partition_columns, dedup_order_by, model_name) %}
source_deduped_rows as (
    select *
    from typed_source_rows
    qualify row_number() over (
        partition by {{ dedup_partition_columns | join(', ') }}
        order by {{ dedup_order_by }}
    ) = 1
),

source_change_rows as (
    select source_row.*
    from source_deduped_rows as source_row
    {% if is_incremental() %}
    where not exists (
        select 1
        from {{ this }} as existing_target
        where {% for key in business_key_columns %}existing_target.{{ key }} = source_row.{{ key }}{% if not loop.last %} and {% endif %}{% endfor %}
          and existing_target.VALID_FROM_DATETIME = source_row.VALID_FROM_DATETIME
          and existing_target.BUSINESS_DATA_HASH = source_row.BUSINESS_DATA_HASH
          and coalesce(existing_target.IS_DELETED_FLAG, 'N') = source_row.IS_DELETED_FLAG
    )
      and not exists (
        select 1
        from {{ this }} as current_target
        where {% for key in business_key_columns %}current_target.{{ key }} = source_row.{{ key }}{% if not loop.last %} and {% endif %}{% endfor %}
          and current_target.IS_CURRENT_FLAG = 'Y'
          and current_target.BUSINESS_DATA_HASH = source_row.BUSINESS_DATA_HASH
          and coalesce(current_target.IS_DELETED_FLAG, 'N') = source_row.IS_DELETED_FLAG
          and source_row.VALID_FROM_DATETIME >= current_target.VALID_FROM_DATETIME
    )
    {% endif %}
),

affected_business_keys as (
    select distinct {{ business_key_columns | join(', ') }}
    from source_change_rows
),

combined_rows as (
    {% if is_incremental() %}
    select
        {% for column in columns %}existing_target.{{ column }},{% endfor %}
        existing_target.IS_DELETED_FLAG,
        existing_target.VALID_FROM_DATETIME,
        existing_target.BUSINESS_DATA_HASH,
        existing_target.AUDIT_CREATED_SOURCE,
        existing_target.AUDIT_LAST_CHANGED_SOURCE,
        existing_target.AUDIT_CREATED_DATETIME,
        existing_target.AUDIT_LAST_CHANGED_DATETIME,
        existing_target.AUDIT_DATA_PROCESS_KEY,
        existing_target.IS_CURRENT_FLAG as ORIGINAL_IS_CURRENT_FLAG,
        existing_target.VALID_TO_DATETIME as ORIGINAL_VALID_TO_DATETIME,
        1 as SOURCE_PRIORITY
    from {{ this }} as existing_target
    inner join affected_business_keys as affected
        on {% for key in business_key_columns %}affected.{{ key }} = existing_target.{{ key }}{% if not loop.last %} and {% endif %}{% endfor %}
    union all
    {% endif %}
    select
        {% for column in columns %}source_row.{{ column }},{% endfor %}
        source_row.IS_DELETED_FLAG,
        source_row.VALID_FROM_DATETIME,
        source_row.BUSINESS_DATA_HASH,
        cast('dbt.{{ model_name }}' as varchar(16777216)) as AUDIT_CREATED_SOURCE,
        cast('dbt.{{ model_name }}' as varchar(16777216)) as AUDIT_LAST_CHANGED_SOURCE,
        cast(current_timestamp() as timestamp_tz) as AUDIT_CREATED_DATETIME,
        cast(current_timestamp() as timestamp_tz) as AUDIT_LAST_CHANGED_DATETIME,
        cast('{{ invocation_id }}' as varchar(64)) as AUDIT_DATA_PROCESS_KEY,
        cast(null as varchar(1)) as ORIGINAL_IS_CURRENT_FLAG,
        cast(null as timestamp_tz) as ORIGINAL_VALID_TO_DATETIME,
        0 as SOURCE_PRIORITY
    from source_change_rows as source_row
),

version_rows as (
    select *
    from combined_rows
    qualify row_number() over (
        partition by {{ business_key_columns | join(', ') }}, VALID_FROM_DATETIME
        order by SOURCE_PRIORITY, {{ dedup_order_by }}
    ) = 1
),

boundary_rows as (
    select
        version_rows.*,
        lag(BUSINESS_DATA_HASH) over (
            partition by {{ business_key_columns | join(', ') }}
            order by VALID_FROM_DATETIME, SOURCE_PRIORITY
        ) as PREVIOUS_BUSINESS_DATA_HASH,
        lag(IS_DELETED_FLAG) over (
            partition by {{ business_key_columns | join(', ') }}
            order by VALID_FROM_DATETIME, SOURCE_PRIORITY
        ) as PREVIOUS_IS_DELETED_FLAG
    from version_rows
),

collapsed_rows as (
    select *
    from boundary_rows
    where PREVIOUS_BUSINESS_DATA_HASH is null
       or BUSINESS_DATA_HASH <> PREVIOUS_BUSINESS_DATA_HASH
       or coalesce(IS_DELETED_FLAG, 'N') <> coalesce(PREVIOUS_IS_DELETED_FLAG, 'N')
),

windowed_rows as (
    select
        collapsed_rows.*,
        lead(VALID_FROM_DATETIME) over (
            partition by {{ business_key_columns | join(', ') }}
            order by VALID_FROM_DATETIME
        ) as NEXT_VALID_FROM_DATETIME
    from collapsed_rows
),

final_rows as (
    select
        windowed_rows.*,
        cast(
            case when NEXT_VALID_FROM_DATETIME is null then 'Y' else 'N' end
            as varchar(1)
        ) as DERIVED_IS_CURRENT_FLAG,
        coalesce(
            dateadd(nanosecond, -1, NEXT_VALID_FROM_DATETIME),
            cast('9999-12-31 23:59:59 +00:00' as timestamp_tz)
        ) as DERIVED_VALID_TO_DATETIME
    from windowed_rows
)
{{ native_scd2_validation_ctes('final_rows', business_key_columns) }}

select
    {% for column in columns %}{{ column }},{% endfor %}
    DERIVED_IS_CURRENT_FLAG as IS_CURRENT_FLAG,
    IS_DELETED_FLAG,
    VALID_FROM_DATETIME,
    DERIVED_VALID_TO_DATETIME as VALID_TO_DATETIME,
    BUSINESS_DATA_HASH,
    AUDIT_CREATED_SOURCE,
    case
        when SOURCE_PRIORITY = 0
          or ORIGINAL_IS_CURRENT_FLAG <> DERIVED_IS_CURRENT_FLAG
          or ORIGINAL_VALID_TO_DATETIME <> DERIVED_VALID_TO_DATETIME
        then cast('dbt.{{ model_name }}' as varchar(16777216))
        else AUDIT_LAST_CHANGED_SOURCE
    end as AUDIT_LAST_CHANGED_SOURCE,
    AUDIT_CREATED_DATETIME,
    case
        when SOURCE_PRIORITY = 0
          or ORIGINAL_IS_CURRENT_FLAG <> DERIVED_IS_CURRENT_FLAG
          or ORIGINAL_VALID_TO_DATETIME <> DERIVED_VALID_TO_DATETIME
        then cast(current_timestamp() as timestamp_tz)
        else AUDIT_LAST_CHANGED_DATETIME
    end as AUDIT_LAST_CHANGED_DATETIME,
    case
        when SOURCE_PRIORITY = 0
          or ORIGINAL_IS_CURRENT_FLAG <> DERIVED_IS_CURRENT_FLAG
          or ORIGINAL_VALID_TO_DATETIME <> DERIVED_VALID_TO_DATETIME
        then cast('{{ invocation_id }}' as varchar(64))
        else AUDIT_DATA_PROCESS_KEY
    end as AUDIT_DATA_PROCESS_KEY
from final_rows
{{ native_scd2_validation_guard_join() }}
{% endmacro %}
