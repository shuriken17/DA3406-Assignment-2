-- F1 Top 10 audio tracks by distinct videos in last 7 days
WITH a AS ( SELECT MAX(uploaded_at) t FROM Video ) SELECT t.track_id,t.title,t.origin_kind,COUNT(DISTINCT v.video_id) n_videos FROM AudioTrack t JOIN Video v ON v.audio_track_id=t.track_id CROSS JOIN a WHERE v.uploaded_at>=strftime('%Y-%m-%dT%H:%M:%SZ',a.t,'-7 days') GROUP BY t.track_id,t.title,t.origin_kind ORDER BY n_videos DESC,t.track_id LIMIT 10;

-- F2 Watch hours and mean completion rate per creator, live clips only
WITH ld AS ( SELECT video_id,MAX(decided_at) last_at FROM ModerationDecision GROUP BY video_id ), cs AS ( SELECT md.video_id,md.to_state FROM ModerationDecision md JOIN ld ON ld.video_id=md.video_id AND ld.last_at=md.decided_at ), live AS ( SELECT v.video_id,v.owner_id FROM Video v JOIN cs ON cs.video_id=v.video_id WHERE cs.to_state='live' ), cr AS ( SELECT DISTINCT user_id creator_id FROM CreatorTierPeriod ), pi AS ( SELECT i.impression_id,l.owner_id, COALESCE(SUM(s.watched_ms),0) w, COALESCE(MAX(s.reached_end),0) e, CASE WHEN COUNT(s.seq_no)>0 THEN 1 ELSE 0 END n FROM Impression i JOIN live l ON l.video_id=i.video_id LEFT JOIN ViewSegment s ON s.impression_id=i.impression_id GROUP BY i.impression_id,l.owner_id ) SELECT c.creator_id, ROUND(COALESCE(SUM(p.w),0)/3600000.0,3) watch_hours, ROUND( CASE WHEN COALESCE(SUM(p.n),0)=0 THEN 0.0 ELSE 1.0*SUM(p.e)/SUM(p.n) END,4 ) mean_completion_rate FROM cr c LEFT JOIN pi p ON p.owner_id=c.creator_id GROUP BY c.creator_id ORDER BY watch_hours DESC,c.creator_id LIMIT 20;

-- F3a Videos with no audio track, NOT IN
SELECT COUNT(*) FROM Video v WHERE v.audio_track_id NOT IN ( SELECT t.track_id FROM AudioTrack t );

-- F3b Videos with no audio track, NOT EXISTS
SELECT COUNT(*) FROM Video v WHERE NOT EXISTS ( SELECT 1 FROM AudioTrack t WHERE t.track_id=v.audio_track_id );

-- F4 Users who liked and then retracted within 60 seconds
SELECT user_id,video_id,liked_at,retracted_at, ROUND( (julianday(retracted_at)-julianday(liked_at))*86400.0,1 ) seconds_held FROM VideoLike WHERE retracted_at IS NOT NULL AND (julianday(retracted_at)-julianday(liked_at))*86400.0<=60 ORDER BY seconds_held,like_id LIMIT 20;

-- F5 Caption hashtag search
WITH p(tag) AS ( VALUES('#Study') ), n AS ( SELECT video_id,caption, ' '|| replace(replace(replace(replace(replace(replace( lower(trim(caption)), ',',' '),'.',' '),'!',' '),'?',' '),';',' '),'  ',' ') ||' ' c FROM Video ) SELECT n.video_id,n.caption FROM n CROSS JOIN p WHERE instr(n.c,' '||lower(trim(p.tag))||' ')>0 AND n.c LIKE '%'||lower(trim(p.tag))||'%' ORDER BY n.video_id LIMIT 10;

