{{ config(materialized='view', schema='INTERMEDIATE', alias='STG_V10_CUSTOMER_EVENT', tags=['v10_mapping_staging']) }}

select
    customer.AMNA_ACCT as CUSTOMER_ID,
    sha2(concat_ws('|',
        coalesce(cast(history.AMHS_ND_ACCOUNT as varchar), ''),
        coalesce(cast(history.AMHS_ND_ACTION_CODE as varchar), ''),
        coalesce(cast(history.AMHS_ND_ACTION_DESC as varchar), ''),
        coalesce(cast(history.AMHS_ND_HIST_DATE as varchar), ''),
        coalesce(cast(history.AMHS_ND_HIST_TIME as varchar), '')
    ), 256) as EVENT_ID,
    history.AMHS_ND_ACTION_CODE as EVENT_TYPE_CODE,
    history.AMHS_ND_ACTION_DESC as EVENT_DESCRIPTION,
    try_to_timestamp_ntz(
        history.AMHS_ND_HIST_DATE::varchar || ' ' ||
        left(lpad(trim(history.AMHS_ND_HIST_TIME::varchar), 6, '0'), 4) || '00',
        'YYYY-MM-DD HH24MISS'
    ) as EVENT_CREATION_DATETIME
from DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.ASM_MEMO_NONMONETARY as history
join DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.ACCOUNT_BASE_SEGMENT as account
    on history.AMHS_ND_ACCOUNT = account.AMBS_ACCT
join DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.CUSTOMER as customer
    on account.AMBS_CUST_NBR = customer.AMNA_ACCT
where history.AMHS_ND_ACTION_CODE in ('ADDR', 'CONT', 'LETR', 'B2FM', 'NADD', 'ANEX')
