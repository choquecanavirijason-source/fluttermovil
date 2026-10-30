const fs = require('fs'), cp = require('child_process'), assert = require('assert'), path = require('path');
const root = path.resolve(__dirname,'../..');
const renderer = 'android/app/src/main/kotlin/com/example/test_face/render/LashRenderer.kt';
const read = f => fs.readFileSync(path.join(root,f),'utf8').replace(/\r/g,'');
const head = f => cp.execFileSync('git',['show',`HEAD:${f}`],{cwd:root,encoding:'utf8'}).replace(/\r/g,'');
const r=read(renderer), old=head(renderer);
const gate='if (!lashDeformationFrozen && (transform.lidShapeTrusted || bandScaleChanged) &&';
assert(r.includes(gate));
const from=r.indexOf(gate), to=r.indexOf('// Push directo',from);
assert(from>0 && to>from);
const block=r.slice(from,to);
for(const call of ['LashMeshBender.bendInPlace(', 'geometry.vertexBuffer.setBufferAt(', 'bufferWrite.upload(']) {
 assert(block.includes(call));
 assert.equal(r.split(call).length, block.split(call).length);
}
assert(r.indexOf('slot.interpolator.push(smoothed, nowNanos, publication, trajectory)',to)>to);
// OFF removes only two false guards from the existing applyTransform body.
const body=s=>s.slice(s.indexOf('    private fun applyTransform('),s.indexOf('    private fun loadIntoSlot('));
const normalize=s=>body(s).replace('!lashDeformationFrozen && ','').replace(/                        \/\/ A previous session[^\n]*\n                        \/\/ It must[^\n]*\n                        if \(lashDeformationFrozen\) return@post\n/,'');
assert.equal(normalize(r),normalize(old));
for(const f of ['LashMeshBender.kt','RendererConfiguration.kt','LinerRenderer.kt','FaceMeshRenderer.kt','EyeModelSlot.kt']) {
 const p='android/app/src/main/kotlin/com/example/test_face/render/'+f; assert.equal(read(p),head(p));
}
const manager=read('android/app/src/main/kotlin/com/example/test_face/CameraXManager.kt');
assert.equal(manager.split('beginCameraSession(').length,2);
assert(manager.indexOf('beginCameraSession(deformationFreeze)')<manager.indexOf('stopped.set(false)',manager.indexOf('fun start()')));
const reload=manager.slice(manager.indexOf('private fun reloadPerfFlagsIfChanged()'),manager.indexOf('private fun bindFlagsChanged'));
assert(!reload.includes('beginCameraSession')); assert(reload.includes('reportRequestedDeformationMode'));
assert(r.includes('slot.geometry?.setVertices(sv.engine, raw.vertices)'));
assert.equal((r.match(/lashDeformationFrozen = freeze/g)||[]).length,1);
console.log('PASS: OFF body equivalent; ON gates all dynamic lash uploads; pose publication retained; session latch and rest restoration; other renderers unchanged');
function walk(d){return fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(d,e.name)):[path.join(d,e.name)]);}
for(const f of walk(path.join(root,'assets/modelos')).filter(f=>f.endsWith('.glb'))) {
 const b=fs.readFileSync(f); assert.equal(b.readUInt32LE(0),0x46546c67);
 const j=JSON.parse(b.subarray(20,20+b.readUInt32LE(12)).toString().trim());
 assert(!j.animations?.length,f); assert(!j.skins?.length,f);
 for(const p of j.meshes.flatMap(m=>m.primitives)) { assert(!p.targets?.length,f); assert(j.accessors[p.attributes.POSITION].count>0,f); }
 console.log('PASS: static GLB, nonempty geometry, no animations/skins/morphs:',path.relative(root,f));
}
