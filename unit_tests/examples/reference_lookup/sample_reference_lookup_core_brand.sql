select
    src.source_system,
    src.source_code,
    ref.*
from (
    select 'V10' as source_system, 'LFSAU' as source_code
) as src
{{ reference_lookup_core(
    reference_type='BRAND',
    ref_alias='ref',
    output_column='BRAND_KEY',
    source_code_expression='src.source_code'
) }}
