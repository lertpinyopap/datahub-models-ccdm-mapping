{{
    config(
        enabled=not var('enable_card_customer_initial_load', false),
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='CARD_CUSTOMER_BUSINESS_KEY',
        schema='CORE',
        alias='CARD_CUSTOMER_DBT',
        on_schema_change='sync_all_columns',
        tags=['v10_mapping_target']
    )
}}

with source_query as (
    select
        AMNA_ADD_STATUS,
        AMNA_STATUS,
        cast(CUSTOMER_ID as varchar(20)) as CUSTOMER_ID,
        cast(TITLE as varchar(50)) as TITLE,
        cast(FIRST_NAME as varchar(50)) as FIRST_NAME,
        cast(MIDDLE_NAME as varchar(50)) as MIDDLE_NAME,
        cast(SURNAME as varchar(255)) as SURNAME,
        cast(DATE_OF_BIRTH as date) as DATE_OF_BIRTH,
        cast(CREATED_DATETIME as timestamp_tz) as CREATED_DATETIME,
        cast(UPDATED_DATETIME as timestamp_tz) as UPDATED_DATETIME,
        cast(case
            when AMNA_ADD_STATUS = 99 and AMNA_STATUS = 0 then 'Y'
            else 'N'
        end as varchar(1)) as IS_ACTIVE_IN_SOURCE_FLAG
    from {{ ref('stg_v10_card_customer_incremental') }}
),

typed_source_rows as (
    select
        cast(uuid_string() as varchar(64)) as CARD_CUSTOMER_KEY,
        cast(sha2(concat_ws('|', coalesce(cast(source_query.CUSTOMER_ID as varchar), '')), 256) as varchar(64)) as CARD_CUSTOMER_BUSINESS_KEY,
        customer_status.CUSTOMER_STATUS_KEY,
        source_query.CUSTOMER_ID,
        source_query.CUSTOMER_ID as CLV_ID,
        source_query.TITLE,
        source_query.FIRST_NAME,
        source_query.MIDDLE_NAME,
        source_query.SURNAME,
        source_query.DATE_OF_BIRTH,
        cast(null as varchar(255)) as EXTERNAL_ID,
        cast('AMID' as varchar(255)) as EXTERNAL_IDENTIFICATION_TYPE,
        source_query.CREATED_DATETIME,
        source_query.UPDATED_DATETIME,
        source_query.IS_ACTIVE_IN_SOURCE_FLAG,
        cast(coalesce(source_query.UPDATED_DATETIME, source_query.CREATED_DATETIME) as timestamp_tz) as VALID_FROM_DATETIME,
        cast('N' as varchar(1)) as IS_DELETED_FLAG,
        cast(sha2(concat_ws('|',
            coalesce(cast(customer_status.CUSTOMER_STATUS_KEY as varchar), ''),
            coalesce(cast(source_query.CUSTOMER_ID as varchar), ''),
            coalesce(cast(source_query.TITLE as varchar), ''),
            coalesce(cast(source_query.FIRST_NAME as varchar), ''),
            coalesce(cast(source_query.MIDDLE_NAME as varchar), ''),
            coalesce(cast(source_query.SURNAME as varchar), ''),
            coalesce(cast(source_query.DATE_OF_BIRTH as varchar), ''),
            coalesce(cast('AMID' as varchar), ''),
            coalesce(cast(source_query.CREATED_DATETIME as varchar), ''),
            coalesce(cast(source_query.UPDATED_DATETIME as varchar), ''),
            coalesce(cast(source_query.IS_ACTIVE_IN_SOURCE_FLAG as varchar), '')
        ), 256) as varchar(64)) as BUSINESS_DATA_HASH
    from source_query
    {{ reference_lookup_mapping(
        reference_type='CUSTOMER_STATUS',
        source_system='V10',
        ref_alias='customer_status',
        output_column='CUSTOMER_STATUS_KEY',
        source_code_expression=v10_customer_status_code(
            'source_query.AMNA_ADD_STATUS',
            'source_query.AMNA_STATUS'
        ),
        required=true
    ) }}
    where customer_status.CUSTOMER_STATUS_KEY is not null
      and source_query.CUSTOMER_ID is not null
      and coalesce(source_query.UPDATED_DATETIME, source_query.CREATED_DATETIME) is not null
),

{{ v10_scd2(
    columns=['CARD_CUSTOMER_KEY','CARD_CUSTOMER_BUSINESS_KEY','CUSTOMER_STATUS_KEY','CUSTOMER_ID','CLV_ID','TITLE','FIRST_NAME','MIDDLE_NAME','SURNAME','DATE_OF_BIRTH','EXTERNAL_ID','EXTERNAL_IDENTIFICATION_TYPE','CREATED_DATETIME','UPDATED_DATETIME','IS_ACTIVE_IN_SOURCE_FLAG'],
    business_key_columns=['CARD_CUSTOMER_BUSINESS_KEY'],
    dedup_partition_columns=['CUSTOMER_ID','VALID_FROM_DATETIME'],
    dedup_order_by='UPDATED_DATETIME desc nulls last, CREATED_DATETIME asc nulls last, BUSINESS_DATA_HASH desc',
    model_name='card_customer_scd2'
) }}
