from typing import Any

from type_materialisation.macro_api import TypeMaterialisationMacro


class PrefixTargetSystem(TypeMaterialisationMacro):
    supports_python_execution = True

    def generate_dbt_macro(self) -> str:
        return """
{% macro prefix_target_system(column_expression) %}
    case
        when {{ column_expression }} is null then null
        when '{{ var("ENV_PREFIX", "") }}' = '' then {{ column_expression }}
        when split_part(cast({{ column_expression }} as varchar), '.', 1) like '{{ var("ENV_PREFIX", "") }}%' then cast({{ column_expression }} as varchar)
        else '{{ var("ENV_PREFIX", "") }}' || cast({{ column_expression }} as varchar)
    end
{% endmacro %}
""".strip()

    def execute(self, *, value: Any, **_context: Any) -> Any:
        if value is None:
            return None
        return value


prefix_target_system = PrefixTargetSystem()


class ReferenceLookupMappingSpecBridge(TypeMaterialisationMacro):
    """Thin TMS bridge that forwards the spec macro call to the repo dbt runtime macro."""

    def generate_dbt_macro(self) -> str:
        return """
{% macro reference_lookup_mapping_bridge(
    reference_type,
    source_system,
    ref_alias,
    output_column,
    source_code_expression=none,
    source_code_column=none,
    mapping_table=none,
    code_table=none,
    code_column=none,
    key_column=none,
    as_of_date_expr=none,
    case_insensitive_match=false,
    required=false
) %}
    {{ reference_lookup_mapping(
        reference_type=reference_type,
        source_system=source_system,
        ref_alias=ref_alias,
        output_column=output_column,
        source_code_expression=source_code_expression,
        source_code_column=source_code_column,
        mapping_table=mapping_table,
        code_table=code_table,
        code_column=code_column,
        key_column=key_column,
        as_of_date_expr=as_of_date_expr,
        case_insensitive_match=case_insensitive_match,
        required=required
    ) }}
{% endmacro %}
""".strip()


reference_lookup_mapping_bridge = ReferenceLookupMappingSpecBridge()
