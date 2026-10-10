PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;


CREATE TABLE AppUser (user_id INTEGER PRIMARY KEY, handle TEXT NOT NULL, display_name TEXT NOT NULL, auth_provider TEXT NOT NULL CHECK (auth_provider IN ('phone','google')), phone TEXT NULL, email TEXT NULL, account_state TEXT NOT NULL DEFAULT 'active' CHECK (account_state IN ('active','deactivated','pending_deletion')), deletion_requested_at TEXT NULL, created_at TEXT NOT NULL, CHECK ( (auth_provider = 'phone'  AND phone IS NOT NULL AND email IS NULL) OR (auth_provider = 'google' AND email IS NOT NULL AND phone IS NULL) ), CHECK ( (account_state = 'pending_deletion') = (deletion_requested_at IS NOT NULL) ));
CREATE UNIQUE INDEX ux_appuser_handle ON AppUser (handle COLLATE NOCASE);

CREATE TABLE HandleChange (change_id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE, old_handle TEXT NOT NULL, new_handle TEXT NOT NULL, changed_at TEXT NOT NULL, CHECK (old_handle <> new_handle));

CREATE TABLE InterestCategory (category_id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);

CREATE TABLE UserDeclaredInterest (user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE, category_id INTEGER NOT NULL REFERENCES InterestCategory(category_id) ON DELETE RESTRICT, declared_at TEXT NOT NULL, PRIMARY KEY (user_id, category_id));

CREATE TABLE UserInferredInterest (user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,category_id  INTEGER NOT NULL REFERENCES InterestCategory(category_id) ON DELETE RESTRICT,refreshed_at TEXT NOT NULL,confidence REAL NOT NULL CHECK (confidence BETWEEN 0.0 AND 1.0),PRIMARY KEY (user_id, category_id, refreshed_at));

CREATE TABLE UserInterestSuppression (user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,category_id INTEGER NOT NULL REFERENCES InterestCategory(category_id) ON DELETE RESTRICT,suppressed_at TEXT NOT NULL,lifted_at TEXT NULL,PRIMARY KEY (user_id, category_id, suppressed_at));

CREATE TABLE Follow (follow_id INTEGER PRIMARY KEY,follower_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,followee_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,started_at TEXT NOT NULL,ended_at TEXT NULL, end_reason  TEXT NULL CHECK (end_reason IN ('unfollow','block','account_removed')),CHECK (follower_id <> followee_id),CHECK (ended_at IS NULL OR ended_at >= started_at),CHECK ((ended_at IS NULL) = (end_reason IS NULL)));
CREATE UNIQUE INDEX ux_follow_open ON Follow (follower_id, followee_id) WHERE ended_at IS NULL;
CREATE INDEX ix_follow_followee ON Follow (followee_id, ended_at);

CREATE TABLE Block (blocker_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,blocked_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,created_at TEXT NOT NULL,PRIMARY KEY (blocker_id, blocked_id),CHECK (blocker_id <> blocked_id));

CREATE TABLE Mute (muter_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,muted_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,created_at TEXT NOT NULL,PRIMARY KEY (muter_id, muted_id),CHECK (muter_id <> muted_id));

CREATE TABLE MonetisationTier (tier_code TEXT PRIMARY KEY,rank_order INTEGER NOT NULL UNIQUE,rev_share REAL NOT NULL CHECK (rev_share BETWEEN 0.0 AND 1.0));

CREATE TABLE CreatorTierPeriod (period_id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,tier_code  TEXT NOT NULL REFERENCES MonetisationTier(tier_code) ON DELETE RESTRICT,valid_from TEXT NOT NULL,valid_to TEXT NULL, CHECK (valid_to IS NULL OR valid_to > valid_from));
CREATE UNIQUE INDEX ux_ctp_open ON CreatorTierPeriod (user_id) WHERE valid_to IS NULL;

