select
    src.source_code,
    ref.*
from (
    select 'AUD' as source_code
) as src
{{ reference_lookup_core(
    reference_type='CURRENCY',
    ref_alias='ref',
    output_column='CURRENCY_KEY',
    source_code_expression='src.source_code'
) }}
