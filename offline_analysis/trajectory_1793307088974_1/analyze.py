"""Offline analysis. Requires only the NumPy already bundled with Blender Python.
No Android calls, no modification of input or filter. Outputs JSON/CSV/SVG/HTML.
"""
from __future__ import annotations
import argparse, collections, csv, hashlib, html, json, math, re
from pathlib import Path
import numpy as np

STAGES = ('input', 'euro', 'predicted', 'blend', 'follower', 'final')
PAIRS = {'one_euro': ('input', 'euro'), 'prediction_advance': ('euro', 'predicted'),
         'blend_correction': ('predicted', 'blend'), 'follower_correction': ('blend', 'follower'),
         'eyelid_adjustment': ('follower', 'final'), 'predicted_to_final': ('predicted', 'final')}
FLAGS = {1:'missing_context',2:'missing_processed',4:'history_changed',8:'tracking_lost',
         16:'history_boundary',32:'recovery',64:'lid_untrusted',128:'no_node',256:'hidden',
         512:'nonfinite',1024:'incomplete_stages'}
COLORS = {'input':'#9a6b16','euro':'#777777','predicted':'#2979bd','blend':'#b154b9',
          'follower':'#e56a18','final':'#188b67','reference':'#333333','tau25':'#bb3560','tau20':'#6655bc'}

def unit(q):
    return q / np.linalg.norm(q, axis=-1, keepdims=True)

def conjugate(q):
    z = np.array(q, copy=True); z[..., :3] *= -1; return z

def multiply(a, b):
    a, b = np.broadcast_arrays(a, b)
    xyz = a[...,3,None]*b[...,:3] + b[...,3,None]*a[...,:3] + np.cross(a[...,:3],b[...,:3])
    w = a[...,3]*b[...,3] - np.sum(a[...,:3]*b[...,:3],axis=-1)
    return np.concatenate([xyz,w[...,None]],axis=-1)

def rotvec(q):
    q = unit(q); q = np.where(q[...,3,None] < 0,-q,q)
    s = np.linalg.norm(q[...,:3],axis=-1)
    k = np.divide(np.degrees(2*np.arctan2(s,q[...,3])),s,
                  out=np.full_like(s,180*2/np.pi),where=s>1e-12)
    return q[...,:3]*k[...,None]

def rotation_difference(a,b):
    """World-frame signed shortest-arc downstream minus upstream, degrees."""
    return rotvec(multiply(b,conjugate(a)))

def nlerp(a,b,t):
    if np.dot(a,b)<0: b=-b
    return unit(a+(b-a)*t)

def summary(a):
    a=np.asarray(a,dtype=float); a=a[np.isfinite(a)]
    if not len(a): return {'n':0}
    return dict(n=len(a),mean=float(np.mean(a)),median=float(np.median(a)),
                p95=float(np.percentile(a,95)),p99=float(np.percentile(a,99)),max=float(np.max(a)))

