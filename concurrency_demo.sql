-- Task 5.3: DBeaver, scratch copy demo.db. Tab A = connection "demo", tab B = connection "demoB". Auto-commit. One statement at a time.
-- Test row: like_id = 8.

-- PART 1

-- check. Expect: NULL | 0
SELECT retracted_at, (SELECT COUNT(*) FROM EngagementSignal WHERE like_id = 8 AND signal_type = 'like_retracted') AS retraction_signals FROM VideoLike WHERE like_id = 8;

-- [tab A] read. Expect: NULL
SELECT retracted_at FROM VideoLike WHERE like_id = 8;
-- [tab B] read. Expect: NULL
SELECT retracted_at FROM VideoLike WHERE like_id = 8;

-- [tab A] retract
BEGIN;
UPDATE VideoLike SET retracted_at = '2026-09-01T10:00:01Z' WHERE like_id = 8;
INSERT INTO EngagementSignal (user_id, video_id, impression_id, signal_type, created_at, share_destination, like_id) SELECT user_id, video_id, impression_id, 'like_retracted', '2026-09-01T10:00:01Z', NULL, like_id FROM VideoLike WHERE like_id = 8;
COMMIT;

-- [tab B] retract
BEGIN;
UPDATE VideoLike SET retracted_at = '2026-09-01T10:00:02Z' WHERE like_id = 8;
INSERT INTO EngagementSignal (user_id, video_id, impression_id, signal_type, created_at, share_destination, like_id) SELECT user_id, video_id, impression_id, 'like_retracted', '2026-09-01T10:00:02Z', NULL, like_id FROM VideoLike WHERE like_id = 8;
COMMIT;

-- check. Result: 2026-09-01T10:00:02Z | 2
SELECT retracted_at, (SELECT COUNT(*) FROM EngagementSignal WHERE like_id = 8 AND signal_type = 'like_retracted') AS retraction_signals FROM VideoLike WHERE like_id = 8;

-- [tab A] reset, then check again. Expect: NULL | 0
UPDATE VideoLike SET retracted_at = NULL WHERE like_id = 8;
DELETE FROM EngagementSignal WHERE like_id = 8 AND signal_type = 'like_retracted';

-- PART 2

-- [tab A]
BEGIN IMMEDIATE;
-- [tab B] Result: waits about 3 seconds, then "database is locked"
BEGIN IMMEDIATE;
-- [tab A] read, write, commit
SELECT retracted_at FROM VideoLike WHERE like_id = 8;
UPDATE VideoLike SET retracted_at = '2026-09-01T10:00:01Z' WHERE like_id = 8;
INSERT INTO EngagementSignal (user_id, video_id, impression_id, signal_type, created_at, share_destination, like_id) SELECT user_id, video_id, impression_id, 'like_retracted', '2026-09-01T10:00:01Z', NULL, like_id FROM VideoLike WHERE like_id = 8;
COMMIT;
-- [tab B] retry. Result: sees 2026-09-01T10:00:01Z and skips its writes
BEGIN IMMEDIATE;
SELECT retracted_at FROM VideoLike WHERE like_id = 8;
ROLLBACK;

-- check. Result: 2026-09-01T10:00:01Z | 1
SELECT retracted_at, (SELECT COUNT(*) FROM EngagementSignal WHERE like_id = 8 AND signal_type = 'like_retracted') AS retraction_signals FROM VideoLike WHERE like_id = 8;