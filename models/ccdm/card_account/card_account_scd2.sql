{{
    config(
        enabled=not var('enable_card_customer_initial_load', false),
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='CARD_ACCOUNT_BUSINESS_KEY',
        schema='CORE',
        alias='CARD_ACCOUNT_DBT',
        on_schema_change='sync_all_columns',
        tags=['v10_mapping_target']
    )
}}

-- depends_on: {{ ref('card_customer_scd2') }}

with source_query as (
    select
        coalesce(card_customer.CARD_CUSTOMER_KEY, 'DQMissing') as CARD_CUSTOMER_KEY,
        coalesce(card_customer.CARD_CUSTOMER_BUSINESS_KEY, 'DQMissing') as CARD_CUSTOMER_BUSINESS_KEY,
        product_key.PRODUCT_KEY,
        product_business_key.PRODUCT_BUSINESS_KEY,
        account.AGREEMENT_ID,
        account.BILLING_CYCLE_DATE,
        account.CREDIT_LIMIT_AMOUNT,
        credit_currency.CREDIT_LIMIT_CURRENCY_KEY,
        account.BALANCE_TRANSFER_LIMIT_AMOUNT,
        cast(null as varchar(64)) as BALANCE_TRANSFER_LIMIT_CURRENCY_KEY,
        account.CASH_LIMIT_AMOUNT,
        cash_currency.CASH_LIMIT_CURRENCY_KEY,
        account.MONEY_TRANSFER_LIMIT_AMOUNT,
        cast(null as varchar(64)) as MONEY_TRANSFER_LIMIT_CURRENCY_KEY,
        account.CLOSURE_REQUEST_DATE,
        account.CLOSING_DATETIME,
        account.IS_ACTIVE_IN_SOURCE_FLAG,
        cast(null as varchar(16777216)) as MESSAGE_TRACE_ID,
        account.SOURCE_EFFECTIVE_FROM_DATETIME
    from {{ ref('stg_v10_account') }} as account
    left join {{ v10_card_customer_lookup() }} as card_customer
        on card_customer.CUSTOMER_ID = account.CUSTOMER_ID
    {{ reference_lookup_mapping(
        reference_type='PRODUCT',
        source_system='V10',
        ref_alias='product_key',
        output_column='PRODUCT_KEY',
        source_code_expression="cast(account.PRODUCT_ORG as varchar) || cast(account.PRODUCT_LOGO as varchar)",
        required=true
    ) }}
    {{ reference_lookup_mapping(
        reference_type='PRODUCT',
        source_system='V10',
        ref_alias='product_business_key',
        output_column='PRODUCT_BUSINESS_KEY',
        key_column='PRODUCT_BUSINESS_KEY',
        source_code_expression="cast(account.PRODUCT_ORG as varchar) || cast(account.PRODUCT_LOGO as varchar)",
        required=true
    ) }}
    {{ reference_lookup_mapping(
        reference_type='CURRENCY',
        source_system='V10',
        ref_alias='credit_currency',
        output_column='CREDIT_LIMIT_CURRENCY_KEY',
        source_code_expression="lpad(cast(account.CURRENCY_SOURCE_CODE as varchar), 3, '0')",
        required=true
    ) }}
    {{ reference_lookup_mapping(
        reference_type='CURRENCY',
        source_system='V10',
        ref_alias='cash_currency',
        output_column='CASH_LIMIT_CURRENCY_KEY',
        source_code_expression="lpad(cast(account.CURRENCY_SOURCE_CODE as varchar), 3, '0')",
        required=true
    ) }}
),