def write_csv(path, rows):
    if not rows: return
    keys=list(dict.fromkeys(k for r in rows for k in r))
    with open(path,'w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=keys); w.writeheader(); w.writerows(rows)

def block_labels(times, mask, max_gap=.15):
    labels=np.full(len(times),-1,dtype=int); count=-1
    for i in range(len(times)):
        if mask[i]:
            if i==0 or not mask[i-1] or times[i]-times[i-1]>max_gap: count+=1
            labels[i]=count
    return labels

def local_slopes(t,p,q, labels):
    v=np.full_like(p,np.nan); w=np.full_like(p,np.nan)
    for i in range(len(t)):
        ix=np.where((labels==labels[i]) & (np.abs(t-t[i])<=.22))[0]
        ix=ix[np.argsort(np.abs(ix-i))[:5]]; ix.sort()
        if len(ix)<3: continue
        x=t[ix]-t[i]; x-=np.mean(x); den=np.dot(x,x)
        if den<=0: continue
        v[i]=np.sum(x[:,None]*p[ix],axis=0)/den
        angles=rotation_difference(np.broadcast_to(q[i],q[ix].shape),q[ix])
        w[i]=np.sum(x[:,None]*angles,axis=0)/den
    return v,w

def principal(a):
    a=a[np.all(np.isfinite(a),axis=1)]
    _,_,vh=np.linalg.svd(a-np.mean(a,axis=0),full_matrices=False)
    axis=vh[0]
    if axis[np.argmax(np.abs(axis))]<0: axis=-axis
    return axis

def stage_jitter(t,p,q,mask,scale):
    dt=np.diff(t); good=mask[1:]&mask[:-1]&(dt>0)&(dt<.05)
    v=np.diff(p,axis=0)/dt[:,None]/scale
    w=rotation_difference(q[:-1],q[1:])/dt[:,None]
    g=good[1:]&good[:-1]
    avg=(dt[1:]+dt[:-1])/2
    a=np.linalg.norm(np.diff(v,axis=0)/avg[:,None],axis=1)
    ar=np.linalg.norm(np.diff(w,axis=0)/avg[:,None],axis=1)
    # Kinematic variability, not pure perceptual jitter outside rest.
    return {'position_accel_ipd_s2':summary(a[g]),'angular_accel_deg_s2':summary(ar[g]),
            'position_speed_ipd_s':summary(np.linalg.norm(v,axis=1)[good]),
            'angular_speed_deg_s':summary(np.linalg.norm(w,axis=1)[good])}

def replay(t,pred_p,pred_q,record_p,record_q,frame_ids, tau_ms):
    """Conditional replay with fixed logged predictions. No Android simulation.
    Seed first output from log. Infer warmup gate from observed baseline correction.
    """
    n=len(t); outp=np.empty_like(pred_p); outq=np.empty_like(pred_q)
    fp=np.empty_like(pred_p); fq=np.empty_like(pred_q)
    correction=np.zeros(3); correction_q=np.array([0.,0.,0.,1.]); start=t[0]
    enabled=False
    outp[0]=record_p[0]; outq[0]=record_q[0]
    correction=outp[0]-pred_p[0]; correction_q=multiply(outq[0],conjugate(pred_q[0]))
    for i in range(1,n):
        new=frame_ids[i]!=frame_ids[i-1]
        observed=np.linalg.norm(record_p[i]-pred_p[i])>1e-8 or np.linalg.norm(rotation_difference(pred_q[i],record_q[i]))>1e-3
        if new and observed: enabled=True
        if new:
            if enabled and t[i]-t[i-1]<=.100:
                correction=outp[i-1]-pred_p[i]
                correction_q=multiply(outq[i-1],conjugate(pred_q[i]))
                start=t[i]
            else: correction=np.zeros(3); correction_q=np.array([0.,0.,0.,1.])
        if enabled:
            decay=math.exp(-(t[i]-start)/(tau_ms/1000))
            if decay<1e-3: outp[i]=pred_p[i];outq[i]=pred_q[i]
            else:
                outp[i]=pred_p[i]+correction*decay
                outq[i]=multiply(nlerp(np.array([0.,0.,0.,1.]),correction_q,decay),pred_q[i])
        else: outp[i]=pred_p[i];outq[i]=pred_q[i]
    return outp,unit(outq)

def replay_follower(t,p,q,seed_p,seed_q,tau_ms=35):
    outp=np.empty_like(p);outq=np.empty_like(q);outp[0]=seed_p;outq[0]=seed_q
    for i in range(1,len(t)):
        dt=t[i]-t[i-1]
        if dt<=0 or dt>.250: outp[i]=p[i];outq[i]=q[i]
        else:
            a=1-math.exp(-dt/(tau_ms/1000));outp[i]=outp[i-1]+(p[i]-outp[i-1])*a
            outq[i]=nlerp(outq[i-1],q[i],a)
    return outp,outq

def svg_plot(path,title,panels, bands=(),events=(),width=1250):
    """Dependency-free standalone SVG line charts; all numeric work is NumPy."""
    height=90+235*len(panels); left=90;right=30; top=65;pw=width-left-right
    all_t=np.concatenate([np.asarray(s[1]) for panel in panels for s in panel['series']])
    lo=float(np.nanmin(all_t));hi=float(np.nanmax(all_t));span=max(hi-lo,1e-6)
    X=lambda x:left+(x-lo)/span*pw
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
         '<rect width="100%" height="100%" fill="white"/>',
         '<style>text{font-family:Arial,sans-serif;fill:#263238;font-size:12px}.title{font-size:18px;font-weight:bold}.grid{stroke:#dde3e8;stroke-width:1}</style>',
         f'<text x="25" y="28" class="title">{html.escape(title)}</text>']
    for pi,panel in enumerate(panels):
        y0=top+pi*235;ph=155
        vals=np.concatenate([np.asarray(s[2])[np.isfinite(s[2])] for s in panel['series']])
        mn=float(np.min(vals)) if len(vals) else -1;mx=float(np.max(vals)) if len(vals) else 1
        pad=max((mx-mn)*.08,1e-6);mn-=pad;mx+=pad
        Y=lambda v:y0+ph-(v-mn)/(mx-mn)*ph
        for a,b,c in bands:
            if b>=lo and a<=hi:out.append(f'<rect x="{X(max(a,lo)):.2f}" y="{y0}" width="{X(min(b,hi))-X(max(a,lo)):.2f}" height="{ph}" fill="{c}" opacity="0.22"/>')
        for k in range(6):
            v=mn+(mx-mn)*k/5; yy=Y(v)
            out.append(f'<line x1="{left}" y1="{yy:.2f}" x2="{width-right}" y2="{yy:.2f}" class="grid"/><text x="{left-8}" y="{yy+4:.2f}" text-anchor="end">{v:.4g}</text>')
        for x in np.linspace(lo,hi,9):
            out.append(f'<line x1="{X(x):.2f}" y1="{y0}" x2="{X(x):.2f}" y2="{y0+ph}" class="grid"/><text x="{X(x):.2f}" y="{y0+ph+18}" text-anchor="middle">{x:.2f}</text>')
        for x in events:
            if lo<=x<=hi:out.append(f'<line x1="{X(x):.2f}" y1="{y0}" x2="{X(x):.2f}" y2="{y0+ph}" stroke="#b71c1c" stroke-dasharray="4 4"/>')
        lx=left
        for label,t,y,color in panel['series']:
            parts=[];pen=False
            for xx,yy in zip(t,y):
                if np.isfinite(xx) and np.isfinite(yy):parts.append(f'{"L" if pen else "M"}{X(xx):.2f},{Y(yy):.2f}');pen=True
                else:pen=False
            out.append(f'<path d="{" ".join(parts)}" fill="none" stroke="{color}" stroke-width="1.45" opacity=".9"/>')
            out.append(f'<text x="{lx}" y="{y0+ph+40}" fill="{color}" style="fill:{color}">{html.escape(label)}</text>')
            lx+=max(95,len(label)*7+20)
        out.append(f'<text x="{left}" y="{y0-10}" font-weight="bold">{html.escape(panel["label"])}</text>')
    out.append(f'<text x="{left}" y="{height-12}">Segundos desde el inicio observado de captura (elapsed). No es tiempo de presentación.</text></svg>')
    path.write_text('\n'.join(out),encoding='utf-8')

