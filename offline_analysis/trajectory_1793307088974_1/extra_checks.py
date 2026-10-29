"""Sensitivity, event windows and paired-eye integrity; no changes to filter."""
from pathlib import Path
import csv,json,collections
import numpy as np
from analyze import svg_plot,COLORS,summary,rotation_difference,unit,write_csv
root=Path(__file__).parent
rows=list(csv.DictReader(x for x in open(r'E:/AndroidBuildCache/pose_trajectory/pose_trajectory_1793307088974_1.csv') if not x.startswith('#')))
data=list(csv.DictReader((root/'render_trajectories_and_corrections.csv').open()))
samples=list(csv.DictReader((root/'processed_samples.csv').open()))
segments=list(csv.DictReader((root/'segments.csv').open()))
base=json.loads((root/'metrics.json').read_text())
out={'threshold_sensitivity':{},'event_windows':{},'paired_eyes':{},'publication_path':{}}
paired=collections.defaultdict(dict)
for r in rows:
    if int(r['flags'])==0:paired[int(r['renderEvaluationId'])][int(r['eye'])]=r
both=[p for p in paired.values() if set(p)=={0,1}]
out['paired_eyes']={'valid_paired_evaluations':len(both),
    'same_source_frame':sum(p[0]['frameId']==p[1]['frameId'] for p in both),
    'different_source_frame':sum(p[0]['frameId']!=p[1]['frameId'] for p in both),
    'same_choreographer_time':sum(p[0]['frameTimeNanos']==p[1]['frameTimeNanos'] for p in both),
    'publication_delta_ms':summary([(int(p[1]['publicationBeforeNs'])-int(p[0]['publicationBeforeNs']))/1e6 for p in both if p[0]['frameId']==p[1]['frameId']])}
