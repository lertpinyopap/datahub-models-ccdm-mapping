{{ config(
    materialized='view',
    schema='CORE',
    alias='CARD_ACCOUNT_CURRENT_LOOKUP',
    tags=['conformed_lookup']
) }}

select
    AGREEMENT_ID,
    CARD_ACCOUNT_KEY,
    CARD_ACCOUNT_BUSINESS_KEY,
    CARD_CUSTOMER_KEY,
    CARD_CUSTOMER_BUSINESS_KEY
from {{ var('database', target.database) }}.CORE.{{ var('card_account_table', 'CARD_ACCOUNT') }}
where IS_CURRENT_FLAG = 'Y'
qualify row_number() over (
    partition by AGREEMENT_ID
    order by
        AUDIT_LAST_CHANGED_DATETIME desc nulls last,
        AUDIT_CREATED_DATETIME desc nulls last,
        CARD_ACCOUNT_KEY desc
) = 1
