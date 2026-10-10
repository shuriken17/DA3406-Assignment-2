import sqlite3, random, os, time
from array import array
from datetime import datetime, timedelta, timezone

SEED              = 24018        
N_USERS           = 5_000
N_VIDEOS          = 20_000
N_IMPRESSIONS     = 300_000
N_AGENT_SESSIONS  = 2_000
SCALE             = 50
N_AUDIO_TRACKS    = 900
N_FOLLOWS         = 60_000
WINDOW_DAYS       = 180
END_DATE          = datetime(2026, 9, 1, tzinfo=timezone.utc)
DB_PATH           = os.environ.get("SCROLLSENSE_DB", "scrollsense.db")
SCHEMA_PATH       = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")

N_USERS *= SCALE; N_VIDEOS *= SCALE; N_IMPRESSIONS *= SCALE; N_AGENT_SESSIONS *= SCALE; N_AUDIO_TRACKS *= SCALE; N_FOLLOWS *= SCALE   # A2 changelog: A1 left AUDIO_TRACKS and FOLLOWS unscaled
rng = random.Random(SEED)
START_DATE = END_DATE - timedelta(days=WINDOW_DAYS)


def iso(dt):
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')


HOUR_WEIGHTS = [2,1,1,1,1,2, 5,8,10,9,8,9, 14,15,11,10,12,16, 22,26,28,25,16,8]  


def ts_on_day(day_index):
    h = rng.choices(range(24), weights=HOUR_WEIGHTS, k=1)[0]
    return START_DATE + timedelta(days=day_index, hours=h,
                                  minutes=rng.randrange(60), seconds=rng.randrange(60))


def zipf_weights(n, alpha=0.9):
    return [1.0/((i+1)**alpha) for i in range(n)]


def segment_ms(duration_ms):
    """Three-behaviour mixture, not one lognormal: skim / substantial / loop."""
    r = rng.random()
    if r < 0.55: return int(max(300, rng.uniform(300, duration_ms*0.35)))
    if r < 0.85: return int(rng.uniform(duration_ms*0.35, duration_ms))
    return int(rng.uniform(duration_ms, duration_ms*1.6))