event_rows=[]
for eye in (0,1):
    all_eye=[r for r in rows if int(r['eye'])==eye]
    unique_valid={r['frameId']:r for r in all_eye if int(r['flags'])==0}
    ss=list(unique_valid.values())
    euro_to_pub=np.array([(int(r['publicationBeforeNs'])-int(r['euroElapsedNs']))/1e6 for r in ss])
    callback_to_euro=np.array([(int(r['euroElapsedNs'])-int(r['callbackElapsedNs']))/1e6 for r in ss])
    callback_to_pub=np.array([(int(r['publicationAfterNs'])-int(r['callbackElapsedNs']))/1e6 for r in ss])
    candidates=[]
    render_times=np.array([int(r['renderElapsedNs']) for r in all_eye],dtype=np.int64)
    for sample in ss:
        # Render record timestamp is after node writes, not exact sample consumption.
        # These are overlap opportunities, not a guaranteed number of saved vsyncs.
        lo=int(sample['euroElapsedNs']);hi=int(sample['publicationBeforeNs'])
        overlap=[r for r in all_eye if lo<=int(r['renderElapsedNs'])<hi and int(r['flags'])==0 and r['frameId']!=sample['frameId']]
        candidates.append({'eye':eye,'frameId':sample['frameId'],'euro_to_publication_ms':(hi-lo)/1e6,
                           'render_records_overlapping_before_publication':len(overlap)})
    out['publication_path'][str(eye)]={'processed_strict_valid':len(ss),'euro_to_publication_ms':summary(euro_to_pub),
        'callback_to_euro_ms':summary(callback_to_euro),'callback_to_publication_ms':summary(callback_to_pub),
        'source_samples_with_overlapping_render_record':sum(r['render_records_overlapping_before_publication']>0 for r in candidates),
        'overlapping_render_records':sum(r['render_records_overlapping_before_publication'] for r in candidates),
        'caveat':'renderElapsed is recorded after final node writes; overlap does not guarantee earlier consumption would save a frame'}
    write_csv(root/f'eye_{eye}_publication_opportunities.csv',candidates)
    tt=np.array([(int(r['publicationAfterNs'])-min(int(r['renderElapsedNs']) for r in rows))/1e9 for r in ss])
    svg_plot(root/f'eye_{eye}_publication_timing.svg',f'Ojo {eye}: demoras medidas en elapsed, una marca por muestra procesada',[
        {'label':'Milisegundos; no son lag visible','series':[
            ('callback -> euro',tt,callback_to_euro,COLORS['euro']),
            ('euro -> publicacion',tt,euro_to_pub,COLORS['blend']),
            ('callback -> publicacion',tt,callback_to_pub,COLORS['follower'])]}])
    rr=[r for r in data if int(r['eye'])==eye]
    t=np.array([float(r['render_elapsed_relative_s']) for r in rr]);available=np.array([r['open_comparable']=='1' for r in rr])
    sample_map={r['frameId']:r for r in samples if int(r['eye'])==eye}
    v=np.array([float(sample_map[r['frameId']]['reference_speed_ipd_s']) for r in rr]);w=np.array([float(sample_map[r['frameId']]['reference_angular_speed_deg_s']) for r in rr])
    out['threshold_sensitivity'][str(eye)]=[]
    for pv,av in ((.4,30),(.6,45),(.8,60)):
        fast=available&((v>pv)|(w>av));row={'position_threshold_ipd_s':pv,'angular_threshold_deg_s':av,'n_render':int(np.sum(fast))}
        for stage in ('blend_correction','follower_correction'):
            vec=np.array([[float(r[stage+'_p'+a+'_ipd']) for a in 'xyz'] for r in rr]);rv=np.array([[float(r[stage+'_r'+a+'_deg']) for a in 'xyz'] for r in rr])
            pn=np.linalg.norm(vec,axis=1);rn=np.linalg.norm(rv,axis=1)
            ps=np.array([float(r[stage+'_signed_pos_ipd']) for r in rr]);rs=np.array([float(r[stage+'_signed_rot_deg']) for r in rr])
            a=fast&(v>.1)&(pn>.0001);b=fast&(w>10)&(rn>.01)
            row[stage+'_position_opposed']=float(np.mean(ps[a]/pn[a]<-.5)) if np.any(a) else None
            row[stage+'_angular_opposed']=float(np.mean(rs[b]/rn[b]<-.5)) if np.any(b) else None
        out['threshold_sensitivity'][str(eye)].append(row)
    out['event_windows'][str(eye)]={}
    for typ in ('brake_candidate','reversal_candidate'):
        ev=[float(r['available_elapsed_relative_s']) for r in segments if r['eye']==str(eye) and r['type']==typ]
        mask=available&np.array([any(0<=tt-ee<=.25 for ee in ev) for tt in t])
        out['event_windows'][str(eye)][typ]={'events':len(ev),'n_render':int(np.sum(mask))}
        for stage in ('blend_correction','follower_correction','predicted_to_final'):
            pos=np.array([[float(r[stage+'_p'+a+'_ipd']) for a in 'xyz'] for r in rr]);rot=np.array([[float(r[stage+'_r'+a+'_deg']) for a in 'xyz'] for r in rr])
            metrics={'position_percent_ipd':summary(np.linalg.norm(pos,axis=1)[mask]*100),'angle_deg':summary(np.linalg.norm(rot,axis=1)[mask])}
            out['event_windows'][str(eye)][typ][stage]=metrics
            event_rows.append({'eye':eye,'window':typ,'stage':stage,'n':int(np.sum(mask)),
                'position_mean_percent_ipd':metrics['position_percent_ipd'].get('mean'),'angle_mean_deg':metrics['angle_deg'].get('mean')})
    # Same zoom for both eyes, showing a repeated observed reversal/braking interval.
    mask=(t>=7.2)&(t<=8.5);panels=[]
    for kind,label in [('p','Posicion en eje principal (% distancia interocular)'),('q','Orientacion en eje principal (grados)')]:
        axis=np.array(base['eyes'][str(eye)]['motion_pc_position' if kind=='p' else 'motion_pc_rotation'])
        series=[]
        q0=unit(np.array([float(rr[0]['euro_q'+a]) for a in 'xyzw']))
        for stage in ('input','euro','predicted','blend','follower','final'):
            if kind=='p':
                p=np.array([[float(r[stage+'_p'+a]) for a in 'xyz'] for r in rr]);values=(p@axis)/base['median_intereye_world_units']*100
            else:
                q=unit(np.array([[float(r[stage+'_q'+a]) for a in 'xyzw'] for r in rr]));values=rotation_difference(np.broadcast_to(q0,q.shape),q)@axis
            series.append((stage,t[mask],values[mask],COLORS[stage]))
        panels.append({'label':label,'series':series})
    ev=[float(r['available_elapsed_relative_s']) for r in segments if r['eye']==str(eye) and r['type'].endswith('candidate')]
    svg_plot(root/f'eye_{eye}_turn_detail.svg',f'Ojo {eye}: detalle de giro/frenada observados; input/euro son muestras retenidas',panels,events=ev)
(root/'extra_checks.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
write_csv(root/'event_window_metrics.csv',event_rows)
print(json.dumps(out,indent=2))