typed_source_rows as (
    select
        cast(uuid_string() as varchar(64)) as CARD_ACCOUNT_KEY,
        cast(sha2(concat_ws('|',
            coalesce(cast(CARD_CUSTOMER_BUSINESS_KEY as varchar), ''),
            coalesce(cast(AGREEMENT_ID as varchar), '')
        ), 256) as varchar(64)) as CARD_ACCOUNT_BUSINESS_KEY,
        cast(CARD_CUSTOMER_KEY as varchar(64)) as CARD_CUSTOMER_KEY,
        cast(CARD_CUSTOMER_BUSINESS_KEY as varchar(64)) as CARD_CUSTOMER_BUSINESS_KEY,
        cast(PRODUCT_KEY as varchar(64)) as PRODUCT_KEY,
        cast(PRODUCT_BUSINESS_KEY as varchar(64)) as PRODUCT_BUSINESS_KEY,
        cast(AGREEMENT_ID as varchar(16777216)) as AGREEMENT_ID,
        cast(BILLING_CYCLE_DATE as number(2)) as BILLING_CYCLE_DATE,
        cast(CREDIT_LIMIT_AMOUNT as number(38, 7)) as CREDIT_LIMIT_AMOUNT,
        cast(CREDIT_LIMIT_CURRENCY_KEY as varchar(64)) as CREDIT_LIMIT_CURRENCY_KEY,
        cast(BALANCE_TRANSFER_LIMIT_AMOUNT as number(38, 7)) as BALANCE_TRANSFER_LIMIT_AMOUNT,
        cast(BALANCE_TRANSFER_LIMIT_CURRENCY_KEY as varchar(64)) as BALANCE_TRANSFER_LIMIT_CURRENCY_KEY,
        cast(CASH_LIMIT_AMOUNT as number(38, 7)) as CASH_LIMIT_AMOUNT,
        cast(CASH_LIMIT_CURRENCY_KEY as varchar(64)) as CASH_LIMIT_CURRENCY_KEY,
        cast(MONEY_TRANSFER_LIMIT_AMOUNT as number(38, 7)) as MONEY_TRANSFER_LIMIT_AMOUNT,
        cast(MONEY_TRANSFER_LIMIT_CURRENCY_KEY as varchar(64)) as MONEY_TRANSFER_LIMIT_CURRENCY_KEY,
        cast(CLOSURE_REQUEST_DATE as date) as CLOSURE_REQUEST_DATE,
        cast(CLOSING_DATETIME as timestamp_tz) as CLOSING_DATETIME,
        cast(IS_ACTIVE_IN_SOURCE_FLAG as varchar(1)) as IS_ACTIVE_IN_SOURCE_FLAG,
        cast(MESSAGE_TRACE_ID as varchar(16777216)) as MESSAGE_TRACE_ID,
        cast(SOURCE_EFFECTIVE_FROM_DATETIME as timestamp_tz) as VALID_FROM_DATETIME,
        cast('N' as varchar(1)) as IS_DELETED_FLAG,
        cast(sha2(concat_ws('|',
            coalesce(cast(PRODUCT_BUSINESS_KEY as varchar), ''),
            coalesce(cast(BILLING_CYCLE_DATE as varchar), ''),
            coalesce(cast(CREDIT_LIMIT_AMOUNT as varchar), ''),
            coalesce(cast(CREDIT_LIMIT_CURRENCY_KEY as varchar), ''),
            coalesce(cast(BALANCE_TRANSFER_LIMIT_AMOUNT as varchar), ''),
            coalesce(cast(BALANCE_TRANSFER_LIMIT_CURRENCY_KEY as varchar), ''),
            coalesce(cast(CASH_LIMIT_AMOUNT as varchar), ''),
            coalesce(cast(CASH_LIMIT_CURRENCY_KEY as varchar), ''),
            coalesce(cast(MONEY_TRANSFER_LIMIT_AMOUNT as varchar), ''),
            coalesce(cast(MONEY_TRANSFER_LIMIT_CURRENCY_KEY as varchar), ''),
            coalesce(cast(CLOSURE_REQUEST_DATE as varchar), ''),
            coalesce(cast(CLOSING_DATETIME as varchar), ''),
            coalesce(cast(IS_ACTIVE_IN_SOURCE_FLAG as varchar), '')
        ), 256) as varchar(64)) as BUSINESS_DATA_HASH
    from source_query
    where AGREEMENT_ID is not null
      and PRODUCT_KEY is not null
      and PRODUCT_BUSINESS_KEY is not null
      and CREDIT_LIMIT_AMOUNT is not null
      and CASH_LIMIT_AMOUNT is not null
      and SOURCE_EFFECTIVE_FROM_DATETIME is not null
),

{{ v10_scd2(
    columns=[
        'CARD_ACCOUNT_KEY', 'CARD_ACCOUNT_BUSINESS_KEY',
        'CARD_CUSTOMER_KEY', 'CARD_CUSTOMER_BUSINESS_KEY',
        'PRODUCT_KEY', 'PRODUCT_BUSINESS_KEY', 'AGREEMENT_ID',
        'BILLING_CYCLE_DATE', 'CREDIT_LIMIT_AMOUNT',
        'CREDIT_LIMIT_CURRENCY_KEY', 'BALANCE_TRANSFER_LIMIT_AMOUNT',
        'BALANCE_TRANSFER_LIMIT_CURRENCY_KEY', 'CASH_LIMIT_AMOUNT',
        'CASH_LIMIT_CURRENCY_KEY', 'MONEY_TRANSFER_LIMIT_AMOUNT',
        'MONEY_TRANSFER_LIMIT_CURRENCY_KEY', 'CLOSURE_REQUEST_DATE',
        'CLOSING_DATETIME', 'IS_ACTIVE_IN_SOURCE_FLAG', 'MESSAGE_TRACE_ID'
    ],
    business_key_columns=['CARD_ACCOUNT_BUSINESS_KEY'],
    dedup_partition_columns=[
        'CARD_CUSTOMER_BUSINESS_KEY', 'AGREEMENT_ID', 'VALID_FROM_DATETIME'
    ],
    dedup_order_by='IS_ACTIVE_IN_SOURCE_FLAG desc nulls last, BUSINESS_DATA_HASH desc',
    model_name='card_account_scd2'
) }}
