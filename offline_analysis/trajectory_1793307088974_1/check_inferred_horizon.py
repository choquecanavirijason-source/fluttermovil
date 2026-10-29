"""Cross-check an inference from quaternion nlerp. Not a presentation timestamp."""
import csv, numpy as np
from analyze import unit, multiply, conjugate, rotation_difference, summary
from pathlib import Path
p=Path(r'E:/AndroidBuildCache/pose_trajectory/pose_trajectory_1793307088974_1.csv')
rows=list(csv.DictReader(x for x in p.open() if not x.startswith('#')))
for eye in [0,1]:
    rr=[r for r in rows if int(r['eye'])==eye and int(r['flags']) in [0,64]]
    samples=[];h=[];ts=[];err=[];eligible=0
    for r in rr:
        if samples and r['frameId']==samples[-1]['frameId']:continue
        samples.append(r)
        if len(samples)<5:continue
        a,b,c=samples[-3:]
        q=lambda r,s:unit(np.array([float(r[s+'_q'+x]) for x in 'xyzw']))
        pos=lambda r:np.array([float(r['euro_p'+x]) for x in 'xyz'])
        qb=q(b,'euro');qc=q(c,'euro');qp=q(c,'predicted')
        if np.dot(qb,qc)<0:qc=-qc
        if np.dot(qb,qp)<0:qp=-qp
        if np.linalg.norm(rotation_difference(qb,qc))<.05:continue
        coeff=np.linalg.lstsq(np.column_stack([qc-qb,-qp]),-qb,rcond=None)[0]
        f=coeff[0];dt=(int(c['functionalNs'])-int(b['functionalNs']))/1e9;T=(f-1)*dt
        if T<=0:continue
        eligible+=1
        ta,tb,tc=[int(r['functionalNs'])/1e9 for r in (a,b,c)]
        va=(pos(b)-pos(a))/(tb-ta);vb=(pos(c)-pos(b))/(tc-tb)
        ac=(vb-va)/((tc-ta)/2);vel=vb*T;acc=.5*ac*T*T
        limit=np.linalg.norm(vel)*.5
        if np.linalg.norm(acc)>limit:acc*=limit/np.linalg.norm(acc)
        pred=pos(c)+vel+acc
        actual=np.array([float(c['predicted_p'+x]) for x in 'xyz'])
        e=np.linalg.norm(pred-actual);err.append(e)
        if e<1e-5 and T<.249:
            H=T-(int(c['frameTimeNanos'])-int(c['functionalNs']))/1e9
            h.append(H);ts.append(T)
    print(eye,'eligible',eligible,'position validation',summary(err),'unsaturated validated',len(h),'H_ms',summary(np.array(h)*1000),'T_ms',summary(np.array(ts)*1000))
