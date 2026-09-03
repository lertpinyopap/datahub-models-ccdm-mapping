select
    src.source_code,
    ref.*
from (
    select 'LFSAU' as source_code
) as src
{{ reference_lookup_core(
    reference_type='FINANCIAL_INSTITUTION',
    ref_alias='ref',
    output_column='FINANCIAL_INSTITUTION_KEY',
    source_code_expression='src.source_code'
) }}
