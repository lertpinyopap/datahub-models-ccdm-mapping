{% macro _reference_lookup_mapping_reference_name(reference_type) -%}
    {% set normalized_type = reference_type | trim %}

    {% if normalized_type == '' %}
        {{ exceptions.raise_compiler_error("reference_type is required for reference_lookup_mapping") }}
    {% endif %}

    {{ return(normalized_type | upper) }}
{%- endmacro %}

{% macro _reference_lookup_mapping_database(reference_database=none) -%}
    {{ return(reference_database if reference_database is not none else var('ENV_PREFIX', '') ~ 'REFERENCE') }}
{%- endmacro %}

{% macro _reference_lookup_mapping_equals(left_sql, right_sql, case_insensitive_match=false) -%}
    {% if case_insensitive_match %}
        upper(trim(cast({{ left_sql }} as varchar))) = upper(trim(cast({{ right_sql }} as varchar)))
    {% else %}
        {{ left_sql }} = {{ right_sql }}
    {% endif %}
{%- endmacro %}

{% macro reference_lookup_mapping(
    reference_type,
    source_system,
    ref_alias,
    output_column,
    source_code_expression=none,
    source_code_column=none,
    mapping_table=none,
    code_table=none,
    reference_database=none,
    code_column=none,
    key_column=none,
    as_of_date_expr=none,
    case_insensitive_match=false,
    required=false
) -%}
    {# Runtime dbt lookup logic called by the TMS bridge macro in reference_lookup_mapping_macros.py. #}
    {% set reference_name = _reference_lookup_mapping_reference_name(reference_type) %}
    {% if source_code_expression is none and source_code_column is none %}
        {{ exceptions.raise_compiler_error(
            "reference_lookup_mapping requires source_code_column or source_code_expression"
        ) }}
    {% endif %}
    {% set resolved_source_code_expression = source_code_expression %}
    {% if resolved_source_code_expression is none %}
        {% set resolved_source_code_expression = "source_query." ~ adapter.quote(source_code_column) %}
    {% endif %}
    {% set resolved_reference_database = _reference_lookup_mapping_database(reference_database) %}
    {% set mapping_relation = mapping_table if mapping_table is not none else resolved_reference_database ~ '.MAPPING.' ~ reference_name %}
    {% set code_relation = code_table if code_table is not none else resolved_reference_database ~ '.CORE.' ~ reference_name %}
    {% set resolved_code_column = code_column if code_column is not none else reference_name ~ '_CODE' %}
    {% set resolved_key_column = key_column if key_column is not none else reference_name ~ '_KEY' %}
    {% set resolved_as_of_date_expr = as_of_date_expr if as_of_date_expr is not none else 'current_timestamp()' %}

    left join (
        select
            mapping.SOURCE_SYSTEM as _REFERENCE_SOURCE_SYSTEM,
            mapping.SOURCE_CODE as _REFERENCE_SOURCE_CODE,
            code.*
            {%- if output_column != resolved_key_column %},
            code.{{ adapter.quote(resolved_key_column) }} as {{ adapter.quote(output_column) }}
            {%- endif %}
        from {{ mapping_relation }} as mapping
        inner join {{ code_relation }} as code
            on {{ _reference_lookup_mapping_equals(
                'mapping.TARGET_CODE',
                'code.' ~ adapter.quote(resolved_code_column),
                case_insensitive_match
            ) }}
        where coalesce(trim(mapping.IS_DELETED_FLAG), 'N') <> 'Y'
          and coalesce(trim(code.IS_DELETED_FLAG), 'N') <> 'Y'
          and (
                mapping.VALID_FROM_DATE is null
                or cast(mapping.VALID_FROM_DATE as timestamp_ntz) <= cast({{ resolved_as_of_date_expr }} as timestamp_ntz)
          )
          and (
                mapping.VALID_TO_DATE is null
                or cast(mapping.VALID_TO_DATE as timestamp_ntz) >= cast({{ resolved_as_of_date_expr }} as timestamp_ntz)
          )
          and (
                code.VALID_FROM_DATE is null
                or cast(code.VALID_FROM_DATE as timestamp_ntz) <= cast({{ resolved_as_of_date_expr }} as timestamp_ntz)
          )
          and (
                code.VALID_TO_DATE is null
                or cast(code.VALID_TO_DATE as timestamp_ntz) >= cast({{ resolved_as_of_date_expr }} as timestamp_ntz)
          )
        qualify row_number() over (
            partition by mapping.SOURCE_SYSTEM, mapping.SOURCE_CODE
            order by
                case when upper(coalesce(trim(mapping.IS_CURRENT_FLAG), 'N')) = 'Y' then 0 else 1 end,
                case when upper(coalesce(trim(code.IS_CURRENT_FLAG), 'N')) = 'Y' then 0 else 1 end,
                cast(mapping.VALID_TO_DATE as timestamp_ntz) desc nulls last,
                cast(mapping.VALID_FROM_DATE as timestamp_ntz) desc nulls last,
                cast(code.VALID_TO_DATE as timestamp_ntz) desc nulls last,
                cast(code.VALID_FROM_DATE as timestamp_ntz) desc nulls last
        ) = 1
    ) as {{ ref_alias }}
      on {{ _reference_lookup_mapping_equals(
            ref_alias ~ '._REFERENCE_SOURCE_SYSTEM',
            "'" ~ source_system ~ "'",
            case_insensitive_match
         ) }}
     and {{ _reference_lookup_mapping_equals(
            ref_alias ~ '._REFERENCE_SOURCE_CODE',
            '(' ~ resolved_source_code_expression ~ ')',
            case_insensitive_match
         ) }}
{%- endmacro %}