def analyze(input_path,out):
    out.mkdir(parents=True,exist_ok=True)
    text=input_path.read_text(encoding='utf-8-sig');lines=text.splitlines()
    assert lines[0].startswith('#schema=pose_trajectory_v1 ')
    footer=next(x for x in reversed(lines) if x.startswith('#END '))
    footer_fields=dict(re.findall(r'(\w+)=([^ ]+)',footer))
    rows=list(csv.DictReader(x for x in lines if not x.startswith('#') and x.strip()))
    assert len(rows[0])==66
    fields=set(rows[0]);assert all(f'{s}_{c}' in fields for s in STAGES for c in ('px','py','pz','qx','qy','qz','qw'))
    assert int(footer_fields['rows'])==len(rows)
    assert [int(r['eventSeq']) for r in rows]==list(range(1,len(rows)+1))
    flag_counts=collections.Counter(int(r['flags']) for r in rows)
    report={'input':str(input_path),'sha256':hashlib.sha256(input_path.read_bytes()).hexdigest(),
            'schema_columns':len(fields),'rows':len(rows),'footer':footer_fields,
            'flags':dict(flag_counts),'flag_bits':{label:sum(bool(int(r['flags'])&bit) for r in rows) for bit,label in FLAGS.items()},
            'method':{'reference':'local least-squares raw pose velocity over <=5 processed samples and +/-0.22s sensor time; NOT visible current face',
                      'motion_thresholds':'rest: position<0.08 IPD/s AND angular<8 deg/s; fast: position>0.6 IPD/s OR angular>45 deg/s',
                      'blink_guard':'exclude +/-0.15s around lid-untrusted or closedAmount>0.05',
                      'sign':'downstream minus upstream; follower correction is NEGATIVE of PoseTrace target-minus-output residual',
                      'replay':'conditional on fixed logged predictions; first states seeded from log; no physical preview reference'},'eyes':{}}
    shared={}
    for r in rows:
        if int(r['flags'])==0:shared.setdefault((r['sessionId'],r['frameId']),{})[int(r['eye'])]=np.array([float(r['input_p'+a]) for a in 'xyz'])
    distances=[np.linalg.norm(d[1]-d[0]) for d in shared.values() if set(d)=={0,1}]
    scale=float(np.median(distances));report['median_intereye_world_units']=scale
    metric_rows=[];segment_rows=[];correction_rows=[];unique_rows=[];replay_rows=[]
    origin=min(int(r['renderElapsedNs']) for r in rows)
    for eye in [0,1]:
        rr=[r for r in rows if int(r['eye'])==eye];n=len(rr)
        arr=lambda c:np.array([float(r[c]) for r in rr])
        ints=lambda c:np.array([int(r[c]) for r in rr],dtype=np.int64)
        t=(ints('renderElapsedNs')-origin)/1e9
        rt=(ints('frameTimeNanos')-ints('frameTimeNanos')[0])/1e9
        flags=ints('flags');valid=flags==0
        ps={s:np.array([[float(r[s+'_p'+a]) for a in 'xyz'] for r in rr]) for s in STAGES}
        qs={s:np.array([[float(r[s+'_q'+a]) for a in 'xyzw'] for r in rr]) for s in STAGES}
        norm_errors={s:summary(np.abs(np.linalg.norm(qs[s][valid],axis=1)-1)) for s in STAGES}
        finite=np.logical_and.reduce([np.all(np.isfinite(ps[s]),axis=1)&np.all(np.isfinite(qs[s]),axis=1) for s in STAGES])
        assert np.all(finite[valid]);assert all(np.max(np.abs(np.linalg.norm(qs[s][valid],axis=1)-1))<1e-3 for s in STAGES)
        for s in STAGES:qs[s][finite]=unit(qs[s][finite])
        evaluation=ints('renderEvaluationId');assert np.all(np.diff(evaluation)==1)
        assert np.all(np.diff(ints('frameTimeNanos'))>0);assert np.all(np.diff(ints('renderElapsedNs'))>0)
        # Keep source and render domains distinct. One source row per actual processed frame.
        unique={};consistency=0
        for i,r in enumerate(rr):
            if not finite[i] or flags[i]&~64:continue
            key=(r['sessionId'],r['frameId'],r['generation'])
            if key in unique:
                old=unique[key]
                assert r['sensorNs']==rr[old]['sensorNs']
                for s in ('input','euro'):assert np.array_equal(ps[s][i],ps[s][old]) and np.array_equal(qs[s][i],qs[s][old])
                consistency+=1
            else:unique[key]=i
        ix=np.array(list(unique.values()),dtype=int)
        st=(ints('sensorNs')[ix]-ints('sensorNs')[ix][0])/1e9
        assert np.all(np.diff(st)>0)
        ordered=['sensorNs','submitElapsedNs','callbackElapsedNs','rawElapsedNs','euroElapsedNs','publicationBeforeNs','publicationAfterNs','renderElapsedNs']
        violations=sum(any(int(rr[i][a])>int(rr[i][b]) for a,b in zip(ordered,ordered[1:])) for i in ix)
        assert violations==0
        slabel=block_labels(st,np.ones(len(st),dtype=bool),.20)
        v,w=local_slopes(st,ps['input'][ix],qs['input'][ix],slabel)
        sv=np.linalg.norm(v,axis=1)/scale;sw=np.linalg.norm(w,axis=1)
        categories=np.where((sv<.08)&(sw<8),'rest',np.where((sv>.6)|(sw>45),'fast','slow'))
        categories[~np.isfinite(sv)|~np.isfinite(sw)]='unknown'
        row_map={int(i):j for j,i in enumerate(ix)}
        refs={k:j for j,k in enumerate(unique)}
        rv=np.full((n,3),np.nan);rw=np.full((n,3),np.nan);cat=np.full(n,'unknown',dtype='<U8')
        for i,r in enumerate(rr):
            j=refs.get((r['sessionId'],r['frameId'],r['generation']))
            if j is not None:rv[i]=v[j];rw[i]=w[j];cat[i]=categories[j]
        blink=(flags&64!=0)|(arr('closedAmount')>.05)
        guarded=np.array([np.any(blink & (np.abs(t-tt)<=.15)) for tt in t])
        comparable=valid&~guarded
        stable_rest=np.zeros(n,dtype=bool)
        rest_blocks=block_labels(t,comparable&(cat=='rest'),.05)
        for block in np.unique(rest_blocks[rest_blocks>=0]):
            ids=np.where(rest_blocks==block)[0]
            if t[ids[-1]]-t[ids[0]]>=.40:
                stable_rest[ids]=(t[ids]-t[ids[0]]>=.25)&(t[ids[-1]]-t[ids]>=.05)
        paxis=principal(ps['input'][ix]);qref=qs['input'][ix[0]]
        qaxis=principal(rotation_difference(np.broadcast_to(qref,qs['input'][ix].shape),qs['input'][ix]))
        # Significant reversals/braking are candidates from observed source motion, not video annotations.
        vp=v@paxis;wp=w@qaxis;events=[]
        last_event=-1.
        for j in range(1,len(ix)):
            prev=np.where((st<st[j])&(st>=st[j]-.25))[0]
            prev=prev[np.isfinite(sv[prev])&np.isfinite(sw[prev])]
            if not len(prev) or not np.isfinite(sv[j]) or not np.isfinite(sw[j]):continue
            reversal=(abs(vp[j])/scale>.10 and np.any(vp[prev]*vp[j]<-(.10*scale)**2)) or (abs(wp[j])>10 and np.any(wp[prev]*wp[j]<-100))
            score=max(sv[j]/.6,sw[j]/45)
            past=max(np.nanmax(sv[prev]/.6),np.nanmax(sw[prev]/45))
            brake=past>1 and score<.4*past
            if (reversal or brake) and st[j]-last_event>.45:
                last_event=st[j];events.append(t[ix[j]])
                segment_rows.append({'eye':eye,'type':'reversal_candidate' if reversal else 'brake_candidate',
                    'frameId':int(rr[ix[j]]['frameId']),'sensor_relative_s':st[j],'available_elapsed_relative_s':t[ix[j]],'reference_speed_ipd_s':sv[j],'reference_angular_deg_s':sw[j]})
        for state in ('rest','slow','fast'):
            blocks=block_labels(t,comparable&(cat==state),.05)
            for b in np.unique(blocks[blocks>=0]):
                ids=np.where(blocks==b)[0]
                if t[ids[-1]]-t[ids[0]]>=.15:
                    segment_rows.append({'eye':eye,'type':state,'start_available_s':t[ids[0]],'end_available_s':t[ids[-1]],'render_rows':len(ids)})
        er={'render_rows':n,'strict_valid':int(np.sum(valid)),'open_comparable':int(np.sum(comparable)),
            'processed_samples_including_lid_untrusted':len(ix),'processed_strict_valid':len({rr[i]['frameId'] for i in np.where(valid)[0]}),
            'repeat_source_checks':consistency,'render_dt_ms':summary(np.diff(rt)*1000),
            'source_dt_ms':summary(np.diff(st)*1000),'quat_norm_error':norm_errors,
            'elapsed_order_violations':violations,'rest_render_rows':int(np.sum(comparable&(cat=='rest'))),
            'stable_rest_render_rows':int(np.sum(stable_rest)),
            'fast_render_rows':int(np.sum(comparable&(cat=='fast'))),'motion_pc_position':paxis.tolist(),'motion_pc_rotation':qaxis.tolist(),
            'stages':{},'jitter':{},'replay':{}}
        dp={};dr={};signed_p={};signed_r={}
        for name,(a,b) in PAIRS.items():
            dp[name]=(ps[b]-ps[a])/scale
            dr[name]=rotation_difference(qs[a],qs[b])
            vnorm=np.linalg.norm(rv,axis=1);wnorm=np.linalg.norm(rw,axis=1)
            signed_p[name]=np.sum(dp[name]*rv,axis=1)/np.where(vnorm>0,vnorm,np.nan)
            signed_r[name]=np.sum(dr[name]*rw,axis=1)/np.where(wnorm>0,wnorm,np.nan)
            er['stages'][name]={}
            for state in ('all','rest','rest_stable','slow','fast'):
                mask=comparable.copy()
                if state=='rest_stable':mask&=stable_rest
                elif state!='all':mask&=cat==state
                if name=='one_euro':mask&=np.isin(np.arange(n),ix)
                pnorm=np.linalg.norm(dp[name],axis=1);rnorm=np.linalg.norm(dr[name],axis=1)
                mp=mask&(vnorm/scale>.1)&(pnorm>.0001)
                mr=mask&(wnorm>10)&(rnorm>.01)
                pc=np.divide(signed_p[name],pnorm,out=np.full(n,np.nan),where=pnorm>0)
                rc=np.divide(signed_r[name],rnorm,out=np.full(n,np.nan),where=rnorm>0)
                entry={'position_percent_ipd':summary(pnorm[mask]*100),'angle_deg':summary(rnorm[mask]),
                    'position_signed_percent_ipd':summary(signed_p[name][mp]*100),
                    'rotation_signed_deg':summary(signed_r[name][mr]),
                    'position_motion_eligible':int(np.sum(mp)),'rotation_motion_eligible':int(np.sum(mr)),
                    'position_opposed_fraction':float(np.mean(pc[mp]<-.5)) if np.any(mp) else None,
                    'rotation_opposed_fraction':float(np.mean(rc[mr]<-.5)) if np.any(mr) else None}
                er['stages'][name][state]=entry
                metric_rows.append({'eye':eye,'stage':name,'state':state,'n':int(np.sum(mask)),
                    'position_mean_percent_ipd':entry['position_percent_ipd'].get('mean'),
                    'position_p95_percent_ipd':entry['position_percent_ipd'].get('p95'),
                    'angle_mean_deg':entry['angle_deg'].get('mean'),'angle_p95_deg':entry['angle_deg'].get('p95'),
                    'opposed_position_fraction':entry['position_opposed_fraction'],'opposed_rotation_fraction':entry['rotation_opposed_fraction']})
        # Show repeated-source weighting sensitivity: first observation of each processed sample.
        er['opposition_first_render_per_source']={}
        for name in ('blend_correction','follower_correction'):
            mask=comparable&(cat=='fast')&np.isin(np.arange(n),ix)
            pn=np.linalg.norm(dp[name],axis=1);rn=np.linalg.norm(dr[name],axis=1)
            mp=mask&(np.linalg.norm(rv,axis=1)/scale>.1)&(pn>.0001)
            mr=mask&(np.linalg.norm(rw,axis=1)>10)&(rn>.01)
            er['opposition_first_render_per_source'][name]={
                'position_n':int(np.sum(mp)),'position_opposed':float(np.mean(signed_p[name][mp]/pn[mp]<-.5)) if np.any(mp) else None,
                'rotation_n':int(np.sum(mr)),'rotation_opposed':float(np.mean(signed_r[name][mr]/rn[mr]<-.5)) if np.any(mr) else None}
        # Verify known follower equation using actual logged target/output and render-domain dt.
        dt=np.diff(rt);g=finite[1:]&finite[:-1]&(dt>0)&(dt<.05)
        alpha=1-np.exp(-dt/.035)
        expected=ps['follower'][:-1]+(ps['blend'][1:]-ps['follower'][:-1])*alpha[:,None]
        er['follower_equation_position_error_world']=summary(np.linalg.norm(expected-ps['follower'][1:],axis=1)[g])
        # New-sample stasis is a direct signature of previous-vsync re-anchoring.
        new=np.r_[False,ints('frameId')[1:]!=ints('frameId')[:-1]]
        arrival=new&comparable&np.r_[False,valid[:-1]]&np.r_[False,np.diff(rt)<.1]
        arrival &= rt-rt[np.where(finite)[0][0]]>1.
        pd=np.r_[np.nan,np.linalg.norm(np.diff(ps['blend'],axis=0),axis=1)]
        qd=np.r_[np.nan,np.linalg.norm(rotation_difference(qs['blend'][:-1],qs['blend'][1:]),axis=1)]
        er['new_sample_stasis']={'n':int(np.sum(arrival)),'position_fraction':float(np.mean(pd[arrival]<1e-7)),
            'rotation_fraction':float(np.mean(qd[arrival]<.001))}
        for s in STAGES:er['jitter'][s]={state:stage_jitter(rt,ps[s],qs[s],stable_rest if state=='rest_stable' else comparable&(cat==state),scale) for state in ('rest','rest_stable','fast')}
        # Replay all finite rows (including blinking), not only analysis-selected rows.
        fi=np.where(finite & ((flags&~64)==0))[0]
        assert np.all(np.diff(fi)==1), 'Replay requires a continuous finite run; split if violated.'
        ft=rt[fi];fr=ints('frameId')[fi]
        replays={}
        for tau in (30,25,20):
            bp,bq=replay(ft,ps['predicted'][fi],qs['predicted'][fi],ps['blend'][fi],qs['blend'][fi],fr,tau)
            fp,fq=replay_follower(ft,bp,bq,ps['follower'][fi[0]],qs['follower'][fi[0]])
            replays[tau]=(bp,bq,fp,fq)
            base_p=ps['follower'][fi];base_q=qs['follower'][fi]
            stats={'blend_position_reproduction_world':summary(np.linalg.norm(bp-ps['blend'][fi],axis=1)),
                'blend_rotation_reproduction_deg':summary(np.linalg.norm(rotation_difference(qs['blend'][fi],bq),axis=1)),
                'follower_position_change_percent_ipd':summary(np.linalg.norm(fp-base_p,axis=1)/scale*100),
                'follower_rotation_change_deg':summary(np.linalg.norm(rotation_difference(base_q,fq),axis=1)),
                'states':{}}
            if tau==30:
                assert stats['blend_position_reproduction_world']['max']<1e-6
                assert stats['blend_rotation_reproduction_deg']['max']<.001
                assert np.max(np.linalg.norm(fp-base_p,axis=1))<1e-6
            for state in ('rest','rest_stable','fast'):
                mask=stable_rest[fi] if state=='rest_stable' else comparable[fi]&(cat[fi]==state)
                net=(fp-ps['predicted'][fi])/scale
                netr=rotation_difference(qs['predicted'][fi],fq)
                svv=rv[fi];sww=rw[fi]
                vn=np.linalg.norm(svv,axis=1);wn=np.linalg.norm(sww,axis=1)
                mp=mask&(vn/scale>.1);mr=mask&(wn>10)
                projp=np.sum(net*svv,axis=1)/np.where(vn>0,vn,np.nan)*100
                projr=np.sum(netr*sww,axis=1)/np.where(wn>0,wn,np.nan)
                state_stats={'net_position_percent_ipd':summary(np.linalg.norm(net,axis=1)[mask]*100),
                    'net_angle_deg':summary(np.linalg.norm(netr,axis=1)[mask]),
                    'net_signed_position_percent_ipd':summary(projp[mp]),'net_signed_rotation_deg':summary(projr[mr]),
                    'roughness':stage_jitter(ft,fp,fq,mask,scale)}
                stats['states'][state]=state_stats
                replay_rows.append({'eye':eye,'tau_blend_ms':tau,'state':state,
                    'net_separation_mean_percent_ipd':state_stats['net_position_percent_ipd'].get('mean'),
                    'net_angle_mean_deg':state_stats['net_angle_deg'].get('mean'),
                    'signed_position_mean_percent_ipd':state_stats['net_signed_position_percent_ipd'].get('mean'),
                    'signed_rotation_mean_deg':state_stats['net_signed_rotation_deg'].get('mean'),
                    'position_accel_p95_ipd_s2':state_stats['roughness']['position_accel_ipd_s2'].get('p95'),
                    'angular_accel_p95_deg_s2':state_stats['roughness']['angular_accel_deg_s2'].get('p95')})
            er['replay'][str(tau)]=stats
        # Export trajectories and signed residuals individually.
        for i,r in enumerate(rr):
            if not valid[i]:continue
            row={'eye':eye,'evaluation':int(evaluation[i]),'frameId':int(r['frameId']),
                 'render_elapsed_relative_s':t[i],'render_frame_relative_s':rt[i],
                 'state_observed_source':cat[i],'open_comparable':int(comparable[i]),
                 'stable_rest':int(stable_rest[i]),
                 'reference_vx_world_s':rv[i,0],'reference_vy_world_s':rv[i,1],'reference_vz_world_s':rv[i,2]}
            for name in PAIRS:
                for k,a in enumerate('xyz'):row[name+'_p'+a+'_ipd']=dp[name][i,k];row[name+'_r'+a+'_deg']=dr[name][i,k]
                row[name+'_signed_pos_ipd']=signed_p[name][i];row[name+'_signed_rot_deg']=signed_r[name][i]
            for s in STAGES:
                for k,a in enumerate('xyz'):row[s+'_p'+a]=ps[s][i,k]
                for k,a in enumerate('xyzw'):row[s+'_q'+a]=qs[s][i,k]
            correction_rows.append(row)
        for j,i in enumerate(ix):
            unique_rows.append({'eye':eye,'sessionId':int(rr[i]['sessionId']),'frameId':int(rr[i]['frameId']),
                'sensor_relative_s':st[j],'publication_elapsed_relative_s':(int(rr[i]['publicationAfterNs'])-origin)/1e9,
                'reference_speed_ipd_s':sv[j],'reference_angular_speed_deg_s':sw[j],'state':categories[j],
                'input_x':ps['input'][i,0],'input_y':ps['input'][i,1],'input_z':ps['input'][i,2]})
        # Shade observed source classification. Times are availability times, not exposure/render equivalence.
        bands=[]
        for i in range(n-1):
            if comparable[i] and cat[i] in ('rest','fast'):
                bands.append((t[i],t[i+1], '#93c5a5' if cat[i]=='rest' else '#f3b26b'))
        def masked(a):return np.where(valid,a,np.nan)
        panels=[]
        for k,a in enumerate('xyz'):
            panels.append({'label':a.upper()+' (unidades de mundo)', 'series':[(s,t,masked(ps[s][:,k]),COLORS[s]) for s in STAGES]})
        svg_plot(out/f'eye_{eye}_positions.svg',f'Ojo {eye}: posiciones; input/euro = muestra disponible, no rostro actual',panels,bands,events)
        qpanels=[]
        for k,a in enumerate('xyzw'):
            series=[]
            for s in ('predicted','blend','follower','final'):
                qq=qs[s].copy();previous=None
                for i in range(n):
                    if not valid[i]:previous=None;continue
                    if previous is not None and np.dot(previous,qq[i])<0:qq[i]*=-1
                    previous=qq[i]
                series.append((s,t,masked(qq[:,k]),COLORS[s]))
            qpanels.append({'label':'Cuaternion q'+a+' (normalizado; hemisferio continuo)', 'series':series})
        svg_plot(out/f'eye_{eye}_quaternions.svg',f'Ojo {eye}: cuaterniones por evaluacion',qpanels,bands,events)
        corr_panels=[]
        for angular in (False,True):
            series=[]
            for name,s in [('one_euro','euro'),('prediction_advance','predicted'),('blend_correction','blend'),('follower_correction','follower'),('eyelid_adjustment','final')]:
                val=np.linalg.norm(dr[name] if angular else dp[name]*100,axis=1)
                series.append((name,t,masked(val),COLORS[s]))
            corr_panels.append({'label':'Magnitud angular (grados)' if angular else 'Magnitud posicion (% distancia interocular)', 'series':series})
        svg_plot(out/f'eye_{eye}_corrections.svg',f'Ojo {eye}: diferencias entre etapas; no son errores fisicos',corr_panels,bands,events)
        signed=[]
        for angular in (False,True):
            series=[]
            for name,s in [('prediction_advance','predicted'),('blend_correction','blend'),('follower_correction','follower'),('predicted_to_final','final')]:
                val=(signed_r[name] if angular else signed_p[name]*100).copy()
                eligible=comparable & (np.linalg.norm(rw if angular else rv,axis=1)>(10 if angular else .1*scale))
                series.append((name,t,np.where(eligible,val,np.nan),COLORS[s]))
            signed.append({'label':'Proyeccion sobre giro observado (grados); negativo = se opone' if angular else 'Proyeccion sobre movimiento observado (% interocular); negativo = se opone','series':series})
        svg_plot(out/f'eye_{eye}_signed.svg',f'Ojo {eye}: signo relativo a la ultima muestra observada',signed,bands,events)
        rpanels=[]
        for angular in (False,True):
            series=[]
            for tau,color in [(30,COLORS['follower']),(25,COLORS['tau25']),(20,COLORS['tau20'])]:
                fp,fq=replays[tau][2:]
                net=rotation_difference(qs['predicted'][fi],fq) if angular else (fp-ps['predicted'][fi])/scale*100
                val=np.linalg.norm(net,axis=1)
                series.append((f'blend tau={tau}ms',t[fi],np.where(comparable[fi],val,np.nan),color))
            rpanels.append({'label':'Follower vs prediccion (grados)' if angular else 'Follower vs prediccion (% interocular)', 'series':series})
        svg_plot(out/f'eye_{eye}_replay.svg',f'Ojo {eye}: replay condicional, predicciones fijas; no mide lag visible',rpanels,bands,events)
        report['eyes'][str(eye)]=er
    (out/'metrics.json').write_text(json.dumps(report,indent=2,allow_nan=False),encoding='utf-8')
    write_csv(out/'stage_metrics.csv',metric_rows);write_csv(out/'segments.csv',segment_rows)
    write_csv(out/'render_trajectories_and_corrections.csv',correction_rows)
    write_csv(out/'processed_samples.csv',unique_rows);write_csv(out/'replay_metrics.csv',replay_rows)
    figures=''.join(f'<h2>{p.stem}</h2><a href="{p.name}">Abrir SVG</a><object data="{p.name}" type="image/svg+xml" style="width:100%;height:{1100 if "quaternions" in p.name else 900 if "positions" in p.name or "partial_rebase" in p.name else 700 if "turn_detail" in p.name else 610}px"></object>' for p in sorted(out.glob('*.svg')))
    page='''<!doctype html><html lang="es"><meta charset="utf-8"><title>Analisis offline de trayectorias AR</title><style>body{font:16px Arial;max-width:1350px;margin:25px auto;background:#f5f7fa;color:#263238}object{background:white}h2{margin-top:40px}a{color:#1565aa}</style><h1>Trayectorias AR: captura 1793307088974</h1><p>Analisis offline Python/NumPy. Verde: reposo observado; naranja: movimiento rapido observado. Lineas rojas: candidatos de frenada/inversion, no anotaciones de video.</p><p>Input/euro pertenecen a la ultima muestra disponible. Prediccion/blend/follower/final son evaluaciones posteriores. Ninguna distancia se convierte a milisegundos de lag visible.</p><p>Posicion normalizada por mediana de distancia interocular: no son metros ni milimetros. Replay tau25/tau20 conserva las predicciones registradas y no demuestra adherencia fisica.</p><p><a href="metrics.json">Metricas completas</a> | <a href="stage_metrics.csv">Metricas por etapa</a> | <a href="replay_metrics.csv">Replay</a> | <a href="segments.csv">Segmentos</a> | <a href="render_trajectories_and_corrections.csv">Trayectorias individuales</a> | <a href="processed_samples.csv">Muestras procesadas</a></p>'''+figures+'</html>'
    (out/'report.html').write_text(page,encoding='utf-8')
    print(json.dumps({'validation':{k:report[k] for k in ('rows','flags','median_intereye_world_units')},'eyes':{k:{x:v[x] for x in ('render_rows','strict_valid','open_comparable','rest_render_rows','fast_render_rows','new_sample_stasis')} for k,v in report['eyes'].items()}},indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('input',type=Path);parser.add_argument('--out',type=Path,default=Path(__file__).parent)
    args=parser.parse_args();analyze(args.input,args.out)