-- F6a EXCEPT, users shown a creator's clips but never engaged
WITH p AS ( SELECT owner_id FROM Video GROUP BY owner_id ORDER BY COUNT(*) DESC,owner_id LIMIT 1 ) SELECT i.user_id FROM Impression i JOIN Video v ON v.video_id=i.video_id JOIN p ON p.owner_id=v.owner_id EXCEPT SELECT e.user_id FROM EngagementSignal e JOIN Video v ON v.video_id=e.video_id JOIN p ON p.owner_id=v.owner_id;

-- F6b UNION, one signal roll-up
SELECT user_id,video_id FROM EngagementSignal WHERE signal_type='like' UNION SELECT user_id,video_id FROM EngagementSignal WHERE signal_type='save';

-- F6c UNION ALL, same roll-up without removing duplicates
SELECT user_id,video_id FROM EngagementSignal WHERE signal_type='like' UNION ALL SELECT user_id,video_id FROM EngagementSignal WHERE signal_type='save';

-- F7 Agent session cost by prompt template version, last month, sessions above threshold
WITH pj AS ( SELECT t.turn_id,t.session_id,t.template_version_id,t.created_at, u.input_tokens,u.output_tokens,u.cached_tokens, ROUND( (u.input_tokens-u.cached_tokens)/1000.0*mp.input_rate+ u.cached_tokens/1000.0*mp.cached_rate+ u.output_tokens/1000.0*mp.output_rate,8 ) cost_usd FROM AgentTurn t JOIN TurnUsage u ON u.turn_id=t.turn_id JOIN ModelPrice mp ON mp.model_id=t.model_id AND t.created_at>=mp.valid_from AND (mp.valid_to IS NULL OR t.created_at<mp.valid_to) ), a AS ( SELECT MAX(created_at) t FROM AgentTurn ) SELECT session_id,template_version_id, COUNT(*) turns, SUM(input_tokens) input_tokens, SUM(output_tokens) output_tokens, ROUND(SUM(cost_usd),6) session_cost_usd FROM pj CROSS JOIN a WHERE created_at>=strftime('%Y-%m-%dT%H:%M:%SZ',a.t,'-1 month') GROUP BY session_id,template_version_id HAVING SUM(cost_usd)>0.0008 ORDER BY session_cost_usd DESC LIMIT 15;

-- F8 Videos whose moderation state changed more than twice
WITH s AS ( SELECT video_id,to_state,decided_at, LAG(to_state) OVER( PARTITION BY video_id ORDER BY decided_at ) prev_state FROM ModerationDecision ) SELECT video_id, SUM( CASE WHEN prev_state IS NOT NULL AND prev_state<>to_state THEN 1 ELSE 0 END ) n_changes, COUNT(*) n_decisions, group_concat( to_state,' -> ' ORDER BY decided_at ) transition_sequence FROM s GROUP BY video_id HAVING n_changes>2 ORDER BY n_changes DESC,video_id LIMIT 10;

-- F9 Each user's longest streak of consecutive active days
WITH d AS ( SELECT DISTINCT user_id,date(shown_at) day FROM Impression UNION SELECT DISTINCT user_id,date(created_at) FROM EngagementSignal UNION SELECT DISTINCT user_id,date(started_at) FROM AgentSession ), i AS ( SELECT user_id,day, julianday(day)- ROW_NUMBER() OVER( PARTITION BY user_id ORDER BY day ) island FROM d ), r AS ( SELECT user_id,island,COUNT(*) len, MIN(day) start_day,MAX(day) end_day FROM i GROUP BY user_id,island ), x AS ( SELECT *, ROW_NUMBER() OVER( PARTITION BY user_id ORDER BY len DESC,start_day ) rn FROM r ) SELECT user_id, len longest_streak_days, start_day,end_day FROM x WHERE rn=1 ORDER BY longest_streak_days DESC,user_id LIMIT 15;

