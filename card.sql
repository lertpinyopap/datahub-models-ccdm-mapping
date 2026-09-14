with source_products as (
    select
        cast(A.AMBS_ORG as varchar) as product_org,
        cast(A.AMBS_LOGO as varchar) as product_logo,
        cast(A.AMBS_ORG as varchar)
            || cast(A.AMBS_LOGO as varchar) as source_code,
        count(*) as account_count,
        count(distinct A.AMBS_ACCT) as agreement_count
    from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT as A
    where A.AMBS_CURR_CODE is null
       or lpad(cast(A.AMBS_CURR_CODE as varchar), 3, '0') <> '000'
    group by 1, 2, 3
),
product_mapping as (
    select
        mapping.SOURCE_SYSTEM,
        mapping.SOURCE_CODE,
        mapping.TARGET_CODE,
        mapping.IS_CURRENT_FLAG as mapping_is_current,
        mapping.IS_DELETED_FLAG as mapping_is_deleted,
        product.PRODUCT_KEY,
        product.PRODUCT_BUSINESS_KEY,
        product.PRODUCT_CODE,
        product.IS_CURRENT_FLAG as product_is_current,
        product.IS_DELETED_FLAG as product_is_deleted
    from NONPROD_REFERENCE.MAPPING.PRODUCT as mapping
    left join NONPROD_REFERENCE.CORE.PRODUCT as product
        on product.PRODUCT_CODE = mapping.TARGET_CODE
    where mapping.SOURCE_SYSTEM = 'V10'
)
select
    source_products.*,
    product_mapping.TARGET_CODE,
    product_mapping.PRODUCT_KEY,
    product_mapping.PRODUCT_BUSINESS_KEY,
    case
        when product_mapping.SOURCE_CODE is null then 'NO_MAPPING_SOURCE_CODE'
        when product_mapping.PRODUCT_KEY is null then 'TARGET_PRODUCT_NOT_FOUND'
        when coalesce(trim(product_mapping.mapping_is_deleted), 'N') = 'Y' then 'MAPPING_DELETED'
        when coalesce(trim(product_mapping.product_is_deleted), 'N') = 'Y' then 'PRODUCT_DELETED'
        else 'MAPPED'
    end as lookup_status
from source_products
left join product_mapping
    on product_mapping.SOURCE_CODE = source_products.source_code
order by lookup_status, agreement_count desc, source_code;


select
    A.AMBS_ACCT as agreement_id,
    A.AMBS_CUST_NBR as customer_id,
    A.AMBS_ORG,
    A.AMBS_LOGO,
    cast(A.AMBS_ORG as varchar) || cast(A.AMBS_LOGO as varchar) as source_code
from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT as A
left join NONPROD_REFERENCE.MAPPING.PRODUCT as mapping
    on mapping.SOURCE_SYSTEM = 'V10'
   and mapping.SOURCE_CODE =
       cast(A.AMBS_ORG as varchar) || cast(A.AMBS_LOGO as varchar)
left join NONPROD_REFERENCE.CORE.PRODUCT as product
    on product.PRODUCT_CODE = mapping.TARGET_CODE
where (A.AMBS_CURR_CODE is null
       or lpad(cast(A.AMBS_CURR_CODE as varchar), 3, '0') <> '000')
  and product.PRODUCT_KEY is null
order by source_code, agreement_id;




select
    cast(A.AMBS_ORG as varchar) as product_org,
    cast(A.AMBS_LOGO as varchar) as product_logo,
    cast(A.AMBS_ORG as varchar)
        || cast(A.AMBS_LOGO as varchar) as missing_source_code,
    count(*) as account_count,
    count(distinct A.AMBS_ACCT) as agreement_count,
    min(A.AMBS_ACCT) as example_agreement_id
from DATAOPS_HUB_SHARE_VISION_NONPROD.RAW.ACCOUNT_BASE_SEGMENT as A
left join NONPROD_REFERENCE.MAPPING.PRODUCT as mapping
    on mapping.SOURCE_SYSTEM = 'V10'
   and mapping.SOURCE_CODE =
       cast(A.AMBS_ORG as varchar) || cast(A.AMBS_LOGO as varchar)
   and coalesce(trim(mapping.IS_DELETED_FLAG), 'N') <> 'Y'
left join NONPROD_REFERENCE.CORE.PRODUCT as product
    on product.PRODUCT_CODE = mapping.TARGET_CODE
   and coalesce(trim(product.IS_DELETED_FLAG), 'N') <> 'Y'
where (A.AMBS_CURR_CODE is null
       or lpad(cast(A.AMBS_CURR_CODE as varchar), 3, '0') <> '000')
  and product.PRODUCT_KEY is null
group by 1, 2, 3
order by account_count desc, missing_source_code;