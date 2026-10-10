SELECT like_id, user_id, video_id, retracted_at FROM VideoLike WHERE retracted_at IS NULL LIMIT 1;

SELECT like_id, retracted_at FROM VideoLike WHERE like_id = :like_id;
SELECT COUNT(*) FROM EngagementSignal WHERE like_id = :like_id AND signal_type = 'like_retracted';

BEGIN IMMEDIATE;
    UPDATE VideoLike SET retracted_at = '2026-09-01T10:00:00Z' WHERE like_id = :like_id AND retracted_at IS NULL;

    INSERT INTO EngagementSignal (user_id, video_id, impression_id, signal_type, created_at, share_destination, like_id)
    SELECT user_id, video_id, impression_id, 'like_retracted', '2026-09-01T10:00:00Z', NULL, like_id FROM VideoLike WHERE like_id = :like_id;

    SELECT retracted_at FROM VideoLike WHERE like_id = :like_id;

    INSERT INTO EngagementSignal (user_id, video_id, signal_type, created_at) VALUES (:user_id, :video_id, 'not_a_real_signal', '2026-09-01T10:00:00Z');
ROLLBACK;   

SELECT like_id, retracted_at FROM VideoLike WHERE like_id = :like_id;
SELECT COUNT(*) FROM EngagementSignal WHERE like_id = :like_id AND signal_type = 'like_retracted';



SELECT video_id FROM v_video_current_state WHERE current_state = 'live' LIMIT 1;
SELECT current_state FROM v_video_current_state WHERE video_id = :video_id;

BEGIN IMMEDIATE;
    INSERT INTO ModerationDecision (video_id, to_state, decided_at, decided_by_kind, reviewer_id, classifier_version, reason) VALUES (:video_id, 'taken_down', '2026-09-01T11:00:00Z', 'human', :reviewer_id, NULL, 'policy violation');

SELECT current_state FROM v_video_current_state WHERE video_id = :video_id;
SELECT current_state FROM v_video_current_state WHERE video_id = :video_id;

ROLLBACK;

SELECT current_state FROM v_video_current_state WHERE video_id = :video_id;


SELECT user_id, handle FROM AppUser WHERE user_id NOT IN (SELECT user_id FROM HandleChange) LIMIT 1;
BEGIN IMMEDIATE;
    INSERT INTO HandleChange (user_id, old_handle, new_handle, changed_at) VALUES (:uid, :h0, 'alpha_one', '2026-01-10T09:00:00Z');          
    INSERT INTO HandleChange (user_id, old_handle, new_handle, changed_at) VALUES (:uid, 'alpha_one', 'beta_two', '2026-04-10T09:00:00Z');   
    INSERT INTO HandleChange (user_id, old_handle, new_handle, changed_at) VALUES (:uid, 'beta_two', 'gamma_three', '2026-06-10T09:00:00Z'); 
COMMIT;

SELECT COUNT(*) FROM HandleChange WHERE user_id = :uid;
SELECT handle FROM AppUser WHERE user_id = :uid;


BEGIN IMMEDIATE;
    UPDATE AppUser SET display_name = display_name WHERE user_id = :uid;  

BEGIN IMMEDIATE;
    UPDATE AppUser SET display_name = 'X' WHERE user_id = :uid;
COMMIT;
ROLLBACK;