def main():
    t0 = time.time()
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    con.executescript(open(SCHEMA_PATH).read())
    con.execute("PRAGMA foreign_keys = ON")     
    cur = con.cursor()
    cur.execute("BEGIN")

    tiers = [('none',1,0.00),('bronze',2,0.20),('silver',3,0.35),('gold',4,0.45),('partner',5,0.55)]
    cur.executemany("INSERT INTO MonetisationTier VALUES (?,?,?)", tiers)

    cats = ['comedy','dance','food','gaming','study','tech','sports','music',
            'fashion','travel','pets','diy','news','fitness','art']
    cur.executemany("INSERT INTO InterestCategory VALUES (?,?)", [(i+1,c) for i,c in enumerate(cats)])

    models = [(1,'gpt-4o-mini','openai'),(2,'llama-3.1-70b','meta'),
              (3,'scrollsense-ft-v2','internal'),(4,'judge-mini','internal')]
    cur.executemany("INSERT INTO LlmModel VALUES (?,?,?)", models)

    prices, pid = [], 0
    base = {1:(0.00015,0.00060,0.000075), 2:(0.00009,0.00035,0.000045),
            3:(0.00020,0.00080,0.000100), 4:(0.00005,0.00020,0.000025)}
    for mid,(ir,orr,cr) in base.items():
        cut = START_DATE + timedelta(days=rng.randrange(70,130))
        pid+=1; prices.append((pid,mid,iso(START_DATE-timedelta(days=400)),iso(cut),ir,orr,cr))
        f = rng.choice([0.8,0.9,1.25])
        pid+=1; prices.append((pid,mid,iso(cut),None,round(ir*f,8),round(orr*f,8),round(cr*f,8)))
    cur.executemany("INSERT INTO ModelPrice VALUES (?,?,?,?,?,?,?)", prices)

    templates = [(1,'why_this_explainer','Explains why a clip was surfaced'),
                 (2,'search_answer','Answers conversational search')]
    cur.executemany("INSERT INTO PromptTemplate VALUES (?,?,?)", templates)
    tv, tvid = [], 0
    for tid,_,_ in templates:
        for v in range(1,17):
            tvid+=1
            tv.append((tvid,tid,v,f'[template {tid} v{v}] system prompt text ...',
                       iso(START_DATE+timedelta(days=int(v*WINDOW_DAYS/17)))))
    cur.executemany("INSERT INTO PromptTemplateVersion VALUES (?,?,?,?,?)", tv)
    tv_by_tid = {}
    for r in tv: tv_by_tid.setdefault(r[1], []).append((r[0], r[4]))

    first=['aarav','diya','kabir','meera','rohan','isha','vikram','tara','arjun','nisha']
    last=['x','_official','99','_ss','ig','yt','21','_real','oo','7']
    handles, users, hseen = [], [], set()
    for uid in range(1, N_USERS+1):
        for _ in range(30):
            h = rng.choice(first)+rng.choice(last)+str(rng.randrange(1000))
            if h.lower() not in hseen: hseen.add(h.lower()); break
        else:
            h = f'user{uid}'; hseen.add(h)
        handles.append(h)
        prov = 'phone' if rng.random()<0.62 else 'google'
        phone = f'+91{rng.randrange(6000000000,9999999999)}' if prov=='phone' else None
        email = None if prov=='phone' else f'{h}@example.com'
        r = rng.random()
        if r<0.90: state,dreq='active',None
        elif r<0.97: state,dreq='deactivated',None
        else: state='pending_deletion'; dreq=iso(END_DATE-timedelta(days=rng.randrange(0,45)))
        users.append((uid,h,h.replace('_',' ').title(),prov,phone,email,state,dreq,
                      iso(START_DATE-timedelta(days=rng.randrange(0,700)))))
    cur.executemany("INSERT INTO AppUser VALUES (?,?,?,?,?,?,?,?,?)", users)

    decl=[]
    for uid in range(1,N_USERS+1):
        for c in rng.sample(range(1,len(cats)+1), k=rng.randrange(2,6)):
            decl.append((uid,c,iso(START_DATE)))
    cur.executemany("INSERT INTO UserDeclaredInterest VALUES (?,?,?)", decl)

    inf=[]
    for uid in rng.sample(range(1,N_USERS+1), k=N_USERS//2):
        cs = rng.sample(range(1,len(cats)+1), k=rng.randrange(2,5))
        for d in range(0,WINDOW_DAYS,14):
            for c in cs:
                inf.append((uid,c,iso(START_DATE+timedelta(days=d)),round(rng.betavariate(2,3),3)))
    cur.executemany("INSERT INTO UserInferredInterest VALUES (?,?,?,?)", inf)

    sup=[(uid, rng.randrange(1,len(cats)+1), iso(START_DATE+timedelta(days=rng.randrange(WINDOW_DAYS))), None)
         for uid in rng.sample(range(1,N_USERS+1), k=N_USERS//20)]
    cur.executemany("INSERT OR IGNORE INTO UserInterestSuppression VALUES (?,?,?,?)", sup)

    n_creators = int(N_USERS*0.30)
    creators = rng.sample(range(1,N_USERS+1), k=n_creators)
    ctp, cid = [], 0
    for u in creators:
        n_per = rng.choices([1,2,3], weights=[6,3,1], k=1)[0]
        cuts = sorted(rng.sample(range(10,WINDOW_DAYS-10), k=n_per-1))
        bounds = [0]+cuts+[None]
        idx = rng.randrange(0,3)
        for i in range(n_per):
            cid+=1
            vf = iso(START_DATE+timedelta(days=bounds[i]))
            vt = None if bounds[i+1] is None else iso(START_DATE+timedelta(days=bounds[i+1]))
            ctp.append((cid,u,tiers[min(idx+i,4)][0],vf,vt))
    cur.executemany("INSERT INTO CreatorTierPeriod VALUES (?,?,?,?,?)", ctp)

    tag_pool=['#fyp','#comedy','#Study','#DIY','#chennai','#catsofinstagram','#dance','#Food']
    track_pop = zipf_weights(N_AUDIO_TRACKS, 1.1)
    vids=[]
    creator_w = zipf_weights(n_creators, 0.7)
    owners = rng.choices(creators, weights=creator_w, k=N_VIDEOS)
    track_choice = rng.choices(range(1,N_AUDIO_TRACKS+1), weights=track_pop, k=N_VIDEOS)
    for vid in range(1,N_VIDEOS+1):
        cap = f'clip {vid} ' + ' '.join(rng.sample(tag_pool, k=rng.randrange(0,4)))
        has_track = rng.random()<0.82
        vids.append((vid, owners[vid-1], rng.randrange(20000,90001), cap.strip(),
                     track_choice[vid-1] if has_track else None,
                     iso(ts_on_day(rng.randrange(WINDOW_DAYS)))))
    cur.executemany("INSERT INTO Video VALUES (?,?,?,?,?,?)", vids)

    tracks=[]
    for t in range(1,N_AUDIO_TRACKS+1):
        if rng.random()<0.55:
            tracks.append((t,f'sound {t}','original',rng.randrange(1,N_VIDEOS+1),None,iso(START_DATE)))
        else:
            tracks.append((t,f'sound {t}','licensed',None,f'CAT-{t:05d}',iso(START_DATE)))
    cur.executemany("INSERT INTO AudioTrack VALUES (?,?,?,?,?,?)", tracks)

    mods, mid = [], 0
    for vid in range(1,N_VIDEOS+1):
        up = datetime.strptime(vids[vid-1][5],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
        mid+=1; mods.append((mid,vid,'pending',iso(up),'classifier',None,'clf-1.4',None))
        t = up+timedelta(minutes=rng.randrange(1,90))
        mid+=1
        r=rng.random()
        st = 'live' if r<0.88 else ('age_restricted' if r<0.93 else 'demoted')
        mods.append((mid,vid,st,iso(t),'classifier',None,'clf-1.4',None))
        for _ in range(rng.choices([0,1,2,3], weights=[76,14,7,3], k=1)[0]):
            t = t+timedelta(hours=rng.randrange(2,400))
            if t>END_DATE: break
            mid+=1
            st = rng.choice(['live','demoted','age_restricted','taken_down'])
            human = rng.random()<0.6
            mods.append((mid,vid,st,iso(t),'human' if human else 'classifier',
                         rng.randrange(1,N_USERS+1) if human else None,
                         None if human else 'clf-1.5', 'manual review' if human else None))
    cur.executemany("INSERT INTO ModerationDecision VALUES (?,?,?,?,?,?,?,?)", mods)

    ranked=list(range(1,N_USERS+1)); rng.shuffle(ranked)
    fw = zipf_weights(N_USERS,0.8)
    followees = rng.choices(ranked, weights=fw, k=N_FOLLOWS)
    followers = rng.choices(range(1,N_USERS+1), k=N_FOLLOWS)
    seen, follows, fid = set(), [], 0
    for a,b in zip(followers,followees):
        if a==b or (a,b) in seen: continue
        seen.add((a,b)); fid+=1
        s = ts_on_day(rng.randrange(WINDOW_DAYS))
        if rng.random()<0.12:
            e = min(s+timedelta(days=rng.randrange(1,60)), END_DATE)
            reason = rng.choices(['unfollow','block'], weights=[8,2], k=1)[0]
            follows.append((fid,a,b,iso(s),iso(e),reason))
        else:
            follows.append((fid,a,b,iso(s),None,None))
    cur.executemany("INSERT INTO Follow VALUES (?,?,?,?,?,?)", follows)

    blocks = {(f[1],f[2]) for f in follows if f[5]=='block'}
    for _ in range(N_USERS//10):
        a,b = rng.randrange(1,N_USERS+1), rng.randrange(1,N_USERS+1)
        if a!=b: blocks.add((a,b))
    cur.executemany("INSERT OR IGNORE INTO Block VALUES (?,?,?)",
                    [(a,b,iso(ts_on_day(rng.randrange(WINDOW_DAYS)))) for a,b in blocks])
    mutes = {(rng.randrange(1,N_USERS+1), rng.randrange(1,N_USERS+1)) for _ in range(N_USERS//8)}
    cur.executemany("INSERT OR IGNORE INTO Mute VALUES (?,?,?)",
                    [(a,b,iso(START_DATE)) for a,b in mutes if a!=b])

    sessions, turns, usage, calls, recs = [], [], [], [], []
    tid=cid_call=rid=0
    for sid in range(1,N_AGENT_SESSIONS+1):
        u = rng.randrange(1,N_USERS+1)
        kind = 'why_this' if rng.random()<0.55 else 'conversational_search'
        s0 = ts_on_day(rng.randrange(WINDOW_DAYS))
        n_turns = rng.choices([1,2,3,4,5,6], weights=[30,26,18,12,8,6], k=1)[0]
        sessions.append((sid,u,kind,iso(s0),iso(s0+timedelta(minutes=rng.randrange(1,25)))))
        t_at = s0
        for tn in range(1,n_turns+1):
            tid+=1
            t_at = t_at+timedelta(seconds=rng.randrange(5,200))
            tmpl = 1 if kind=='why_this' else 2
            pool = tv_by_tid[tmpl]
            vidx = min(len(pool)-1, int((t_at-START_DATE).days/WINDOW_DAYS*len(pool)))
            model = rng.choices([1,2,3], weights=[6,3,1], k=1)[0]
            turns.append((tid,sid,tn,f'q{tid}',f'a{tid}',pool[vidx][0],model,
                          round(rng.choice([0.2,0.7,1.0]),2), iso(t_at)))
            it = int(rng.lognormvariate(7.0,0.5)); ot = int(rng.lognormvariate(5.6,0.6))
            usage.append((tid,it,ot,int(it*rng.choice([0,0,0.3,0.6]))))
            if kind=='conversational_search' or rng.random()<0.35:
                for _ in range(rng.randrange(1,4)):
                    cid_call+=1; root=cid_call
                    err = 1 if rng.random()<0.06 else 0
                    calls.append((root,tid,None, rng.choice(['search_videos','get_user_history','fetch_trending_audio']),
                                  '{"query":"cat that thinks it is a dog","filters":{"lang":"ta"}}',
                                  None if err else 'ok: 12 hits', int(rng.lognormvariate(5.2,0.7)), err,
                                  'TIMEOUT' if err else None, iso(t_at)))
                    parent=root
                    for _d in range(rng.choices([0,1,2,3], weights=[50,30,15,5], k=1)[0]):
                        cid_call+=1
                        calls.append((cid_call,tid,parent,'rerank','{"k":20}','ok',
                                      int(rng.lognormvariate(4.5,0.6)),0,None,iso(t_at)))
                        parent=cid_call
            if kind=='conversational_search':
                shelf = rng.sample(range(1,N_VIDEOS+1), k=rng.randrange(3,9))
                for pos,v in enumerate(shelf, start=1):
                    rid+=1; recs.append((rid,tid,v,pos))
    cur.executemany("INSERT INTO AgentSession VALUES (?,?,?,?,?)", sessions)
    cur.executemany("INSERT INTO AgentTurn VALUES (?,?,?,?,?,?,?,?,?)", turns)
    cur.executemany("INSERT INTO TurnUsage VALUES (?,?,?,?)", usage)
    cur.executemany("INSERT INTO ToolCall VALUES (?,?,?,?,?,?,?,?,?,?)", calls)
    cur.executemany("INSERT INTO Recommendation VALUES (?,?,?,?)", recs)

    js=[(t[0],t[8],4,round(rng.uniform(1,5),2),round(rng.uniform(1,5),2),round(rng.uniform(3,5),2))
        for t in turns if rng.random()<0.22]
    cur.executemany("INSERT INTO JudgeScore VALUES (?,?,?,?,?,?)", js)
    fb=[(t[0],t[8],'up' if rng.random()<0.72 else 'down') for t in turns if rng.random()<0.06]
    cur.executemany("INSERT INTO UserFeedback VALUES (?,?,?)", fb)

    assert WINDOW_DAYS < 256 and N_USERS < 2**21 and N_VIDEOS < 2**21
    active_pairs=array('I')
    for uid in range(1,N_USERS+1):
        p = min(0.95, rng.betavariate(1.6,3.0)+0.02)
        on = rng.random()<p
        for d in range(WINDOW_DAYS):
            on = (rng.random()<0.80) if on else (rng.random()<p*0.35)
            if on: active_pairs.append(uid*256+d)
    rng.shuffle(active_pairs)

    video_w = zipf_weights(N_VIDEOS,0.85)
    ranked_videos=list(range(1,N_VIDEOS+1)); rng.shuffle(ranked_videos)
    pair_pick = array('I')
    for lo in range(0, N_IMPRESSIONS, 1_000_000):
        pair_pick.extend(rng.choices(active_pairs, k=min(1_000_000, N_IMPRESSIONS-lo)))
    vid_pick  = array('I')
    for lo in range(0, N_IMPRESSIONS, 1_000_000):
        vid_pick.extend(rng.choices(ranked_videos, weights=video_w, k=min(1_000_000, N_IMPRESSIONS-lo)))

    impressions, segments, likes, signals = [], [], [], []
    def flush_impr():
        cur.executemany("INSERT INTO Impression VALUES (?,?,?,?,?,?,?,?)", impressions)
        cur.executemany("INSERT INTO ViewSegment VALUES (?,?,?,?,?,?)", segments)
        impressions.clear(); segments.clear()
    iid=seg_id=like_id=sig_id=0
    dur = {v[0]:v[2] for v in vids}
    seen_impr=set()

    for k in range(N_IMPRESSIONS):
        if k and k % 250_000 == 0: flush_impr()
        x = pair_pick[k]; u = x >> 8; d = x & 255; v = vid_pick[k]; t = ts_on_day(d)
        key=((u<<21|v)<<31)|int(t.timestamp())
        if key in seen_impr: continue
        seen_impr.add(key); iid+=1
        r=rng.random()
        if r<0.90: surface,pos='feed',rng.randrange(0,60)
        elif r<0.97: surface,pos='search_shelf',None
        else: surface,pos='profile',None
        impressions.append((iid,v,u,iso(t),surface,pos,
                            rng.choice(['rank-v12','rank-v13','rank-v14']), None))
        if rng.random()>0.34: continue
        n_seg = rng.choices([1,2,3], weights=[78,17,5], k=1)[0]
        total,at = 0,t
        for s in range(1,n_seg+1):
            seg_id+=1; w = segment_ms(dur[v]); total+=w
            segments.append((iid,s,iso(at),0 if s==1 else rng.randrange(0,dur[v]),w,1 if total>=dur[v] else 0))
            at = at+timedelta(milliseconds=w+rng.randrange(200,3000))
        if rng.random()>0.09: continue
        kind = rng.choices(['like','save','share','comment','follow_from_feed','not_interested','report'],
                           weights=[55,14,10,9,6,5,1], k=1)[0]
        if kind=='like':
            like_id+=1
            retract_at=None
            if rng.random()<0.13:
                gap = rng.choice([rng.randrange(3,60), rng.randrange(60,90000)])
                retract_at = t+timedelta(seconds=gap)
            likes.append((like_id,u,v,iid,iso(t), iso(retract_at) if retract_at else None))
            sig_id+=1; signals.append((sig_id,u,v,iid,'like',iso(t),None,like_id))
            if retract_at:
                sig_id+=1; signals.append((sig_id,u,v,iid,'like_retracted',iso(retract_at),None,like_id))
        else:
            sig_id+=1
            dest = rng.choice(['whatsapp','instagram','copy_link']) if kind=='share' else None
            signals.append((sig_id,u,v,iid,kind,iso(t),dest,None))

    sess_user={s[0]:s[1] for s in sessions}
    turn_meta={t[0]:(t[1],t[8]) for t in turns}
    for rid_,turn_id_,vid_,pos_ in recs:
        sid_,t_iso = turn_meta[turn_id_]
        u_ = sess_user[sid_]
        p_seen = max(0.15, 0.85-0.09*(pos_-1))
        if rng.random()>p_seen: continue
        t_ = datetime.strptime(t_iso,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)+timedelta(seconds=rng.randrange(2,240))
        key=((u_<<21|vid_)<<31)|int(t_.timestamp())
        if key in seen_impr: continue
        seen_impr.add(key); iid+=1
        impressions.append((iid,vid_,u_,iso(t_),'search_shelf',None,
                            rng.choice(['rank-v13','rank-v14']), rid_))
        if rng.random()>0.55: continue
        total,at=0,t_
        for s in range(1, rng.choices([1,2],weights=[85,15],k=1)[0]+1):
            seg_id+=1; w=segment_ms(dur[vid_]); total+=w
            segments.append((iid,s,iso(at),0 if s==1 else rng.randrange(0,dur[vid_]),w,1 if total>=dur[vid_] else 0))
            at = at+timedelta(milliseconds=w+rng.randrange(200,3000))

    flush_impr()
    cur.executemany("INSERT INTO VideoLike VALUES (?,?,?,?,?,?)", likes)
    cur.executemany("INSERT INTO EngagementSignal VALUES (?,?,?,?,?,?,?,?)", signals)

    comments=[]
    for i,s in enumerate([x for x in signals if x[4]=='comment'], start=1):
        comments.append((i,s[2],s[1],f'nice one {i}',s[5]))
    cur.executemany("INSERT INTO VideoComment VALUES (?,?,?,?,?)", comments)

    con.commit()                
    con.execute("ANALYZE")
    con.commit()

    counts = {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] for t in
              ['AppUser','Video','AudioTrack','ModerationDecision','Follow','Impression',
               'ViewSegment','VideoLike','EngagementSignal','AgentSession','AgentTurn',
               'ToolCall','Recommendation','CreatorTierPeriod','ModelPrice']}
    for k,v in counts.items(): print(f'{k:22s} {v:>9,}')
    print(f'\nseed={SEED}  scale={SCALE}  elapsed={time.time()-t0:.1f}s  -> {DB_PATH}')
    con.close()


if __name__ == '__main__':
    main()
