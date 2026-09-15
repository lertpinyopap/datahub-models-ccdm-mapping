{% macro _reference_lookup_core_reference_name(reference_type) -%}
    {% set normalized_type = reference_type | trim %}

    {% if normalized_type == '' %}
        {{ exceptions.raise_compiler_error("reference_type is required for reference_lookup_core") }}
    {% endif %}

    {{ return(normalized_type | upper) }}
{%- endmacro %}

{% macro _reference_lookup_core_database(reference_database=none) -%}
    {{ return(reference_database if reference_database is not none else var('ENV_PREFIX', '') ~ 'REFERENCE') }}
{%- endmacro %}

{% macro _reference_lookup_core_equals(left_sql, right_sql, case_insensitive_match=false) -%}
    {% if case_insensitive_match %}
        upper(trim(cast({{ left_sql }} as varchar))) = upper(trim(cast({{ right_sql }} as varchar)))
    {% else %}
        {{ left_sql }} = {{ right_sql }}
    {% endif %}
{%- endmacro %}

{% macro reference_lookup_core(
    reference_type,
    ref_alias,
    output_column,
    source_code_expression=none,
    source_code_column=none,
    code_table=none,
    reference_database=none,
    code_column=none,
    value_column=none,
    as_of_date_expr=none,
    case_insensitive_match=false,
    required=false
) -%}
    {# Direct core-table lookup for child reference rows that store the parent's business code. #}
    {% set reference_name = _reference_lookup_core_reference_name(reference_type) %}
    {% if source_code_expression is none and source_code_column is none %}
        {{ exceptions.raise_compiler_error(
            "reference_lookup_core requires source_code_column or source_code_expression"
        ) }}
    {% endif %}
    {% set resolved_source_code_expression = source_code_expression %}
    {% if resolved_source_code_expression is none %}
        {% set resolved_source_code_expression = "source_query." ~ adapter.quote(source_code_column) %}
    {% endif %}
    {% set resolved_reference_database = _reference_lookup_core_database(reference_database) %}
    {% set code_relation = code_table if code_table is not none else resolved_reference_database ~ '.CORE.' ~ reference_name %}
    {% set resolved_code_column = code_column if code_column is not none else reference_name ~ '_CODE' %}
    {% set resolved_value_column = value_column if value_column is not none else output_column %}
    {% set resolved_as_of_date_expr = as_of_date_expr if as_of_date_expr is not none else 'current_timestamp()' %}

    left join (
        select
            code.*
            {%- if output_column != resolved_value_column %},
            code.{{ adapter.quote(resolved_value_column) }} as {{ adapter.quote(output_column) }}
            {%- endif %}
        from {{ code_relation }} as code
        where coalesce(trim(code.IS_DELETED_FLAG), 'N') <> 'Y'
          and (
                code.VALID_FROM_DATETIME is null
                or cast(code.VALID_FROM_DATETIME as timestamp_ntz) <= cast({{ resolved_as_of_date_expr }} as timestamp_ntz)
          )
          and (
                code.VALID_TO_DATETIME is null
                or cast(code.VALID_TO_DATETIME as timestamp_ntz) >= cast({{ resolved_as_of_date_expr }} as timestamp_ntz)
          )
        qualify row_number() over (
            partition by code.{{ adapter.quote(resolved_code_column) }}
            order by
                case when upper(coalesce(trim(code.IS_CURRENT_FLAG), 'N')) = 'Y' then 0 else 1 end,
                cast(code.VALID_TO_DATETIME as timestamp_ntz) desc nulls last,
                cast(code.VALID_FROM_DATETIME as timestamp_ntz) desc nulls last
        ) = 1
    ) as {{ ref_alias }}
      on {{ _reference_lookup_core_equals(
            ref_alias ~ '.' ~ adapter.quote(resolved_code_column),
            '(' ~ resolved_source_code_expression ~ ')',
            case_insensitive_match
         ) }}
{%- endmacro %}
