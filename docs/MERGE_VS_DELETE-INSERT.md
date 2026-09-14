| Case | Example | `delete+insert` TMS-style | simple `merge` model |
|---|---|---:|---:|
| First load | Insert first customer row | Supported | Supported |
| No change rerun | Same `CUSTOMER_ID`, same hash | Supported | Supported |
| Forward change | Active -> Closed at newer `UPDATED_DATETIME` | Supported | Supported |
| Close old current row | Old row becomes `IS_CURRENT_FLAG = N` | Supported | Supported |
| Insert new current row | New row becomes `IS_CURRENT_FLAG = Y` | Supported | Supported |
| Same hash, newer timestamp | Same customer state observed later | Supported, skips after fix | Supported, skips |
| Late-arriving historical row | New row should sit between 2021 and 2024 versions | Supported | Not fully supported |
| Recalculate next row boundary | Insert 2023 row, update 2024 row’s previous window | Supported | Not supported |
| Duplicate hash boundary collapse | 2021 hash `A`, 2024 hash `A` should collapse | Supported | Limited |
| Multiple changes for same key in one run | Customer has 2022, 2023, 2024 versions in source | Supported if source provides versions | Limited |
| Delete marker version | Insert current row with `IS_DELETED_FLAG = Y` | Supported if configured | Limited/custom |
| Full affected timeline rebuild | Rebuild all rows for one customer key | Supported | Not supported |
| Lower write volume | Only update/insert changed rows | No, rewrites affected key window | Yes |
| Better audit stability | Avoid restamping unchanged rows | Supported after patch | Supported if coded carefully |
| Simpler logic | Easy to reason locally | Medium complexity | Simpler |
| Safer general SCD2 correctness | Handles edge cases and windows | Strong | Weaker |

Example: forward-only change, both work

```text
Before:
123 | 2021-01-01 | 9999-12-31 | current=Y | hash=A

Source:
123 | 2024-01-01 | hash=B

After:
123 | 2021-01-01 | 2023-12-31 | current=N | hash=A
123 | 2024-01-01 | 9999-12-31 | current=Y | hash=B
```

Example: late-arriving row, only TMS-style is safe

```text
Before:
123 | 2021-01-01 | 2023-12-31 | current=N | hash=A
123 | 2024-01-01 | 9999-12-31 | current=Y | hash=C

Late source arrives:
123 | 2023-01-01 | hash=B

Correct after:
123 | 2021-01-01 | 2022-12-31 | current=N | hash=A
123 | 2023-01-01 | 2023-12-31 | current=N | hash=B
123 | 2024-01-01 | 9999-12-31 | current=Y | hash=C
```

A simple `merge` usually only knows how to close the current row and insert a new current row. It does not naturally go back and recalculate the old 2021 row and the existing 2024 row.

So my recommendation: use `merge` only if your source is guaranteed forward-only and one latest row per customer. Use TMS/delete+insert if you need robust SCD2 history correctness.


| Area | `delete+insert` TMS-style | simple `merge` model |
|---|---|---|
| Write volume | Higher. Deletes and reinserts the affected business key window. | Lower. Usually updates one old current row and inserts one new row. |
| Best case rerun | After the fix, should be `0` rows affected when no source change. | Should also be `0` rows affected when no source change. |
| Forward-only change | More expensive than needed because it may rewrite history for the key. | Usually faster: one update + one insert per changed key. |
| Late-arriving change | More expensive, but correct because it rebuilds the window. | Can be faster, but often incomplete/wrong unless extra logic is added. |
| Large table scan | Can be heavier because affected keys join back to existing history. | Usually lighter if filtered to current rows only. |
| Historical row volume | Cost grows with number of versions per affected business key. | Cost mostly grows with number of changed incoming rows. |
| Snowflake micro-partitions | More delete/reinsert churn, can create more table maintenance pressure. | Less churn for simple forward changes. |
| Audit churn | Higher unless TMS preserves existing audit fields, which we patched. | Lower if update/insert logic is careful. |
| Complexity cost | Runtime SQL can be heavier, more CTEs/window functions. | Simpler SQL for forward-only SCD2. |
| Safety vs speed | Optimized for correctness. | Optimized for speed in simple cases. |

For `CARD_CUSTOMER`, if the source is always “latest customer only” and changes only move forward, `merge` should be faster.

Roughly:

```text
delete+insert:
changed customer -> delete/reinsert that customer’s full history

merge:
changed customer -> update old current row + insert one new current row
```

So for 10 changed customers:

```text
delete+insert may rewrite 20+ rows depending history
merge writes about 20 rows
```

For 100k unchanged customers:

```text
both should write 0 rows if change detection is correct
```

The main performance risk with `delete+insert` is not the final row count; it is the amount of historical window rebuilding and physical rewrite. The main performance risk with `merge` is correctness logic becoming complex if you later need late-arriving or multi-version changes.