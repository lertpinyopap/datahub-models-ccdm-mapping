{% macro v10_card_customer_lookup(database=none, table=none) -%}
{% set lookup_database = var('database', database or target.database) %}
{% set lookup_table = table or var('card_customer_lookup_table', 'CARD_CUSTOMER_DBT') %}
(
    select
        CUSTOMER_ID,
        CARD_CUSTOMER_KEY,
        CARD_CUSTOMER_BUSINESS_KEY
    from {{ lookup_database }}.CORE.{{ lookup_table }}
    where IS_CURRENT_FLAG = 'Y'
    qualify row_number() over (
        partition by CUSTOMER_ID
        order by
            AUDIT_LAST_CHANGED_DATETIME desc nulls last,
            AUDIT_CREATED_DATETIME desc nulls last,
            CARD_CUSTOMER_KEY desc
    ) = 1
)
{%- endmacro %}

{% macro v10_contact_preference_code(flag_expression, null_code='DQMissing') -%}
case
    when {{ flag_expression }} is null then '{{ null_code }}'
    when {{ flag_expression }} = 2 then 'PREFERRED'
    when {{ flag_expression }} = 1 then 'UNDEC'
    when {{ flag_expression }} = 0 then 'NOCTCT'
    else 'DQMapping'
end
{%- endmacro %}

{% macro v10_email_address(email_expression) -%}
lower(trim({{ email_expression }}))
{%- endmacro %}

{% macro v10_email_local_part(email_expression) -%}
split_part(split_part(trim({{ email_expression }}), '@', 1), '+', 1)
{%- endmacro %}

{% macro v10_email_subaddress_tag(email_expression) -%}
nullif(split_part(split_part(trim({{ email_expression }}), '@', 1), '+', 2), '')
{%- endmacro %}

{% macro v10_email_domain(email_expression) -%}
split_part(lower(trim({{ email_expression }})), '@', 2)
{%- endmacro %}

{% macro v10_account_effective_datetime(last_maint_expression, opened_expression) -%}
coalesce(
    cast(nullif({{ last_maint_expression }}, to_date('1901-01-01')) as timestamp_tz),
    cast(nullif({{ opened_expression }}, to_date('1901-01-01')) as timestamp_tz),
    cast('1901-01-01' as timestamp_tz)
)
{%- endmacro %}

{% macro v10_customer_status_code(add_status_expression, status_expression) -%}
case
    when {{ add_status_expression }} != 99 then '9999'
    when {{ status_expression }} = 0 then '0'
    when {{ status_expression }} = 1 then '1'
    when {{ status_expression }} = 2 then '2'
    else 'DQMapping'
end
{%- endmacro %}
