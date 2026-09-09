from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
TMS_SOURCE = REPO_ROOT / "datahub-type-materialisation-specification" / "src"
TMS_INTEGRATION_SOURCE = (
    REPO_ROOT / "datahub-type-materialisation-specification" / "integration_tests" / "src"
)
SCENARIO_ROOT = REPO_ROOT / "integration_tests" / "card_customer_created_datetime_type0"


def test_card_customer_created_datetime_is_type0_across_initial_and_incremental_loads(
    tmp_path: Path,
) -> None:
    """Run the repository-owned Type 0/SCD2 scenario against Snowflake."""
    if os.environ.get("TMS_RUN_INTEGRATION") != "1":
        pytest.skip("set TMS_RUN_INTEGRATION=1 to run live Snowflake integration tests")
    if not TMS_SOURCE.is_dir() or not TMS_INTEGRATION_SOURCE.is_dir():
        pytest.fail("the datahub-type-materialisation-specification submodule is required for integration tests")

    sys.path[:0] = [str(TMS_SOURCE), str(TMS_INTEGRATION_SOURCE)]
    from tms_integration.runner import run_live_scenario
    from tms_integration.scenario import load_scenario

    scenario = load_scenario(SCENARIO_ROOT)
    run_live_scenario(scenario, tmp_path)
