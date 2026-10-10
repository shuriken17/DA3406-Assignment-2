# plan_analysis

Supporting data for the report: the full plans, the run times and the row counts. The explanations are in the report.

## Files

| File | What it is |
|---|---|
| `schema.sql`, `views.sql`, `queries.sql`, `transactions.sql` | A1 files, unchanged |
| `generate_data.py` | A1 generator with the two changes from the report (`SCALE = 50`) |
| `indexes.sql` | The three indexes of Task 2 |
| `concurrency_demo.sql` | The Task 5.3 script |
| `F1_rewritten.sql`, `F7_pushed.sql`, `F12_forced.sql` | Query versions used in Tasks 2, 3.3 and 4 |
| `a2_lab.py`, `run_batch.py` | Helper scripts for plans, run times and the index experiments |
| `results_batch.txt` | Raw log of the index experiments |

## Row counts (scale 50)

| Table | Rows | x A1 |
|---|---:|---:|
| AppUser | 250,000 | 50.0 |
| Video | 1,000,000 | 50.0 |
| AudioTrack | 45,000 | 50.0 |
| ModerationDecision | 2,345,054 | 50.0 |
| Follow | 2,987,171 | 51.0 |
| Impression | 15,400,863 | 50.0 |
| ViewSegment | 6,732,140 | 50.0 |
| VideoLike | 252,948 | 50.5 |
| EngagementSignal | 492,497 | 50.8 |
| AgentSession | 100,000 | 50.0 |
| AgentTurn | 259,760 | 50.1 |
| ToolCall | 585,519 | 50.3 |
| Recommendation | 643,155 | 50.0 |
| CreatorTierPeriod | 112,253 | 49.4 |
| ModelPrice | 8 | 1.0 |

ModelPrice is a small fixed table, so it stays at 8.

## Task 1: baseline plans

**F12**

```
SCAN s
SEARCH i USING INDEX ix_impression_user (user_id=?)
SEARCH r USING INTEGER PRIMARY KEY (rowid=?)
SEARCH vs USING INDEX sqlite_autoindex_ViewSegment_1 (impression_id=?)
SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

**F10**

```
CO-ROUTINE (subquery-5)
  CO-ROUTINE (subquery-6)
    MATERIALIZE r
      CO-ROUTINE (subquery-7)
        MATERIALIZE d
          SCAN s
          SEARCH i USING INTEGER PRIMARY KEY (rowid=?)
          SEARCH v USING INTEGER PRIMARY KEY (rowid=?)
          USE TEMP B-TREE FOR GROUP BY
        SCAN d
        USE TEMP B-TREE FOR ORDER BY
      SCAN (subquery-7)
    MATERIALIZE a
      SEARCH d
    SCAN a
    SCAN r
    BLOOM FILTER ON p (creator_id=? AND day=?)
    SEARCH p USING AUTOMATIC COVERING INDEX (creator_id=? AND day=?) LEFT-JOIN
    USE TEMP B-TREE FOR ORDER BY
  SCAN (subquery-6)
SCAN (subquery-5)
USE TEMP B-TREE FOR ORDER BY
```

**F1**

```
MATERIALIZE a
  SEARCH Video
SCAN t
SEARCH v USING INDEX ix_video_track (audio_track_id=?)
SCAN a
USE TEMP B-TREE FOR ORDER BY
```

## Task 2: plans before and after

**F1 as written, before**

```
MATERIALIZE a
  SEARCH Video
SCAN t
SEARCH v USING INDEX ix_video_track (audio_track_id=?)
SCAN a
USE TEMP B-TREE FOR ORDER BY
```

**F1 as written, with the index**

```
MATERIALIZE a
  SEARCH Video USING COVERING INDEX idx_video_track_uploaded
SCAN t
SEARCH v USING COVERING INDEX idx_video_track_uploaded (audio_track_id=?)
SCAN a
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

**F1 rewritten, before**

```
SCAN t
SEARCH v USING INDEX ix_video_track (audio_track_id=?)
SCALAR SUBQUERY 1
  SEARCH Video
USE TEMP B-TREE FOR ORDER BY
```

**F1 rewritten, with the index**

```
SCAN t
SEARCH v USING COVERING INDEX idx_video_track_uploaded (audio_track_id=? AND uploaded_at>?)
SCALAR SUBQUERY 1
  SEARCH Video USING COVERING INDEX idx_video_track_uploaded
USE TEMP B-TREE FOR count(DISTINCT)
USE TEMP B-TREE FOR ORDER BY
```

**F1 rewritten, with the reversed index**

