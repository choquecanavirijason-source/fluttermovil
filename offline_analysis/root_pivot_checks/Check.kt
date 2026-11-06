package com.example.test_face.render
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry
import java.nio.FloatBuffer
import kotlin.math.*
fun main() {
 val xs=(0..63).map { -1f+2f*it/63 }
 val verts=xs.flatMap { x -> val z=-0.2f-0.35f*x*x; listOf(Geometry.Vertex(Float3(x,-0.4f,z)),Geometry.Vertex(Float3(x,0.5f,z+0.3f))) }
 val raw=RawMesh(verts,-1f,1f,-0.4f)
 val depths=LashRootDepth.perVertex(raw)
 val rest=FloatArray(verts.size*4) { if(it%4==3) 1f else 0f }
 val plain=FloatBuffer.allocate(verts.size*3); val out=FloatBuffer.allocate(verts.size*3); val tangent=FloatBuffer.allocate(verts.size*4)
 var worst=0f
 for (height in listOf(0f,3f,12f)) {
  val curve=LashLineCurve.fit(listOf(ImagePoint(-50f,0f),ImagePoint(0f,-height),ImagePoint(50f,0f)),ImagePoint(0f,0f),ImagePoint(1f,0f))!!
  for (ratio in listOf(0.7f,1f,1.55f,2.4f)) {
   for (wing in listOf(0f,1f)) {
    val style=LashStyleConfig(foxyLiftMultiplier=wing)
    LashMeshBender.bendInPlace(raw,plain,null,rest,tangent,1f,curve,style,100f)
    for (angle in -150..150) {
     val theta=Math.toRadians(angle.toDouble()).toFloat()
     LashMeshBender.bendInPlace(raw,out,null,rest,tangent,1f,curve,style,100f,rootDepths=depths,dropRadians=theta,scaleYToZ=ratio)
     for(i in xs.indices) {
      val v=i*2; val y=(out[v*3+1]-raw.minY)*ratio; val z=out[v*3+2]
      val actualY=cos(theta)*y-sin(theta)*z
      val actualZ=sin(theta)*y+cos(theta)*z
      val expectedY=(plain[v*3+1]-raw.minY)*ratio; val expectedZ=plain[v*3+2]
      worst=max(worst,max(abs(actualY-expectedY),abs(actualZ-expectedZ)))
      check(abs(actualY-expectedY)<0.000003f && abs(actualZ-expectedZ)<0.000003f)
      if(angle==0) for(k in 0..2) check(out[v*3+k]==plain[v*3+k])
      // Fibers keep their drop and length about their own attachment point.
      val fy=(out[(v+1)*3+1]-out[v*3+1])*ratio
      val fz=out[(v+1)*3+2]-out[v*3+2]
      check(abs(sqrt(fy*fy+fz*fz)-sqrt((0.9f*ratio).pow(2)+0.3f.pow(2)))<0.000003f)
     }
    }
   }
  }
 }
 println("PASS: roots stationary through +/-150 degrees including 90, straight/round contours, unequal Y/Z scales, depth wrapping; open geometry exact; fiber drop/length retained. Worst=$worst")
}
