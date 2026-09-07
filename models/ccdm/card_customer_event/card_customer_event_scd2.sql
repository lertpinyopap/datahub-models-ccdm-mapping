{{ config(enabled=not var('enable_card_customer_initial_load', false), materialized='incremental', incremental_strategy='delete+insert', unique_key='CARD_CUSTOMER_EVENT_BUSINESS_KEY', schema='CORE', alias='CARD_CUSTOMER_EVENT_DBT', on_schema_change='sync_all_columns', tags=['v10_mapping_target']) }}

-- depends_on: {{ ref('card_customer_scd2') }}

with source_query as (
    select customer.CARD_CUSTOMER_KEY, customer.CARD_CUSTOMER_BUSINESS_KEY, event.*
    from {{ ref('stg_v10_customer_event') }} as event
    inner join {{ v10_card_customer_lookup() }} as customer on customer.CUSTOMER_ID = event.CUSTOMER_ID
),
typed_source_rows as (
    select
        cast(uuid_string() as varchar(64)) as CARD_CUSTOMER_EVENT_KEY,
        cast(sha2(concat_ws('|', coalesce(cast(CARD_CUSTOMER_KEY as varchar), ''), coalesce(cast(CARD_CUSTOMER_BUSINESS_KEY as varchar), ''), coalesce(cast(EVENT_ID as varchar), '')), 256) as varchar(64)) as CARD_CUSTOMER_EVENT_BUSINESS_KEY,
        CARD_CUSTOMER_KEY, CARD_CUSTOMER_BUSINESS_KEY,
        event_type.CARD_CUSTOMER_EVENT_TYPE_KEY,
        cast(EVENT_ID as varchar(16777216)) as EVENT_ID,
        cast(EVENT_DESCRIPTION as varchar(16777216)) as EVENT_DESCRIPTION,
        cast(EVENT_CREATION_DATETIME as timestamp_tz) as EVENT_CREATION_DATETIME,
        cast(EVENT_CREATION_DATETIME as timestamp_tz) as VALID_FROM_DATETIME,
        cast('N' as varchar(1)) as IS_DELETED_FLAG,
        cast(sha2(concat_ws('|', coalesce(cast(event_type.CARD_CUSTOMER_EVENT_TYPE_KEY as varchar), ''), coalesce(cast(EVENT_ID as varchar), ''), coalesce(cast(EVENT_DESCRIPTION as varchar), ''), coalesce(cast(EVENT_CREATION_DATETIME as varchar), '')), 256) as varchar(64)) as BUSINESS_DATA_HASH
    from source_query
    {{ reference_lookup_mapping(reference_type='CARD_CUSTOMER_EVENT_TYPE', source_system='V10', ref_alias='event_type', output_column='CARD_CUSTOMER_EVENT_TYPE_KEY', source_code_column='EVENT_TYPE_CODE', required=true) }}
    where event_type.CARD_CUSTOMER_EVENT_TYPE_KEY is not null and EVENT_CREATION_DATETIME is not null
),
{{ v10_scd2(
    columns=['CARD_CUSTOMER_EVENT_KEY','CARD_CUSTOMER_EVENT_BUSINESS_KEY','CARD_CUSTOMER_KEY','CARD_CUSTOMER_BUSINESS_KEY','CARD_CUSTOMER_EVENT_TYPE_KEY','EVENT_ID','EVENT_DESCRIPTION','EVENT_CREATION_DATETIME'],
    business_key_columns=['CARD_CUSTOMER_EVENT_BUSINESS_KEY'],
    dedup_partition_columns=['CARD_CUSTOMER_EVENT_BUSINESS_KEY','VALID_FROM_DATETIME'],
    dedup_order_by='EVENT_ID desc',
    model_name='card_customer_event_scd2'
) }}
