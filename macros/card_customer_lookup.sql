{% macro card_customer_lookup(database=none, table='CARD_CUSTOMER') -%}
{% set lookup_database = var('OVERRIDE_DB', none) or var('database', none) or database %}
(
    select
        CUSTOMER_ID,
        CARD_CUSTOMER_KEY,
        CARD_CUSTOMER_BUSINESS_KEY
    from {{ lookup_database }}.CORE.{{ table }}
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
