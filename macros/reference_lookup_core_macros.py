from type_materialisation.macro_api import TypeMaterialisationMacro


class ReferenceLookupCoreSpecBridge(TypeMaterialisationMacro):
    """TMS bridge for direct lookups against a parent reference core table."""

    def generate_dbt_macro(self) -> str:
        return """
{% macro reference_lookup_core_bridge(
    reference_type,
    ref_alias,
    output_column,
    source_code_expression=none,
    source_code_column=none,
    code_table=none,
    reference_database=none,
    code_column=none,
    value_column=none,
    as_of_date_expr=none,
    case_insensitive_match=false,
    required=false
) %}
    {{ reference_lookup_core(
        reference_type=reference_type,
        ref_alias=ref_alias,
        output_column=output_column,
        source_code_expression=source_code_expression,
        source_code_column=source_code_column,
        code_table=code_table,
        reference_database=reference_database,
        code_column=code_column,
        value_column=value_column,
        as_of_date_expr=as_of_date_expr,
        case_insensitive_match=case_insensitive_match,
        required=required
    ) }}
{% endmacro %}
""".strip()


reference_lookup_core_bridge = ReferenceLookupCoreSpecBridge()
