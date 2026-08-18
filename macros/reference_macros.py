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

