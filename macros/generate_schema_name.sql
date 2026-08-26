{% macro generate_schema_name(custom_schema_name, node) -%}
    {% if custom_schema_name is none or custom_schema_name | trim == '' %}
        {{ target.schema }}
    {% else %}
        {{ custom_schema_name | trim }}
    {% endif %}
{%- endmacro %}
