select
    src.source_system,
    src.source_code,
    ref.*
from (
    select 'V10' as source_system, 'AUS' as source_code
) as src
{{ reference_lookup_mapping(
    reference_type='COUNTRY',
    source_system='V10',
    ref_alias='ref',
    output_column='COUNTRY_KEY',
    source_code_expression='src.source_code'
) }}
