select
    src.source_system,
    src.source_code,
    ref.*
from (
    select 'V10' as source_system, 'CCAUGEM' as source_code
) as src
{{ reference_lookup_core(
    reference_type='PRODUCT',
    ref_alias='ref',
    output_column='PRODUCT_KEY',
    source_code_expression='src.source_code'
) }}
