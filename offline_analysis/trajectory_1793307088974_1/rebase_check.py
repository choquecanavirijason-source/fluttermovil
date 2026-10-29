"""Conservative partial counterfactual: same-time rebase only where old/new
forecast horizons are demonstrably below the 250ms minimum cap. No assumption
about current phone preview latency or cap margin. Other arrivals use baseline.
Not a complete replay of an unimplemented Android variant or a physical error.
"""
import csv,json,math
from pathlib import Path
import numpy as np
from analyze import unit, multiply, conjugate, rotation_difference, nlerp, summary, replay_follower,stage_jitter,svg_plot,COLORS

ROOT=Path(__file__).parent
INPUT=Path(r'E:/AndroidBuildCache/pose_trajectory/pose_trajectory_1793307088974_1.csv')
rows=list(csv.DictReader(x for x in INPUT.open() if not x.startswith('#')))
export=list(csv.DictReader((ROOT/'render_trajectories_and_corrections.csv').open()))
metrics=json.loads((ROOT/'metrics.json').read_text());scale=metrics['median_intereye_world_units']
report={}

def pure(h,T):
    a,b,c=h[-3:];dt0=b[0]-a[0];dt1=c[0]-b[0]
    v0=(b[1]-a[1])/dt0;v1=(c[1]-b[1])/dt1
    vel=v1*T;acc=.5*(v1-v0)/((dt0+dt1)*.5)*T*T
    lim=np.linalg.norm(vel)*.5
    if np.linalg.norm(acc)>lim and np.linalg.norm(acc)>1e-30:acc*=lim/np.linalg.norm(acc)
    return c[1]+vel+acc,nlerp(b[2],c[2],1+T/dt1)

