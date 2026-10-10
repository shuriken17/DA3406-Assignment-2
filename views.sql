DROP VIEW IF EXISTS v_public_profile;
CREATE VIEW v_public_profile AS SELECT u.user_id,u.handle,u.display_name, (SELECT COUNT(*) FROM Follow f WHERE f.followee_id = u.user_id AND f.ended_at IS NULL) AS follower_count FROM AppUser u WHERE u.account_state = 'active';


DROP VIEW IF EXISTS v_video_current_state;
CREATE VIEW v_video_current_state AS SELECT d.video_id,d.to_state AS current_state,d.decided_at AS state_since,d.decided_by_kind,d.reviewer_id,d.classifier_version FROM ModerationDecision d WHERE d.decision_id = (SELECT d2.decision_id FROM ModerationDecision d2 WHERE d2.video_id = d.video_id ORDER BY d2.decided_at DESC, d2.decision_id DESC LIMIT 1);


DROP VIEW IF EXISTS v_creator_tier_current;
CREATE VIEW v_creator_tier_current AS SELECT p.user_id AS creator_id,p.tier_code,t.rank_order,t.rev_share, p.valid_from   AS tier_since FROM CreatorTierPeriod p JOIN MonetisationTier t ON t.tier_code = p.tier_code WHERE p.valid_to IS NULL;


DROP VIEW IF EXISTS v_video_daily_engagement;
CREATE VIEW v_video_daily_engagement AS
WITH day_spine AS (SELECT video_id, date(shown_at)   AS day FROM Impression UNION SELECT video_id, date(created_at) AS day FROM EngagementSignal),
seg_per_impression AS (SELECT impression_id, SUM(watched_ms) AS watched_ms, MAX(reached_end) AS reached_end FROM ViewSegment GROUP BY impression_id),
impr AS (SELECT i.video_id, date(i.shown_at) AS day, COUNT(*) AS impressions, SUM(CASE WHEN s.impression_id IS NOT NULL THEN 1 ELSE 0 END) AS views, COALESCE(SUM(s.watched_ms), 0) / 1000.0 AS watch_seconds, SUM(COALESCE(s.reached_end, 0)) AS completions FROM Impression i LEFT JOIN seg_per_impression s ON s.impression_id = i.impression_id GROUP BY i.video_id, date(i.shown_at)),
lik AS (SELECT video_id, date(created_at) AS day, SUM(CASE WHEN signal_type = 'like' THEN  1 WHEN signal_type = 'like_retracted' THEN -1 ELSE 0 END) AS net_likes FROM EngagementSignal WHERE signal_type IN ('like','like_retracted') GROUP BY video_id, date(created_at))
SELECT d.video_id, d.day, COALESCE(i.impressions, 0) AS impressions,COALESCE(i.views, 0) AS views,COALESCE(i.watch_seconds, 0) AS watch_seconds,COALESCE(i.completions, 0) AS completions,COALESCE(l.net_likes, 0) AS net_likes FROM day_spine d LEFT JOIN impr i ON i.video_id = d.video_id AND i.day = d.day LEFT JOIN lik l ON l.video_id = d.video_id AND l.day = d.day;

DROP VIEW IF EXISTS v_turn_cost;
CREATE VIEW v_turn_cost AS SELECT t.turn_id, t.session_id, s.user_id, t.created_at,t.model_id, m.model_name, t.template_version_id,u.input_tokens, u.output_tokens, u.cached_tokens,p.price_id,ROUND( (u.input_tokens - u.cached_tokens) / 1000.0 * p.input_rate +  u.cached_tokens/ 1000.0 * p.cached_rate +  u.output_tokens/ 1000.0 * p.output_rate, 8) AS cost_usd FROM AgentTurn t JOIN AgentSession s ON s.session_id = t.session_id JOIN TurnUsage u ON u.turn_id = t.turn_id JOIN LlmModel m ON m.model_id = t.model_id JOIN ModelPrice p ON p.model_id = t.model_id AND t.created_at >= p.valid_from AND (p.valid_to IS NULL OR t.created_at < p.valid_to);