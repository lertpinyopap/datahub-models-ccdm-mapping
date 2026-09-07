{% macro native_scd2_validation_enabled() -%}
    {{ return(var('native_scd2_validation', false)) }}
{%- endmacro %}


{% macro native_scd2_validation_mode() -%}
    {% set mode = var('native_scd2_validation_mode', 'continuous') | lower %}
    {% if mode not in ['continuous', 'sparse'] %}
        {{ exceptions.raise_compiler_error(
            "native_scd2_validation_mode must be 'continuous' or 'sparse'"
        ) }}
    {% endif %}
    {{ return(mode) }}
{%- endmacro %}


{% macro native_scd2_validation_ctes(input_cte, business_key_columns) %}
{% if native_scd2_validation_enabled() %}
{% set validation_mode = native_scd2_validation_mode() %}
,
native_scd2_validation_windowed_rows as (
    select
        *,
        lead(VALID_FROM_DATETIME) over (
            partition by {{ business_key_columns | join(', ') }}
            order by VALID_FROM_DATETIME
        ) as NATIVE_SCD2_NEXT_VALID_FROM_DATETIME
    from {{ input_cte }}
),
native_scd2_invalid_validity_rows as (
    select *
    from native_scd2_validation_windowed_rows
    where VALID_FROM_DATETIME is null
       or VALID_TO_DATETIME is null
       or VALID_TO_DATETIME <= VALID_FROM_DATETIME
       or NATIVE_SCD2_NEXT_VALID_FROM_DATETIME <= VALID_TO_DATETIME
       {% if validation_mode == 'continuous' %}
       or (
            NATIVE_SCD2_NEXT_VALID_FROM_DATETIME is not null
            and NATIVE_SCD2_NEXT_VALID_FROM_DATETIME <> dateadd(nanosecond, 1, VALID_TO_DATETIME)
       )
       or (
            NATIVE_SCD2_NEXT_VALID_FROM_DATETIME is null
            and VALID_TO_DATETIME < cast('9999-12-30 00:00:00' as timestamp_tz)
       )
       {% endif %}
),
native_scd2_validation_failure_count as (
    select count(*) as FAILURE_COUNT
    from native_scd2_invalid_validity_rows
),
native_scd2_validation_guard as (
    select 0 as VALIDATION_GUARD
    from native_scd2_validation_failure_count
    where FAILURE_COUNT = 0
    union all
    select cast(concat('NATIVE_DBT_SCD2_VALIDATION_FAILED:', FAILURE_COUNT) as number) as VALIDATION_GUARD
    from native_scd2_validation_failure_count
    where FAILURE_COUNT > 0
)
{% endif %}
{% endmacro %}


{% macro native_scd2_validation_guard_join() %}
{% if native_scd2_validation_enabled() %}
cross join native_scd2_validation_guard
where native_scd2_validation_guard.VALIDATION_GUARD = 0
{% endif %}
{% endmacro %}
