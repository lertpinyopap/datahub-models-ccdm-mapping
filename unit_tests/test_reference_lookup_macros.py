from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
EXAMPLES_DIR = REPO_ROOT / "unit_tests" / "examples" / "reference_lookup"


class ReferenceLookupMacroTests(unittest.TestCase):
    def assert_file_contains(self, file_path: Path, *expected_fragments: str) -> None:
        content = file_path.read_text(encoding="utf-8")
        for fragment in expected_fragments:
            self.assertIn(fragment, content, msg=f"{file_path.name} missing fragment: {fragment}")

    def assert_example_contains(self, example_name: str, *expected_fragments: str) -> None:
        example_path = EXAMPLES_DIR / example_name
        self.assert_file_contains(example_path, *expected_fragments)

    def test_reference_lookup_mapping_macro_supports_resolution_effective_dating_and_current_row(self) -> None:
        macro_path = REPO_ROOT / "macros" / "reference_lookup_mapping.sql"
        self.assert_file_contains(
            macro_path,
            "{% macro reference_lookup_mapping(",
            "mapping_relation",
            "code_relation",
            "var('ENV_PREFIX'",
            "reference_database=none",
            "mapping.TARGET_CODE",
            "code.*",
            "VALID_FROM_DATETIME",
            "VALID_TO_DATETIME",
            "timestamp_ltz",
            "IS_CURRENT_FLAG",
            "IS_DELETED_FLAG",
            "current_timestamp()",
            "row_number() over",
        )

    def test_reference_lookup_core_macro_supports_effective_dating_and_current_row(self) -> None:
        macro_path = REPO_ROOT / "macros" / "reference_lookup_core.sql"
        self.assert_file_contains(
            macro_path,
            "{% macro reference_lookup_core(",
            "code_relation",
            "code.*",
            "var('ENV_PREFIX'",
            "reference_database=none",
            "resolved_value_column",
            "VALID_FROM_DATETIME",
            "VALID_TO_DATETIME",
            "timestamp_ltz",
            "IS_CURRENT_FLAG",
            "IS_DELETED_FLAG",
            "current_timestamp()",
            "row_number() over",
        )

    def test_runtime_lookup_macros_exist(self) -> None:
        self.assertTrue((REPO_ROOT / "macros" / "reference_lookup_core.sql").exists())
        self.assertTrue((REPO_ROOT / "macros" / "reference_lookup_mapping.sql").exists())


def _add_example_test(method_name: str, example_name: str, *expected_fragments: str) -> None:
    def test_method(self: ReferenceLookupMacroTests) -> None:
        self.assert_example_contains(example_name, *expected_fragments)

    setattr(ReferenceLookupMacroTests, method_name, test_method)


_add_example_test(
    "test_core_country_input_au_expected_country_key",
    "sample_reference_lookup_core_country.sql",
    "select 'AU' as source_code",
    "ref.*",
    "{{ reference_lookup_core(",
    "reference_type='COUNTRY'",
    "output_column='COUNTRY_KEY'",
)
_add_example_test(
    "test_core_currency_input_aud_expected_currency_key",
    "sample_reference_lookup_core_currency.sql",
    "select 'AUD' as source_code",
    "ref.*",
    "{{ reference_lookup_core(",
    "reference_type='CURRENCY'",
    "output_column='CURRENCY_KEY'",
)
_add_example_test(
    "test_core_financial_institution_input_lfsau_expected_financial_institution_key",
    "sample_reference_lookup_core_financial_institution.sql",
    "select 'LFSAU' as source_code",
    "ref.*",
    "{{ reference_lookup_core(",
    "reference_type='FINANCIAL_INSTITUTION'",
    "output_column='FINANCIAL_INSTITUTION_KEY'",
)
_add_example_test(
    "test_core_brand_input_lfsau_expected_brand_key",
    "sample_reference_lookup_core_brand.sql",
    "select 'LFSAU' as source_code",
    "ref.*",
    "{{ reference_lookup_core(",
    "reference_type='BRAND'",
    "output_column='BRAND_KEY'",
)
_add_example_test(
    "test_core_product_input_ccaugem_expected_product_key",
    "sample_reference_lookup_core_product.sql",
    "select 'CCAUGEM' as source_code",
    "ref.*",
    "{{ reference_lookup_core(",
    "reference_type='PRODUCT'",
    "output_column='PRODUCT_KEY'",
)
_add_example_test(
    "test_mapping_country_input_v10_aus_expected_target_code_au_and_country_key",
    "sample_reference_lookup_mapping_country.sql",
    "select 'V10' as source_system, 'AUS' as source_code",
    "ref.*",
    "{{ reference_lookup_mapping(",
    "reference_type='COUNTRY'",
    "source_system='V10'",
    "output_column='COUNTRY_KEY'",
)
_add_example_test(
    "test_mapping_currency_input_v10_036_expected_target_code_aud_and_currency_key",
    "sample_reference_lookup_mapping_currency.sql",
    "select 'V10' as source_system, '036' as source_code",
    "ref.*",
    "{{ reference_lookup_mapping(",
    "reference_type='CURRENCY'",
    "source_system='V10'",
    "output_column='CURRENCY_KEY'",
)
_add_example_test(
    "test_mapping_financial_institution_input_v10_101_expected_financial_institution_key",
    "sample_reference_lookup_mapping_financial_institution.sql",
    "select 'V10' as source_system, '101' as source_code",
    "ref.*",
    "{{ reference_lookup_mapping(",
    "reference_type='FINANCIAL_INSTITUTION'",
    "source_system='V10'",
    "output_column='FINANCIAL_INSTITUTION_KEY'",
)
_add_example_test(
    "test_mapping_brand_input_v10_300_expected_brand_key",
    "sample_reference_lookup_mapping_brand.sql",
    "select 'V10' as source_system, '300' as source_code",
    "ref.*",
    "{{ reference_lookup_mapping(",
    "reference_type='BRAND'",
    "source_system='V10'",
    "output_column='BRAND_KEY'",
)
_add_example_test(
    "test_mapping_product_input_v10_4501_expected_product_key",
    "sample_reference_lookup_mapping_product.sql",
    "select 'V10' as source_system, '4501' as source_code",
    "ref.*",
    "{{ reference_lookup_mapping(",
    "reference_type='PRODUCT'",
    "source_system='V10'",
    "output_column='PRODUCT_KEY'",
)


if __name__ == "__main__":
    unittest.main()