for eye in [0,1]:
    rr=[r for r in rows if int(r['eye'])==eye and int(r['flags']) in (0,64)]
    arr=lambda s,c:np.array([[float(r[s+'_'+c+x]) for x in ('xyz' if c=='p' else 'xyzw')] for r in rr])
    pp=arr('predicted','p');pq=unit(arr('predicted','q'));ep=arr('euro','p');eq=unit(arr('euro','q'))
    bp=arr('blend','p');bq=unit(arr('blend','q'))
    recorded_fp=arr('follower','p');recorded_fq=unit(arr('follower','q'))
    t=(np.array([int(r['frameTimeNanos']) for r in rr])-int(rr[0]['frameTimeNanos']))/1e9
    functional=(np.array([int(r['functionalNs']) for r in rr])-int(rr[0]['frameTimeNanos']))/1e9
    elapsed=(np.array([int(r['renderElapsedNs']) for r in rr])-min(int(r['renderElapsedNs']) for r in rows))/1e9
    outp=np.empty_like(pp);outq=np.empty_like(pq);outp[0]=bp[0];outq[0]=bq[0]
    corr=bp[0]-pp[0];corrq=multiply(bq[0],conjugate(pq[0]));start=t[0];enabled=False
    hist=[(functional[0],ep[0],eq[0])];new_count=0;eligible=0;checks=[];records=[]
    for i in range(1,len(rr)):
        new=rr[i]['frameId']!=rr[i-1]['frameId']
        if new:
            new_count+=1
            oldhist=hist.copy();hist.append((functional[i],ep[i],eq[i]))
            observed=np.linalg.norm(bp[i]-pp[i])>1e-8 or np.linalg.norm(rotation_difference(pq[i],bq[i]))>1e-3
            if observed:enabled=True
            targetp=outp[i-1];targetq=outq[i-1];used=False
            if enabled and len(hist)>=5:
                qb=hist[-2][2];qc=hist[-1][2];qp=pq[i]
                if np.dot(qb,qc)<0:qc=-qc
                if np.dot(qb,qp)<0:qp=-qp
                if np.linalg.norm(rotation_difference(qb,qc))>.05:
                    coeff=np.linalg.lstsq(np.column_stack([qc-qb,-qp]),-qb,rcond=None)[0]
                    dt=hist[-1][0]-hist[-2][0];T=(coeff[0]-1)*dt;oldT=T+dt
                    if 0<T<.249 and 0<oldT<.249:
                        checkp,checkq=pure(hist,T)
                        err=np.linalg.norm(checkp-pp[i]);checks.append(err)
                        if err<1e-5:
                            oldp,oldq=pure(oldhist,oldT)
                            decay=math.exp(-(t[i]-start)/.03)
                            targetp=oldp+corr*decay
                            targetq=multiply(nlerp(np.array([0.,0.,0.,1.]),corrq,decay),oldq)
                            used=True;eligible+=1
                            records.append({'eye':eye,'evaluation':int(rr[i]['renderEvaluationId']),'frameId':int(rr[i]['frameId']),
                                            't_s':elapsed[i],'effective_new_ms':T*1000,'effective_old_ms':oldT*1000,
                                            'current_prediction_validation_world':err})
            if enabled and t[i]-t[i-1]<=.1:
                corr=targetp-pp[i];corrq=multiply(targetq,conjugate(pq[i]));start=t[i]
            else:corr=np.zeros(3);corrq=np.array([0.,0.,0.,1.])
        if enabled:
            decay=math.exp(-(t[i]-start)/.03)
            if decay<1e-3:outp[i]=pp[i];outq[i]=pq[i]
            else:outp[i]=pp[i]+corr*decay;outq[i]=multiply(nlerp(np.array([0.,0.,0.,1.]),corrq,decay),pq[i])
        else:outp[i]=pp[i];outq[i]=pq[i]
    fp,fq=replay_follower(t,outp,unit(outq),recorded_fp[0],recorded_fq[0])
    lookup={int(r['evaluation']):r for r in export if int(r['eye'])==eye}
    states={}
    for state in ('rest','rest_stable','fast'):
        mask=np.array([int(r['renderEvaluationId']) in lookup and (lookup[int(r['renderEvaluationId'])]['stable_rest']=='1' if state=='rest_stable' else lookup[int(r['renderEvaluationId'])]['state_observed_source']==state and lookup[int(r['renderEvaluationId'])]['open_comparable']=='1') for r in rr])
        states[state]={'n':int(np.sum(mask)),'baseline':{},'partial_rebase':{}}
        for name,pos,quat in [('baseline',recorded_fp,recorded_fq),('partial_rebase',fp,fq)]:
            states[state][name]={'net_position_percent_ipd':summary(np.linalg.norm(pos-pp,axis=1)[mask]/scale*100),
                                'net_angle_deg':summary(np.linalg.norm(rotation_difference(pq,quat),axis=1)[mask]),
                                'roughness':stage_jitter(t,pos,quat,mask,scale)}
    report[str(eye)]={'new_samples':new_count,'rebase_eligible':eligible,'position_reconstruction_checks':summary(checks),'states':states,
                     'limitation':'Only old/new effective horizons <249ms; baseline elsewhere. Quaternion inversion plus position cross-check, not physical ground truth.'}
    with (ROOT/f'eye_{eye}_rebase_eligible.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(records[0]));w.writeheader();w.writerows(records)
    series=[]
    for axis,label in enumerate('XYZ'):
        series.append({'label':label+' posicion (mundo), replay parcial', 'series':[
            ('predicted',elapsed,pp[:,axis],COLORS['predicted']),('baseline follower',elapsed,recorded_fp[:,axis],COLORS['follower']),
            ('partial same-time',elapsed,fp[:,axis],COLORS['tau25'])]})
    svg_plot(ROOT/f'eye_{eye}_partial_rebase.svg',f'Ojo {eye}: rebase parcial contrafactual; solo {eligible}/{new_count} llegadas',series)
(ROOT/'partial_rebase_metrics.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