-- F10 Creators ranked by 7-day rolling watch time
WITH d AS ( SELECT v.owner_id creator_id, date(i.shown_at) day, SUM(s.watched_ms)/3600000.0 hrs FROM ViewSegment s JOIN Impression i ON i.impression_id=s.impression_id JOIN Video v ON v.video_id=i.video_id GROUP BY v.owner_id,date(i.shown_at) ), r AS ( SELECT creator_id,day, SUM(hrs) OVER( PARTITION BY creator_id ORDER BY julianday(day) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW ) rolling_7d FROM d ), a AS ( SELECT MAX(day) d0 FROM d ) SELECT RANK() OVER( ORDER BY r.rolling_7d DESC ) rk, r.creator_id, r.day as_of, ROUND(r.rolling_7d,3) watch_hours_7d, ROUND(COALESCE(p.rolling_7d,0),3) watch_hours_prev_7d, ROUND( r.rolling_7d-COALESCE(p.rolling_7d,0),3 ) wow_change FROM r JOIN a ON r.day=a.d0 LEFT JOIN r p ON p.creator_id=r.creator_id AND p.day=date(a.d0,'-7 day') ORDER BY rk LIMIT 15;

-- F11 Full nesting tree for a given agent session
WITH RECURSIVE p(session_id) AS ( SELECT t.session_id FROM ToolCall c JOIN AgentTurn t ON t.turn_id=c.turn_id WHERE c.parent_tool_call_id IS NOT NULL GROUP BY t.session_id ORDER BY COUNT(*) DESC LIMIT 1 ), tree(tool_call_id,turn_id,parent_id,tool_name, latency_ms,errored,depth,path) AS ( SELECT c.tool_call_id,c.turn_id,c.parent_tool_call_id, c.tool_name,c.latency_ms,c.errored,0, printf('%06d',c.tool_call_id) FROM ToolCall c JOIN AgentTurn t ON t.turn_id=c.turn_id JOIN p ON p.session_id=t.session_id WHERE c.parent_tool_call_id IS NULL UNION ALL SELECT c.tool_call_id,c.turn_id,c.parent_tool_call_id, c.tool_name,c.latency_ms,c.errored, tr.depth+1, tr.path||'/'||printf('%06d',c.tool_call_id) FROM ToolCall c JOIN tree tr ON c.parent_tool_call_id=tr.tool_call_id ) SELECT turn_id,depth, substr('                    ',1,depth*2)||tool_name nested_call, tool_call_id,parent_id,latency_ms,errored FROM tree ORDER BY path LIMIT 25;

-- F12 Recommended clips watched to completion
SELECT s.session_id,s.user_id,t.turn_no, r.shelf_position,r.video_id,i.impression_id, SUM(vs.watched_ms) watched_ms, MAX(vs.reached_end) reached_end FROM Recommendation r JOIN AgentTurn t ON t.turn_id=r.turn_id JOIN AgentSession s ON s.session_id=t.session_id JOIN Impression i ON i.recommendation_id=r.recommendation_id AND i.user_id=s.user_id JOIN ViewSegment vs ON vs.impression_id=i.impression_id GROUP BY s.session_id,s.user_id,t.turn_no, r.shelf_position,r.video_id,i.impression_id HAVING MAX(vs.reached_end)=1 ORDER BY s.session_id,t.turn_no,r.shelf_position LIMIT 20;

-- F13 Judge score above 4 but user gave thumbs-down
SELECT t.turn_id,t.session_id,t.turn_no, m.model_name, pt.name template_name, pv.version_no template_version, ROUND(j.helpfulness,2) helpfulness, ROUND(j.groundedness,2) groundedness, f.thumbs FROM AgentTurn t JOIN JudgeScore j ON j.turn_id=t.turn_id JOIN UserFeedback f ON f.turn_id=t.turn_id JOIN LlmModel m ON m.model_id=t.model_id JOIN PromptTemplateVersion pv ON pv.template_version_id=t.template_version_id JOIN PromptTemplate pt ON pt.template_id=pv.template_id WHERE j.helpfulness>4.0 AND f.thumbs='down' ORDER BY j.helpfulness DESC,t.turn_id;
