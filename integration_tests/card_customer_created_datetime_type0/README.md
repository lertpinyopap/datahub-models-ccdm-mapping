# CARD_CUSTOMER Type 0 and SCD2 Integration Test

This live Snowflake scenario verifies that `CREATED_DATETIME` is a Type 0
attribute for a CARD_CUSTOMER-style derived SCD2 load.

The test uses an isolated, prefixed target table and four source fixtures:

1. Initial load creates `C001` with `CREATED_DATETIME = 2020-01-01`.
2. The source changes only `CREATED_DATETIME` to `1999-01-01`; no new version
   is created and the target retains `2020-01-01`.
3. The source changes status and effective date; a new SCD2 version is created
   and it still carries `CREATED_DATETIME = 2020-01-01`.
4. The unchanged rerun creates no duplicate version.

## Run

The test uses the TMS integration framework from the local
`datahub-type-materialisation-specification` submodule and a Snowflake CLI
connection in `~/.snowflake/config.toml`.

```bash
[connections.tms_int]
account = "LFSORG-LFS_DATAHUB_NONPROD"
user = <username>
authenticator = "externalbrowser"
database = "SAS_MIGRATION_WORKSPACE"
schema = "TMP"
warehouse = "WH_SCIM_NP_SNOWFLAKE_DATAENGINEER_XSMALL"
role = "SCIM_NP_SNOWFLAKE_DATAENGINEER"
```

```bash
export PATH="$PWD/libs/tms-env/bin:$PWD/.venv/bin:$PATH"

TMS_RUN_INTEGRATION=1 \
TMS_SNOWFLAKE_CONNECTION=tms_int \
.venv/bin/python -m pytest integration_tests/test_card_customer_created_datetime_type0.py
```

The scenario assumes the default `TMS_INTEGRATION_TABLE_PREFIX=TMS_INT__`.
If you choose a different prefix, update each
`card_customer_type0_target` value in `scenario.yaml` to match the prefixed
target table name.

Use `TMS_INTEGRATION_KEEP_TABLES=1` when you want to inspect the generated
source, validation, and target relations after the test.
