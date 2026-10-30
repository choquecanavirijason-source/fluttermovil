const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'../..'),out=process.argv[2];fs.mkdirSync(out,{recursive:true});
const file='android/app/src/main/kotlin/com/example/test_face/render/PoseInterpolator.kt';
const current=fs.readFileSync(path.join(root,file),'utf8').replace(/\r/g,'');
const committed=cp.execFileSync('git',['show','HEAD:'+file],{cwd:root,encoding:'utf8'}).replace(/\r/g,'');
const gate=`        // Session-fixed diagnostic: remove acceleration only for future position.
        // Keep the original expression (and operation order) in normal mode.
        val predictedPos = if (t > 0f && !com.example.test_face.PerfFlags.config.predictorPosQuadratic) {
            c.position + velocityTerm
        } else {
            c.position + velocityTerm + limitedAccelTerm
        }`;
const normalize=s=>s.replace(gate,'        val predictedPos = c.position + velocityTerm + limitedAccelTerm');
const old=normalize(committed);
assert(current.includes(gate));assert.equal(normalize(current),old);
function fun(s,name){let i=s.indexOf('    private fun '+name+'('),b=s.indexOf('{',i),n=1,j=b+1;assert(i>=0);for(;n;j++){if(s[j]==='{')n++;if(s[j]==='}')n--;}return s.slice(i,j).replace('private fun','fun');}
const methods=s=>[fun(s,'quadraticPredict'),fun(s,'lerpQuaternion'),fun(s,'lerpTransform'),'    private fun length(v: Float3): Float = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)'].join('\n');
const write=(f,s)=>fs.writeFileSync(path.join(out,f),s);
write('Context.kt',`package android.content
import java.io.File
class Context(val dir: File) { fun getExternalFilesDir(type: String?): File = dir; val applicationContext get()=this }
`);
write('Android.kt',`package android.util
data class Size(val width: Int, val height: Int)
object Log { val messages=mutableListOf<String>(); fun i(tag:String,text:String):Int { messages.add(text);return 0 }; fun w(tag:String,text:String,error:Throwable?=null):Int {messages.add(text);return 0} }
`);
write('Render.kt',`package com.example.test_face.render
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
object RendererConfiguration { const val FAST_MOTION_POSITION_SPANS_PER_SEC=1f; const val FAST_MOTION_ROTATION_VELOCITY=1f; const val PREVIEW_PATH_LATENCY_NANOS=0L }
object PoseInterpolator { const val INTERVAL_MARGIN_NANOS=1L; const val ABSOLUTE_MAX_EXTRAPOLATION_NANOS=1L }
object PoseTrajectoryTelemetry { fun configure(c:android.content.Context,b:Boolean) {} }
object BufferLifetimeTelemetry { fun configure(c:android.content.Context,b:Boolean) {} }
class LashLineCurve
data class EyeTransform(val position:Float3,val rotation:Quaternion,val scale:Float3,val opennessRatio:Float=1f,val lashLineCurve:LashLineCurve?=null,val eyeWidthPx:Float=0f,val lidShapeTrusted:Boolean=true,val normalizedOpenness:Float=1f)
`);
for(const [name,source]of [['Subject',current],['Baseline',old]])write(name+'.kt',`import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import com.example.test_face.render.EyeTransform
import kotlin.math.sqrt
class ${name} { val ACCEL_TERM_MAX_RATIO=0.5f
${methods(source)}
}
`);
const fixtures=JSON.parse(fs.readFileSync(path.join(__dirname,'event_fixtures.json'),'utf8')).cases;
const f=n=>Number(n).toExponential(12)+'f';
const tr=r=>`EyeTransform(Float3(${r.position.map(f).join(',')}),Quaternion(${r.rotation.map(f).join(',')}),Float3(1.1f,0.8f,1.4f),0.7f,curve,42f,false,0.9f)`;
let calls=[];
for(const e of fixtures){
calls.push(`runCase("${e.name}",${e.samples.map(tr).join(',')},${f(e.dt0Ns)},${f(e.dt1Ns)},${f(e.effectiveMs*1e6)}/${f(e.dt1Ns)},Float3(${e.expected.map(f).join(',')}))`);
}
write('Checks.kt',`import android.content.Context
import android.util.Log
import com.example.test_face.PerfFlags
import com.example.test_face.render.*
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import java.io.File
import kotlin.math.sqrt
private lateinit var ctx: Context
private lateinit var flags: File
private val curve=LashLineCurve()
private fun set(on:Boolean) {flags.writeText("predictor_pos_quadratic="+if(on) "on" else "off");PerfFlags.load(ctx,cameraSessionStart=true)}
private fun bits(a:Float3,b:Float3)=a.x.toBits()==b.x.toBits()&&a.y.toBits()==b.y.toBits()&&a.z.toBits()==b.z.toBits()
private fun distance(a:Float3,b:Float3):Float {val d=a-b;return sqrt(d.x*d.x+d.y*d.y+d.z*d.z)}
private fun runCase(label:String,a:EyeTransform,b:EyeTransform,c:EyeTransform,dt0:Float,dt1:Float,t:Float,logged:Float3?=null) {
 val base=Baseline().quadraticPredict(a,b,c,dt0,dt1,t)
 set(true);val on=Subject().quadraticPredict(a,b,c,dt0,dt1,t)
 check(bits(on.position,base.position));check(on==base)
 set(false);val off=Subject().quadraticPredict(a,b,c,dt0,dt1,t)
 val linear=c.position+((c.position-b.position)*(1f/dt1))*(t*dt1)
 check(bits(off.position,if(t>0f)linear else base.position)) {"OFF mismatch $label"}
 check(off.copy(position=base.position)==base) {"Non-position changed $label"}
 check(Subject().lerpTransform(b,c,0.4f)==Baseline().lerpTransform(b,c,0.4f))
 if(logged!=null) {check(distance(on.position,logged)<1e-6f);println("EVENT $label ON=$'{'on.position} OFF=$'{'off.position} delta=$'{'off.position-on.position}")}
}
fun main(args:Array<String>) {
 ctx=Context(File(args[0]).apply{mkdirs()});flags=File(ctx.dir,PerfFlags.FILE_NAME)
 check(PerfFlags.read(ctx).first.predictorPosQuadratic)
 for((text,expected)in listOf("" to true,"other=off" to true,"predictor_pos_quadratic=on" to true,"predictor_pos_quadratic=off" to false,"predictor_pos_quadratic= OFF " to false,"predictor_pos_quadratic=invalid" to true,"predictor_pos_quadratic=" to true)) {
  flags.writeText(text);check(PerfFlags.read(ctx,log=true).first.predictorPosQuadratic==expected)
 }
 set(true);flags.writeText("predictor_pos_quadratic=off");PerfFlags.load(ctx);check(PerfFlags.config.predictorPosQuadratic)
 check(Log.messages.any{it.contains("requested=off effective=on")})
 PerfFlags.load(ctx,cameraSessionStart=true);check(!PerfFlags.config.predictorPosQuadratic)
 flags.writeText("predictor_pos_quadratic=on");PerfFlags.load(ctx);check(!PerfFlags.config.predictorPosQuadratic)
 check(Log.messages.any{it.contains("requested=on effective=off")})
 PerfFlags.load(ctx,cameraSessionStart=true);check(PerfFlags.config.predictorPosQuadratic)
 check(PerfFlags.describe().contains("predictor_pos_quadratic=on"))
 set(false);flags.delete();PerfFlags.load(ctx);check(!PerfFlags.config.predictorPosQuadratic)
 PerfFlags.load(ctx,cameraSessionStart=true);check(PerfFlags.config.predictorPosQuadratic)
 ${calls.join('\n ')}
 val random=kotlin.random.Random(971)
 repeat(500) {i->
  fun transform()=EyeTransform(Float3(random.nextFloat(),random.nextFloat(),random.nextFloat()),Quaternion(0f,0f,0f,if(i%2==0)1f else -1f),Float3(1f,2f,3f),0.7f,curve,42f,false,0.9f)
  val a=transform();val b=transform();val c=transform()
  runCase("random$i",a,b,c,(30+random.nextInt(200))*1e6f,(30+random.nextInt(200))*1e6f,when(i%5){0->-0.5f;1->0f;else->random.nextFloat()*5f})
 }
 println("PASS: parser/default/session/logs; 6 event cases; 500 seeded cases; ON bitwise baseline; OFF exact linear for t>0; t<=0 and non-position unchanged")
}
`.replaceAll("$'{'",'${'));
console.log('PASS static: only quadratic position expression changed in PoseInterpolator; extracted baseline from HEAD');
