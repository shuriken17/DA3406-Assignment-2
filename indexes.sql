-- F1: join on audio_track_id, then filter on uploaded_at
CREATE INDEX idx_video_track_uploaded ON Video(audio_track_id, uploaded_at);

-- F12: only impressions that came from a recommendation
CREATE INDEX idx_imp_rec_user_p ON Impression(recommendation_id, user_id) WHERE recommendation_id IS NOT NULL;

-- F7: made the query slower (kept as a counter-example)
CREATE INDEX idx_turn_model_created ON AgentTurn(model_id, created_at);

-- Rejected, not built: CREATE INDEX idx_moddec_state ON ModerationDecision(to_state);