```
SCAN t
SEARCH v USING INDEX ix_video_track (audio_track_id=?)
SCALAR SUBQUERY 1
  SEARCH Video USING COVERING INDEX idx_video_up_track
USE TEMP B-TREE FOR ORDER BY
```

**F12, before**

```
SCAN s
SEARCH i USING INDEX ix_impression_user (user_id=?)
SEARCH r USING INTEGER PRIMARY KEY (rowid=?)
SEARCH vs USING INDEX sqlite_autoindex_ViewSegment_1 (impression_id=?)
SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

**F12, with the index**

```
SCAN i USING COVERING INDEX idx_imp_rec_user_p
SEARCH r USING INTEGER PRIMARY KEY (rowid=?)
SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
SEARCH vs USING INDEX sqlite_autoindex_ViewSegment_1 (impression_id=?)
SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

**F7, before**

```
MATERIALIZE a
  SEARCH AgentTurn USING COVERING INDEX ix_turn_created
SCAN t USING INDEX sqlite_autoindex_AgentTurn_1
SEARCH u USING INTEGER PRIMARY KEY (rowid=?)
SCAN mp
SCAN a
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

**F7, with the index**

```
MATERIALIZE a
  SEARCH AgentTurn USING COVERING INDEX ix_turn_created
SCAN mp
SEARCH t USING INDEX idx_turn_model_created (model_id=? AND created_at>?)
SEARCH u USING INTEGER PRIMARY KEY (rowid=?)
SCAN a
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

## Task 3.3 and Task 4: other plans

**F12, order forced to start with Recommendation**

```
SCAN r USING INDEX sqlite_autoindex_Recommendation_2
SEARCH t USING INTEGER PRIMARY KEY (rowid=?)
SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
SEARCH i USING INDEX ix_impression_rec (recommendation_id=?)
SEARCH vs USING INDEX sqlite_autoindex_ViewSegment_1 (impression_id=?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

**F7, filter pushed down** (F7 as written has the same plan as "F7, before" above)

```
SCAN t USING INDEX sqlite_autoindex_AgentTurn_1
SCALAR SUBQUERY 2
  CO-ROUTINE a
    SEARCH AgentTurn USING COVERING INDEX ix_turn_created
  SCAN a
SEARCH u USING INTEGER PRIMARY KEY (rowid=?)
SCAN mp
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

## Run times (ms)

All times are wall-clock. The last column is the median.

| Experiment | Runs | Median |
|---|---|---:|
| F1 as written, before | 9,929.8, 5,699.8, 15,586.6, 7,541.5, 2,463.5 | 7,541.5 |
| F1 as written, with the index | 669.1, 572.7, 574.4, 660.4, 561.0 | 574.4 |
| F1 rewritten, before | 2,658.0, 2,416.6, 2,479.8, 2,617.8, 2,519.2 | 2,519.2 |
| F1 rewritten, with the index | 122.9, 116.7, 97.5, 96.5, 97.6 | 97.6 |
| F1 rewritten, with the reversed index | 3,218.7, 18,351.1, 9,043.8, 2,572.1, 2,515.8 | 3,218.7 |
| F12, before | 179,799.0, 240,756.7, 238,652.3 | 238,652.3 |
| F12, before (earlier run on the baseline) | 68,586.8, 37,612.4, 37,737.4 | 37,737.4 |
| F12, with the index | 969.6, 924.6, 915.9, 1,604.3, 1,631.7 | 969.6 |
| F12, forced order | 2,125.1, 506.6, 517.1 | 517.1 |
| F7, before | 328.4, 321.2, 326.2, 321.4, 320.6, 315.8 | 321.3 |
| F7, with the index | 697.2, 706.7, 718.1, 726.0, 778.6, 696.2 | 712.4 |
| F7, index dropped again | 320.2, 321.1, 332.0, 339.8, 323.1, 332.3 | 327.5 |
| F7 as written | 840.2, 332.2, 329.6, 373.1, 337.1 | 337.1 |
| F7, filter pushed down | 176.4, 110.1, 106.5, 111.2, 112.7 | 111.2 |

The two F7 index runs in `results_batch.txt` (medians 2,574.1 and 4,722.5) were taken while the machine was slow, so the report uses the six-run measurement above.

## Concurrency demo (Task 5.3), like 8

Check after the two tabs retract without the fix:

```
retracted_at = 2026-09-01T10:00:02Z | retraction signals = 2
```

With `BEGIN IMMEDIATE`: tab B waited about 3 seconds and then failed with `database is locked`. After tab A committed, tab B's second try saw the like already retracted and did nothing:

```
retracted_at = 2026-09-01T10:00:01Z | retraction signals = 1
```
