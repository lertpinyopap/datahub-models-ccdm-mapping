{{ config(
    materialized='view',
    schema='CORE',
    alias='CARD_CUSTOMER_CURRENT_LOOKUP',
    tags=['conformed_lookup']
) }}

select
    CUSTOMER_ID,
    CARD_CUSTOMER_KEY,
    CARD_CUSTOMER_BUSINESS_KEY
from {{ var('database', target.database) }}.CORE.{{ var('card_customer_table', 'CARD_CUSTOMER') }}
where IS_CURRENT_FLAG = 'Y'
qualify row_number() over (
    partition by CUSTOMER_ID
    order by
        AUDIT_LAST_CHANGED_DATETIME desc nulls last,
        AUDIT_CREATED_DATETIME desc nulls last,
        CARD_CUSTOMER_KEY desc
) = 1
