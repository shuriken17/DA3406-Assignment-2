# ScrollSense: Assignment 2

The ScrollSense database from A1, scaled up 50 times, with the index, join, pushdown and concurrency experiments from the report.

## Requirements

Python 3 (standard library only) and an SQLite client, version 3.44 or newer.

## Files

| File | What it is |
|---|---|
| `schema.sql`, `views.sql`, `queries.sql`, `transactions.sql` | From A1, unchanged |
| `generate_data.py` | The A1 generator, changed for scale 50 (see the report) |
| `indexes.sql` | The three indexes of Task 2 |
| `F1_rewritten.sql`, `F7_pushed.sql`, `F12_forced.sql` | Query versions used in Tasks 2, 3.3 and 4 |
| `concurrency_demo.sql` | The script for Task 5.3 |
| `plan_analysis.md` | Full plans, run times and row counts |

## How to run

1. `python generate_data.py` builds `scrollsense.db`. It replaces any old copy if exists.
2. Run `views.sql` once. `transactions.sql` needs the views.
3. `queries.sql` and the three `F` files only read data.
4. Run `indexes.sql` on a copy of the database. The "before" times in the report are without these indexes, and the F7 index makes F7 slower.
5. `concurrency_demo.sql` needs two connections to the same database. Run one statement at a time. It changes data, so use a copy.
