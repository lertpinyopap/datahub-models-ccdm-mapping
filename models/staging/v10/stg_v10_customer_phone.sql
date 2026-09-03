{{ config(materialized='view', schema='INTERMEDIATE', alias='STG_V10_CUSTOMER_PHONE', tags=['v10_mapping_staging']) }}

with latest_customer as (
    select * exclude (SOURCE_ROW_NUMBER)
    from (
        select
            customer.*,
            row_number() over (
                partition by customer.AMNA_ORG, customer.AMNA_ACCT
                order by
                    customer.AMNA_DATE_LAST_MAINT desc nulls last,
                    customer.AMNA_HOME_PHONE_FLAG_01 desc nulls last,
                    customer.AMNA_MOBILE_PHONE_FLAG_01 desc nulls last,
                    customer.AMNA_PHONE_FLAG_01 desc nulls last
            ) as SOURCE_ROW_NUMBER
        from DATAOPS_HUB_SHARE_VISION_NONPROD.ODS.CUSTOMER as customer
    )
    where SOURCE_ROW_NUMBER = 1
),

phone_rows as (
    select customer.AMNA_ACCT as CUSTOMER_ID, 'PHON' as PHONE_TYPE_CODE,
        customer.AMNA_HOME_PHONE_FLAG_01 as PHONE_CONTACT_PREFERENCE_FLAG,
        null as SMS_CONTACT_PREFERENCE_FLAG,
        trim(customer.AMNA_HOME_PHONE_01) as PHONE_NUMBER,
        cast(null as varchar) as EXTENSION,
        customer.AMNA_DATE_LAST_MAINT as SOURCE_EFFECTIVE_FROM_DATETIME,
        1 as PHONE_SLOT
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'MOBL', customer.AMNA_MOBILE_PHONE_FLAG_01,
        customer.AMNA_SMS_FLAG_01, trim(customer.AMNA_MOBILE_PHONE_01), cast(null as varchar),
        customer.AMNA_DATE_LAST_MAINT, 2
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'WORK', customer.AMNA_PHONE_FLAG_01,
        null, trim(customer.AMNA_EMP_PHONE_01), trim(customer.AMNA_EMP_PHONE_EXTN_01),
        customer.AMNA_DATE_LAST_MAINT, 3
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'FAX', null, null, trim(customer.AMNA_FAX_PHONE_01),
        cast(null as varchar), customer.AMNA_DATE_LAST_MAINT, 4
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'PHON', customer.AMNA_HOME_PHONE_FLAG_02,
        null, trim(customer.AMNA_HOME_PHONE_02), cast(null as varchar),
        customer.AMNA_DATE_LAST_MAINT, 5
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'MOBL', customer.AMNA_MOBILE_PHONE_FLAG_02,
        customer.AMNA_SMS_FLAG_02, trim(customer.AMNA_MOBILE_PHONE_02), cast(null as varchar),
        customer.AMNA_DATE_LAST_MAINT, 6
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'WORK', customer.AMNA_PHONE_FLAG_02,
        null, trim(customer.AMNA_EMP_PHONE_02), trim(customer.AMNA_EMP_PHONE_EXTN_02),
        customer.AMNA_DATE_LAST_MAINT, 7
    from latest_customer as customer
    union all
    select customer.AMNA_ACCT, 'FAX', null, null, trim(customer.AMNA_FAX_PHONE_02),
        cast(null as varchar), customer.AMNA_DATE_LAST_MAINT, 8
    from latest_customer as customer
)

select *
from phone_rows
where PHONE_NUMBER is not null
  and trim(PHONE_NUMBER) <> ''
qualify row_number() over (
    partition by CUSTOMER_ID, PHONE_TYPE_CODE, PHONE_NUMBER
    order by
        SOURCE_EFFECTIVE_FROM_DATETIME desc nulls last,
        PHONE_CONTACT_PREFERENCE_FLAG desc nulls last,
        SMS_CONTACT_PREFERENCE_FLAG desc nulls last,
        EXTENSION desc nulls last,
        PHONE_SLOT asc
) = 1
