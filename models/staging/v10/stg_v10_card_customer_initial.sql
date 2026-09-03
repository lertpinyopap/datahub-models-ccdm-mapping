{{ config(materialized='view', schema='INTERMEDIATE', alias='STG_V10_CARD_CUSTOMER_INITIAL', tags=['v10_mapping_staging']) }}

with joined_source as (
    select
        customer.AMNA_ADD_STATUS,
        customer.AMNA_STATUS,
        customer.AMNA_ACCT as CUSTOMER_ID,
        customer.AMNA_TITLE_01 as TITLE,
        customer.AMNA_FIRST_NAME_01 as FIRST_NAME,
        customer.AMNA_MIDDLE_NAME_01 as MIDDLE_NAME,
        customer.AMNA_LAST_NAME_01 as SURNAME,
        customer.AMNA_DOB_01 as DATE_OF_BIRTH,
        account.AMBS_DATE_OPENED as CREATED_DATETIME,
        customer.AMNA_DATE_LAST_MAINT as UPDATED_DATETIME,
        account.AMBS_INT_STATUS,
        customer.AMNA_ORG as CUSTOMER_ORG,
        account.AMBS_ORG as ACCOUNT_ORG,
        account.AMBS_ACCT as ACCOUNT_ID
    from DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.CUSTOMER as customer
    inner join DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.CUSTOMER_ACCOUNT as customer_account
        on customer.AMNA_ACCT = customer_account.AMBX_NA_ACCT
       and customer.AMNA_ORG = try_to_number(customer_account.AMBX_NA_ORG)
    inner join DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.ACCOUNT_BASE_SEGMENT as account
        on customer_account.AMBX_BS_ACCT = account.AMBS_ACCT
       and customer_account.AMBX_BS_ORG = account.AMBS_ORG
),

ranked_source as (
    select
        joined_source.*,
        row_number() over (
            partition by CUSTOMER_ID
            order by
                CREATED_DATETIME asc nulls last,
                UPDATED_DATETIME asc nulls last,
                CUSTOMER_ORG,
                ACCOUNT_ORG,
                ACCOUNT_ID
        ) as SOURCE_ROW_NUMBER
    from joined_source
)

select
    AMNA_ADD_STATUS,
    AMNA_STATUS,
    CUSTOMER_ID,
    TITLE,
    FIRST_NAME,
    MIDDLE_NAME,
    SURNAME,
    DATE_OF_BIRTH,
    CREATED_DATETIME,
    UPDATED_DATETIME,
    AMBS_INT_STATUS
from ranked_source
where SOURCE_ROW_NUMBER = 1
