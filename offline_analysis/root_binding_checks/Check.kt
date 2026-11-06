package com.example.test_face.render
import dev.romainguy.kotlin.math.*
import io.github.sceneview.geometries.Geometry
import java.nio.FloatBuffer
import kotlin.math.*
fun rotate(q:Quaternion,v:Float3):Float3 {
 val tx=2f*(q.y*v.z-q.z*v.y); val ty=2f*(q.z*v.x-q.x*v.z); val tz=2f*(q.x*v.y-q.y*v.x)
 return Float3(v.x+q.w*tx+q.y*tz-q.z*ty,v.y+q.w*ty+q.z*tx-q.x*tz,v.z+q.w*tz+q.x*ty-q.y*tx)
}
fun main() {
 val projection=Mat4(Float4(2f,0f,0f,0f),Float4(0f,2f,0f,0f),Float4(0f,0f,-1f,-1f),Float4(0f,0f,-0.2f,0f))
 val identity=Mat4(Float4(1f,0f,0f,0f),Float4(0f,1f,0f,0f),Float4(0f,0f,1f,0f),Float4(0f,0f,0f,1f))
 val camera=CameraProjection(projection,identity)
 val verts=(0..63).flatMap { i->val x=-1f+2f*i/63;val z=-0.2f-0.1f*x*x;listOf(Geometry.Vertex(Float3(x,-0.4f,z)),Geometry.Vertex(Float3(x,0.5f,z+0.3f))) }
 val raw=RawMesh(verts,-1f,1f,-0.4f); val depths=LashRootDepth.perVertex(raw)
 val out=FloatBuffer.allocate(verts.size*3); val tan=FloatBuffer.allocate(verts.size*4)
 val rest=FloatArray(verts.size*4){if(it%4==3)1f else 0f}
 var worst=0f
 for(height in listOf(-20f,0f,8f,18f)) {
  val pixels=listOf(0f,0.08f,0.24f,0.4f,0.6f,0.76f,0.92f,1f).map { t->ImagePoint(250f+140f*t,230f+height*(1f-(2*t-1).pow(2))) }
  val world=pixels.map { p->camera.unproject(2f*p.x/640f-1f,1f-2f*p.y/480f,-2f) }
  for(yaw in listOf(0f,0.35f,3.1415927f)) for(pitch in listOf(-0.3f,0f,0.4f)) for(closed in listOf(0f,0.35f,0.7f,1f)) {
   val base=Quaternion(0f,sin(yaw/2),0f,cos(yaw/2))*Quaternion(sin(pitch/2),0f,0f,cos(pitch/2))
   val scale=Float3(0.12f,0.19f,0.12f); val position=Float3(0.03f,0.02f,-2f)
   val drop=LidDropRotation.apply(closed,raw.minY,scale.y,base)
   val q=drop?.rotation?:base;val p=position+(drop?.positionDelta?:Float3())
   val binding=LashRootBinding.fromWorld(world,p,q,scale,-1f,1f)!!
   check(LashMeshBender.bendInPlace(raw,out,null,rest,tan,1f,null,LashStyleConfig(),140f,rootDepths=depths,rootBinding=binding))
   for(i in 0..63) {
    val k=i*6
    val v=Float3(out[k]*scale.x,out[k+1]*scale.y,out[k+2]*scale.z)
    val actual=p+rotate(q,v)
    val ax=(2*actual.x/-actual.z+1)*320;val ay=(1-2*actual.y/-actual.z)*240
    var distance=Float.MAX_VALUE
    for(j in 0 until pixels.size-1) {
     val a=pixels[j];val b=pixels[j+1];val dx=b.x-a.x;val dy=b.y-a.y
     val t=((ax-a.x)*dx+(ay-a.y)*dy)/(dx*dx+dy*dy)
     val u=t.coerceIn(0f,1f)
     distance=min(distance,hypot(ax-a.x-u*dx,ay-a.y-u*dy))
    }
    worst=max(worst,distance)
    check(distance<0.002f) { "Root projection mismatch $distance height=$height closed=$closed yaw=$yaw" }
    // Fiber offset is unchanged in model space: only its attachment moved.
    check(abs((out[k+4]-out[k+1])-0.9f)<0.000002f)
    check(abs((out[k+5]-out[k+2])-0.3f)<0.000002f)
   }
  }
 }
 println("PASS: full camera -> inverse final model -> actual bender -> model -> pixel projection. Open/closed/flat/round contours, unequal scales, rotated and reversed orientations. Worst root-to-green-line error=$worst px. Fiber drop offsets preserved.")
}
