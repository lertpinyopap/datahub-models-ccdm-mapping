{{ config(enabled=not var('enable_card_customer_initial_load', false), materialized='incremental', incremental_strategy='delete+insert', unique_key='CARD_CUSTOMER_EMAIL_ADDRESS_BUSINESS_KEY', schema='CORE', alias='CARD_CUSTOMER_EMAIL_ADDRESS_DBT', on_schema_change='sync_all_columns', tags=['v10_mapping_target']) }}

-- depends_on: {{ ref('card_customer_scd2') }}

with source_query as (
    select customer.CARD_CUSTOMER_KEY, customer.CARD_CUSTOMER_BUSINESS_KEY, email.*
    from {{ ref('stg_v10_customer_email_address') }} as email
    inner join {{ v10_card_customer_lookup() }} as customer on customer.CUSTOMER_ID = email.CUSTOMER_ID
),
typed_source_rows as (
    select cast(uuid_string() as varchar(64)) CARD_CUSTOMER_EMAIL_ADDRESS_KEY,
        cast(sha2(concat_ws('|',coalesce(cast(CARD_CUSTOMER_KEY as varchar),''),coalesce(cast(CARD_CUSTOMER_BUSINESS_KEY as varchar),''),coalesce(cast(email_type.EMAIL_ADDRESS_TYPE_KEY as varchar),''),coalesce(cast(EMAIL_ADDRESS as varchar),'')),256) as varchar(64)) CARD_CUSTOMER_EMAIL_ADDRESS_BUSINESS_KEY,
        email_type.EMAIL_ADDRESS_TYPE_KEY,CARD_CUSTOMER_KEY,CARD_CUSTOMER_BUSINESS_KEY,preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY,
        cast(EMAIL_ADDRESS as varchar(1024)) EMAIL_ADDRESS,cast(EMAIL_ADDRESS_LOCAL_PART as varchar(1024)) EMAIL_ADDRESS_LOCAL_PART,cast(EMAIL_ADDRESS_SUBADDRESS_TAG as varchar(1024)) EMAIL_ADDRESS_SUBADDRESS_TAG,cast(EMAIL_ADDRESS_DOMAIN as varchar(1024)) EMAIL_ADDRESS_DOMAIN,
        cast(SOURCE_EFFECTIVE_FROM_DATETIME as timestamp_tz) VALID_FROM_DATETIME,cast('N' as varchar(1)) IS_DELETED_FLAG,
        cast(sha2(concat_ws('|',coalesce(cast(email_type.EMAIL_ADDRESS_TYPE_KEY as varchar),''),coalesce(cast(CARD_CUSTOMER_KEY as varchar),''),coalesce(cast(CARD_CUSTOMER_BUSINESS_KEY as varchar),''),coalesce(cast(preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY as varchar),''),coalesce(cast(EMAIL_ADDRESS as varchar),''),coalesce(cast(EMAIL_ADDRESS_LOCAL_PART as varchar),''),coalesce(cast(EMAIL_ADDRESS_SUBADDRESS_TAG as varchar),''),coalesce(cast(EMAIL_ADDRESS_DOMAIN as varchar),'')),256) as varchar(64)) BUSINESS_DATA_HASH
    from source_query
    {{ reference_lookup_mapping(reference_type='EMAIL_ADDRESS_TYPE',source_system='V10',ref_alias='email_type',output_column='EMAIL_ADDRESS_TYPE_KEY',source_code_column='EMAIL_TYPE_CODE',required=true) }}
    {{ reference_lookup_mapping(reference_type='CUSTOMER_CONTACT_PREFERENCE_TYPE',source_system='V10',ref_alias='preference',output_column='CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY',source_code_expression=v10_contact_preference_code('source_query.CUSTOMER_CONTACT_PREFERENCE_TYPE_FLAG'),required=true) }}
    where email_type.EMAIL_ADDRESS_TYPE_KEY is not null and preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY is not null and SOURCE_EFFECTIVE_FROM_DATETIME is not null
),
{{ v10_scd2(columns=['CARD_CUSTOMER_EMAIL_ADDRESS_KEY','CARD_CUSTOMER_EMAIL_ADDRESS_BUSINESS_KEY','EMAIL_ADDRESS_TYPE_KEY','CARD_CUSTOMER_KEY','CARD_CUSTOMER_BUSINESS_KEY','CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY','EMAIL_ADDRESS','EMAIL_ADDRESS_LOCAL_PART','EMAIL_ADDRESS_SUBADDRESS_TAG','EMAIL_ADDRESS_DOMAIN'],business_key_columns=['CARD_CUSTOMER_EMAIL_ADDRESS_BUSINESS_KEY'],dedup_partition_columns=['CARD_CUSTOMER_EMAIL_ADDRESS_BUSINESS_KEY','VALID_FROM_DATETIME'],dedup_order_by='EMAIL_ADDRESS desc',model_name='card_customer_email_address_scd2') }}