CREATE TABLE AudioTrack (track_id INTEGER PRIMARY KEY, title TEXT NOT NULL, origin_kind TEXT NOT NULL CHECK (origin_kind IN ('original','licensed')), origin_video_id INTEGER NULL, catalogue_ref TEXT NULL, created_at TEXT NOT NULL, CHECK ( (origin_kind='original' AND origin_video_id IS NOT NULL AND catalogue_ref IS NULL) OR (origin_kind='licensed' AND catalogue_ref  IS NOT NULL AND origin_video_id IS NULL) ), FOREIGN KEY (origin_video_id) REFERENCES Video(video_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED);

CREATE TABLE Video (video_id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE, duration_ms INTEGER NOT NULL CHECK (duration_ms BETWEEN 20000 AND 90000), caption TEXT NOT NULL DEFAULT '' CHECK (length(caption) <= 2200), audio_track_id INTEGER NULL, uploaded_at TEXT NOT NULL, FOREIGN KEY (audio_track_id) REFERENCES AudioTrack(track_id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED);
CREATE INDEX ix_video_owner ON Video (owner_id);
CREATE INDEX ix_video_track ON Video (audio_track_id);

CREATE TABLE ModerationDecision (decision_id INTEGER PRIMARY KEY, video_id INTEGER NOT NULL REFERENCES Video(video_id) ON DELETE CASCADE, to_state TEXT NOT NULL CHECK (to_state IN ('pending','live','age_restricted','demoted','taken_down')), decided_at TEXT NOT NULL, decided_by_kind TEXT NOT NULL CHECK (decided_by_kind IN ('classifier','human')), reviewer_id INTEGER NULL REFERENCES AppUser(user_id) ON DELETE SET NULL, classifier_version TEXT NULL, reason TEXT NULL, CHECK ( (decided_by_kind='human' AND reviewer_id IS NOT NULL AND classifier_version IS NULL) OR (decided_by_kind='classifier' AND classifier_version IS NOT NULL AND reviewer_id IS NULL) ), UNIQUE (video_id, decided_at));
CREATE INDEX ix_moddec_video ON ModerationDecision (video_id, decided_at);

CREATE TABLE VideoComment (comment_id INTEGER PRIMARY KEY, video_id INTEGER NOT NULL REFERENCES Video(video_id) ON DELETE CASCADE, author_id INTEGER NULL REFERENCES AppUser(user_id) ON DELETE SET NULL, body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 2200), created_at TEXT NOT NULL);
CREATE INDEX ix_comment_video ON VideoComment (video_id, created_at);


CREATE TABLE Impression (impression_id INTEGER PRIMARY KEY, video_id INTEGER NOT NULL REFERENCES Video(video_id) ON DELETE CASCADE, user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE, shown_at TEXT NOT NULL, surface TEXT NOT NULL CHECK (surface IN ('feed','search_shelf','profile')), feed_position INTEGER NULL CHECK (feed_position IS NULL OR feed_position >= 0), ranker_model_version TEXT NOT NULL, recommendation_id INTEGER NULL REFERENCES Recommendation(recommendation_id) ON DELETE SET NULL, CHECK ( (surface='feed') = (feed_position IS NOT NULL) ));
CREATE INDEX ix_impression_video ON Impression (video_id, shown_at);
CREATE INDEX ix_impression_user ON Impression (user_id, shown_at);
CREATE INDEX ix_impression_rec ON Impression (recommendation_id);

CREATE TABLE ViewSegment (impression_id INTEGER NOT NULL REFERENCES Impression(impression_id) ON DELETE CASCADE, seq_no INTEGER NOT NULL CHECK (seq_no >= 1), started_at TEXT NOT NULL, start_offset_ms INTEGER NOT NULL CHECK (start_offset_ms >= 0), watched_ms INTEGER NOT NULL CHECK (watched_ms >= 300), reached_end INTEGER NOT NULL DEFAULT 0 CHECK (reached_end IN (0,1)), PRIMARY KEY (impression_id, seq_no));

CREATE TABLE VideoLike (like_id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE, video_id INTEGER NOT NULL REFERENCES Video(video_id) ON DELETE CASCADE, impression_id INTEGER NULL REFERENCES Impression(impression_id) ON DELETE SET NULL, liked_at TEXT NOT NULL, retracted_at TEXT NULL, CHECK (retracted_at IS NULL OR retracted_at >= liked_at));
CREATE INDEX ix_like_video ON VideoLike (video_id, liked_at);
CREATE INDEX ix_like_user  ON VideoLike (user_id, video_id, liked_at);

CREATE TABLE EngagementSignal (signal_id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE, video_id INTEGER NOT NULL REFERENCES Video(video_id) ON DELETE CASCADE, impression_id INTEGER NULL REFERENCES Impression(impression_id) ON DELETE SET NULL, signal_type TEXT NOT NULL CHECK (signal_type IN ('like','like_retracted','save','share','comment', 'follow_from_feed','not_interested','report')), created_at TEXT NOT NULL, share_destination TEXT NULL CHECK (share_destination IN ('whatsapp','instagram','copy_link')), like_id INTEGER NULL REFERENCES VideoLike(like_id) ON DELETE CASCADE, CHECK ( (signal_type='share') = (share_destination IS NOT NULL) ), CHECK ( signal_type IN ('like','like_retracted') OR like_id IS NULL ));
CREATE INDEX ix_signal_video ON EngagementSignal (video_id, created_at);
CREATE INDEX ix_signal_type  ON EngagementSignal (signal_type, created_at);


CREATE TABLE LlmModel (model_id INTEGER PRIMARY KEY,model_name TEXT NOT NULL UNIQUE, vendor TEXT NOT NULL);

CREATE TABLE ModelPrice (price_id INTEGER PRIMARY KEY,model_id INTEGER NOT NULL REFERENCES LlmModel(model_id) ON DELETE RESTRICT,valid_from TEXT NOT NULL,valid_to TEXT NULL,   input_rate REAL NOT NULL CHECK (input_rate  >= 0),output_rate REAL NOT NULL CHECK (output_rate >= 0),cached_rate REAL NOT NULL CHECK (cached_rate >= 0),CHECK (valid_to IS NULL OR valid_to > valid_from));
CREATE UNIQUE INDEX ux_price_open ON ModelPrice (model_id) WHERE valid_to IS NULL;

CREATE TABLE PromptTemplate (template_id INTEGER PRIMARY KEY,name TEXT NOT NULL UNIQUE,purpose TEXT NOT NULL);

CREATE TABLE PromptTemplateVersion (template_version_id INTEGER PRIMARY KEY,template_id INTEGER NOT NULL REFERENCES PromptTemplate(template_id) ON DELETE RESTRICT,version_no INTEGER NOT NULL CHECK (version_no >= 1),template_text TEXT NOT NULL,created_at TEXT NOT NULL,UNIQUE (template_id, version_no));

CREATE TABLE AgentSession (session_id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES AppUser(user_id) ON DELETE CASCADE,session_kind TEXT NOT NULL CHECK (session_kind IN ('why_this','conversational_search')),started_at TEXT NOT NULL,ended_at TEXT NULL,CHECK (ended_at IS NULL OR ended_at >= started_at));
CREATE INDEX ix_session_user ON AgentSession (user_id, started_at);

CREATE TABLE AgentTurn (turn_id INTEGER PRIMARY KEY,   session_id INTEGER NOT NULL REFERENCES AgentSession(session_id) ON DELETE CASCADE,turn_no INTEGER NOT NULL CHECK (turn_no >= 1),user_message TEXT NOT NULL,assistant_message TEXT NOT NULL,template_version_id INTEGER NOT NULL REFERENCES PromptTemplateVersion(template_version_id) ON DELETE RESTRICT,model_id INTEGER NOT NULL REFERENCES LlmModel(model_id) ON DELETE RESTRICT,temperature REAL NOT NULL CHECK (temperature BETWEEN 0.0 AND 2.0),created_at TEXT NOT NULL,UNIQUE (session_id, turn_no));
CREATE INDEX ix_turn_created ON AgentTurn (created_at);

CREATE TABLE TurnUsage (turn_id INTEGER PRIMARY KEY REFERENCES AgentTurn(turn_id) ON DELETE CASCADE,input_tokens INTEGER NOT NULL CHECK (input_tokens  >= 0),output_tokens INTEGER NOT NULL CHECK (output_tokens >= 0),cached_tokens INTEGER NOT NULL DEFAULT 0 CHECK (cached_tokens >= 0 AND cached_tokens <= input_tokens));

CREATE TABLE ToolCall (tool_call_id INTEGER PRIMARY KEY,turn_id INTEGER NOT NULL REFERENCES AgentTurn(turn_id) ON DELETE CASCADE,parent_tool_call_id INTEGER NULL REFERENCES ToolCall(tool_call_id) ON DELETE CASCADE,tool_name TEXT NOT NULL CHECK (tool_name IN ('search_videos','get_user_history','fetch_trending_audio','rerank')),arguments_json TEXT NOT NULL CHECK (json_valid(arguments_json)),result_summary TEXT NULL,   latency_ms INTEGER NOT NULL CHECK (latency_ms >= 0),errored INTEGER NOT NULL DEFAULT 0 CHECK (errored IN (0,1)),error_code TEXT NULL,started_at TEXT NOT NULL,CHECK ( (errored=1) = (error_code IS NOT NULL) ),CHECK ( errored=1 OR result_summary IS NOT NULL ));
CREATE INDEX ix_toolcall_turn   ON ToolCall (turn_id);
CREATE INDEX ix_toolcall_parent ON ToolCall (parent_tool_call_id);

CREATE TABLE Recommendation (recommendation_id INTEGER PRIMARY KEY, turn_id INTEGER NOT NULL REFERENCES AgentTurn(turn_id) ON DELETE CASCADE,video_id INTEGER NOT NULL REFERENCES Video(video_id) ON DELETE CASCADE,shelf_position INTEGER NOT NULL CHECK (shelf_position >= 1),UNIQUE (turn_id, shelf_position),UNIQUE (turn_id, video_id));
CREATE INDEX ix_rec_video ON Recommendation (video_id);

CREATE TABLE JudgeScore (turn_id INTEGER PRIMARY KEY REFERENCES AgentTurn(turn_id) ON DELETE CASCADE,judged_at TEXT NOT NULL,judge_model_id INTEGER NOT NULL REFERENCES LlmModel(model_id) ON DELETE RESTRICT,helpfulness REAL NOT NULL CHECK (helpfulness  BETWEEN 1.0 AND 5.0),groundedness REAL NOT NULL CHECK (groundedness BETWEEN 1.0 AND 5.0),safety REAL NOT NULL CHECK (safety BETWEEN 1.0 AND 5.0));

CREATE TABLE UserFeedback (turn_id INTEGER PRIMARY KEY REFERENCES AgentTurn(turn_id) ON DELETE CASCADE,rated_at TEXT NOT NULL,thumbs TEXT NOT NULL CHECK (thumbs IN ('up','down')));

CREATE TRIGGER trg_handle_change_rate_limit BEFORE INSERT ON HandleChange FOR EACH ROW WHEN ( SELECT COUNT(*) FROM HandleChange h WHERE h.user_id = NEW.user_id AND h.changed_at > strftime('%Y-%m-%dT%H:%M:%SZ', NEW.changed_at, '-1 year')) >= 2
BEGIN
    SELECT RAISE(ABORT, 'handle may be changed at most twice in any 12 months');
END;

CREATE TRIGGER trg_handle_change_apply AFTER INSERT ON HandleChange FOR EACH ROW
BEGIN
    UPDATE AppUser SET handle = NEW.new_handle WHERE user_id = NEW.user_id;
END;
