{{ config(materialized='view', schema='INTERMEDIATE', alias='STG_V10_CUSTOMER_EMAIL_ADDRESS', tags=['v10_mapping_staging']) }}

with latest_customer as (
    select * exclude (SOURCE_ROW_NUMBER)
    from (
        select
            customer.*,
            row_number() over (
                partition by customer.AMNA_ORG, customer.AMNA_ACCT
                order by
                    customer.AIRFLOW_DAG_TIME desc,
                    customer.AMNA_DATE_LAST_MAINT desc nulls last,
                    customer.AMNA_EMAIL_FLAG_01 desc nulls last,
                    customer.AMNA_EMAIL_FLAG_02 desc nulls last
            ) as SOURCE_ROW_NUMBER
        from DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.CUSTOMER as customer
    )
    where SOURCE_ROW_NUMBER = 1
),

email_rows as (
    select
        customer.AMNA_ACCT as CUSTOMER_ID,
        'PERS' as EMAIL_TYPE_CODE,
        customer.AMNA_EMAIL_FLAG_01 as CUSTOMER_CONTACT_PREFERENCE_TYPE_FLAG,
        customer.AMNA_DATE_LAST_MAINT as SOURCE_EFFECTIVE_FROM_DATETIME,
        customer.AIRFLOW_DAG_TIME as SOURCE_SNAPSHOT_DATETIME,
        1 as EMAIL_SLOT,
        {{ v10_email_address('customer.AMNA_EMAIL_01') }} as EMAIL_ADDRESS,
        {{ v10_email_local_part('customer.AMNA_EMAIL_01') }} as EMAIL_ADDRESS_LOCAL_PART,
        {{ v10_email_subaddress_tag('customer.AMNA_EMAIL_01') }} as EMAIL_ADDRESS_SUBADDRESS_TAG,
        {{ v10_email_domain('customer.AMNA_EMAIL_01') }} as EMAIL_ADDRESS_DOMAIN
    from latest_customer as customer
    where nullif(trim(customer.AMNA_EMAIL_01), '') is not null

    union all

    select
        customer.AMNA_ACCT,
        'PERS',
        customer.AMNA_EMAIL_FLAG_02,
        customer.AMNA_DATE_LAST_MAINT,
        customer.AIRFLOW_DAG_TIME,
        2,
        {{ v10_email_address('customer.AMNA_EMAIL_02') }},
        {{ v10_email_local_part('customer.AMNA_EMAIL_02') }},
        {{ v10_email_subaddress_tag('customer.AMNA_EMAIL_02') }},
        {{ v10_email_domain('customer.AMNA_EMAIL_02') }}
    from latest_customer as customer
    where nullif(trim(customer.AMNA_EMAIL_02), '') is not null
)

select *
from email_rows
qualify row_number() over (
    partition by CUSTOMER_ID, EMAIL_TYPE_CODE, EMAIL_ADDRESS
    order by
        SOURCE_SNAPSHOT_DATETIME desc nulls last,
        SOURCE_EFFECTIVE_FROM_DATETIME desc nulls last,
        CUSTOMER_CONTACT_PREFERENCE_TYPE_FLAG desc nulls last,
        EMAIL_SLOT asc
) = 1
