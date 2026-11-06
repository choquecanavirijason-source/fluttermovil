package com.example.test_face.render
import dev.romainguy.kotlin.math.*
import io.github.sceneview.geometries.Geometry
import java.io.File
import java.nio.*
import kotlin.math.*
fun main(args:Array<String>) {
 var worst=0f; var count=0
 for(file in File(args[0]).listFiles()!!.filter{it.extension=="bin"}) {
  val bytes=ByteBuffer.wrap(file.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
  val vertices=List(bytes.remaining()/12){Geometry.Vertex(Float3(bytes.float,bytes.float,bytes.float))}
  val minY=vertices.minOf{it.position.y};val raw=RawMesh(vertices,vertices.minOf{it.position.x},vertices.maxOf{it.position.x},minY)
  val tolerance=(vertices.maxOf{it.position.y}-minY)*0.005f
  val roots=vertices.indices.filter{vertices[it].position.y-minY<=tolerance}
  val lo=roots.minOf{vertices[it].position.x};val hi=roots.maxOf{vertices[it].position.x}
  val depths=LashRootDepth.perVertex(raw)
  val out=FloatBuffer.allocate(vertices.size*3);val tan=FloatBuffer.allocate(vertices.size*4);val rest=FloatArray(vertices.size*4){if(it%4==3)1f else 0f}
  for(height in listOf(-0.06f,0.025f)) for(closed in listOf(0f,1f)) {
   val world=(0..7).map{val t=it/7f;Float3(-0.15f+t*0.3f,0.03f+height*(1-(2*t-1).pow(2)),-2f)}
   val base=Quaternion(0f,0f,0f,1f);val scale=Float3(0.3f/(hi-lo),0.465f/(hi-lo),0.3f/(hi-lo));val position=Float3(0f,0f,-2f)
   val drop=LidDropRotation.apply(closed,minY,scale.y,base);val q=drop?.rotation?:base;val p=position+(drop?.positionDelta?:Float3())
   val binding=LashRootBinding.fromWorld(world,p,q,scale,lo,hi)!!
   check(LashMeshBender.bendInPlace(raw,out,null,rest,tan,1f,null,LashStyleConfig(),100f,rootDepths=depths,rootBinding=binding))
   for(i in roots) {
    val v=Float3(out[i*3]*scale.x,out[i*3+1]*scale.y,out[i*3+2]*scale.z)
    val actual=p+rotate(q,v)
    val ax=actual.x/-actual.z*640f;val ay=actual.y/-actual.z*480f
    var distance=Float.MAX_VALUE
    for(j in 0..6){val a=world[j];val b=world[j+1];val x=a.x/2*640;val y=a.y/2*480;val dx=(b.x-a.x)/2*640;val dy=(b.y-a.y)/2*480;val t=(((ax-x)*dx+(ay-y)*dy)/(dx*dx+dy*dy)).coerceIn(0f,1f);distance=min(distance,hypot(ax-x-t*dx,ay-y-t*dy))}
    worst=max(worst,distance)
    check(distance<2f){"Real asset root mismatch $distance px ${file.name} closed=$closed"}
   }
  }
  count++
 }
 println("PASS: $count actual GLB assets, open and closed transforms, measured base-row vertices within 2px of target; worst=$worst px")
}
