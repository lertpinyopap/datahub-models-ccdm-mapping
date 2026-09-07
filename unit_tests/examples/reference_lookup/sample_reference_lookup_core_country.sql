select
    src.source_code,
    ref.*
from (
    select 'AU' as source_code
) as src
{{ reference_lookup_core(
    reference_type='COUNTRY',
    ref_alias='ref',
    output_column='COUNTRY_KEY',
    source_code_expression='src.source_code'
) }}
