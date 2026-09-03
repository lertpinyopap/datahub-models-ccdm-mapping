{{ config(materialized='view', schema='INTERMEDIATE', alias='STG_V10_ACCOUNT', tags=['v10_mapping_staging']) }}

select
    account.AMBS_CUST_NBR as CUSTOMER_ID,
    cast(account.AMBS_ACCT as varchar) as AGREEMENT_ID,
    account.AMBS_ORG as PRODUCT_ORG,
    account.AMBS_LOGO as PRODUCT_LOGO,
    account.AMBS_BILLING_CYCLE as BILLING_CYCLE_DATE,
    account.AMBS_CRLIM as CREDIT_LIMIT_AMOUNT,
    account.AMBS_CURR_CODE as CURRENCY_SOURCE_CODE,
    cast(null as number(38, 7)) as BALANCE_TRANSFER_LIMIT_AMOUNT,
    account.AMBS_CASH_CRLIM as CASH_LIMIT_AMOUNT,
    cast(null as number(38, 7)) as MONEY_TRANSFER_LIMIT_AMOUNT,
    case
        when account.AMBS_DATE_CLOSED is not null
         and cast(account.AMBS_DATE_CLOSED as varchar) not like '%1901%'
            then cast(account.AMBS_DATE_CLOSED as date)
    end as CLOSURE_REQUEST_DATE,
    case
        when account.AMBS_DATE_CLOSED is not null
         and cast(account.AMBS_DATE_CLOSED as varchar) not like '%1901%'
            then cast(account.AMBS_DATE_CLOSED as timestamp_tz)
    end as CLOSING_DATETIME,
    case when account.AMBS_INT_STATUS in ('A', 'N') then 'Y' else 'N' end as IS_ACTIVE_IN_SOURCE_FLAG,
    {{ v10_account_effective_datetime('account.AMBS_DATE_LAST_MAINT', 'account.AMBS_DATE_OPENED') }} as SOURCE_EFFECTIVE_FROM_DATETIME
from DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.ACCOUNT_BASE_SEGMENT as account
