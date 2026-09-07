{{ config(enabled=not var('enable_card_customer_initial_load', false), materialized='incremental', incremental_strategy='delete+insert', unique_key='CARD_CUSTOMER_PHONE_BUSINESS_KEY', schema='CORE', alias='CARD_CUSTOMER_PHONE_DBT', on_schema_change='sync_all_columns', tags=['v10_mapping_target']) }}

-- depends_on: {{ ref('card_customer_scd2') }}

with source_query as (
    select customer.CARD_CUSTOMER_KEY, customer.CARD_CUSTOMER_BUSINESS_KEY, phone.*
    from {{ ref('stg_v10_customer_phone') }} as phone
    inner join {{ v10_card_customer_lookup() }} as customer on customer.CUSTOMER_ID = phone.CUSTOMER_ID
),
typed_source_rows as (
    select cast(uuid_string() as varchar(64)) as CARD_CUSTOMER_PHONE_KEY,
        cast(sha2(concat_ws('|',coalesce(cast(CARD_CUSTOMER_KEY as varchar),''),coalesce(cast(CARD_CUSTOMER_BUSINESS_KEY as varchar),''),coalesce(cast(phone_type.PHONE_NUMBER_TYPE_KEY as varchar),''),coalesce(cast(PHONE_NUMBER as varchar),'')),256) as varchar(64)) as CARD_CUSTOMER_PHONE_BUSINESS_KEY,
        CARD_CUSTOMER_KEY,CARD_CUSTOMER_BUSINESS_KEY,phone_type.PHONE_NUMBER_TYPE_KEY,
        phone_preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY as PHONE_CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY,
        sms_preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY as SMS_CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY,
        cast(PHONE_NUMBER as varchar(40)) as PHONE_NUMBER,cast(EXTENSION as varchar(40)) as EXTENSION,
        cast(SOURCE_EFFECTIVE_FROM_DATETIME as timestamp_tz) as VALID_FROM_DATETIME,cast('N' as varchar(1)) as IS_DELETED_FLAG,
        cast(sha2(concat_ws('|',coalesce(cast(phone_type.PHONE_NUMBER_TYPE_KEY as varchar),''),coalesce(cast(CARD_CUSTOMER_KEY as varchar),''),coalesce(cast(CARD_CUSTOMER_BUSINESS_KEY as varchar),''),coalesce(cast(phone_preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY as varchar),''),coalesce(cast(sms_preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY as varchar),''),coalesce(cast(PHONE_NUMBER as varchar),''),coalesce(cast(EXTENSION as varchar),'')),256) as varchar(64)) as BUSINESS_DATA_HASH
    from source_query
    {{ reference_lookup_mapping(reference_type='PHONE_NUMBER_TYPE',source_system='V10',ref_alias='phone_type',output_column='PHONE_NUMBER_TYPE_KEY',source_code_column='PHONE_TYPE_CODE',required=true) }}
    {{ reference_lookup_mapping(reference_type='CUSTOMER_CONTACT_PREFERENCE_TYPE',source_system='V10',ref_alias='phone_preference',output_column='CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY',source_code_expression=v10_contact_preference_code('source_query.PHONE_CONTACT_PREFERENCE_FLAG','NOCTCT'),required=true) }}
    {{ reference_lookup_mapping(reference_type='CUSTOMER_CONTACT_PREFERENCE_TYPE',source_system='V10',ref_alias='sms_preference',output_column='CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY',source_code_expression=v10_contact_preference_code('source_query.SMS_CONTACT_PREFERENCE_FLAG','DQNotApplicable'),required=true) }}
    where phone_type.PHONE_NUMBER_TYPE_KEY is not null and phone_preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY is not null and sms_preference.CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY is not null and SOURCE_EFFECTIVE_FROM_DATETIME is not null
),
{{ v10_scd2(columns=['CARD_CUSTOMER_PHONE_KEY','CARD_CUSTOMER_PHONE_BUSINESS_KEY','CARD_CUSTOMER_KEY','CARD_CUSTOMER_BUSINESS_KEY','PHONE_NUMBER_TYPE_KEY','PHONE_CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY','SMS_CUSTOMER_CONTACT_PREFERENCE_TYPE_KEY','PHONE_NUMBER','EXTENSION'],business_key_columns=['CARD_CUSTOMER_PHONE_BUSINESS_KEY'],dedup_partition_columns=['CARD_CUSTOMER_PHONE_BUSINESS_KEY','VALID_FROM_DATETIME'],dedup_order_by='PHONE_NUMBER desc',model_name='card_customer_phone_scd2') }}
