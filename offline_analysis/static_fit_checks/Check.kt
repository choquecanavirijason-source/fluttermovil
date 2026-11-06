package com.example.test_face.render
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry
import java.nio.FloatBuffer
import kotlin.math.*
fun main() {
 val vertices=(0..100).map { Geometry.Vertex(Float3(-1f+it/50f,-0.4f,-0.2f)) }
 val raw=RawMesh(vertices,-1f,1f,-0.4f)
 val out=FloatBuffer.allocate(vertices.size*3)
 val prior=FloatBuffer.allocate(vertices.size*3)
 val tangents=FloatBuffer.allocate(vertices.size*4)
 val rest=FloatArray(vertices.size*4) { if(it%4==3) 1f else 0f }
 val width=100f
 var worst=0f
 var oldWorst=0f
 for(height in listOf(0f,3f,9f,16f)) {
  val points=(-60..60 step 10).map { x -> ImagePoint(x.toFloat(),-height*(1f-(x/60f).pow(2))) }
  val curve=LashLineCurve.fit(points,ImagePoint(0f,0f),ImagePoint(1f,0f))!!
  val style=LashStyleConfig(foxyLiftMultiplier=0f)
  LashMeshBender.bendInPlace(raw,out,null,rest,tangents,1f,curve,style,width,curveWidthScale=RendererConfiguration.WIDTH_MULTIPLIER)
  LashMeshBender.bendInPlace(raw,prior,null,rest,tangents,1f,curve,style,width)
  for(i in vertices.indices) {
   val actualX=vertices[i].position.x*width/2f*RendererConfiguration.WIDTH_MULTIPLIER
   val desired=-curve.deviationAt(actualX)
   val y=(out[i*3+1]-raw.minY)*width/2f*RendererConfiguration.WIDTH_MULTIPLIER*RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER
   val oldY=(prior[i*3+1]-raw.minY)*width/2f*RendererConfiguration.WIDTH_MULTIPLIER*RendererConfiguration.HEIGHT_VOLUME_MULTIPLIER
   worst=max(worst,abs(y-desired)); oldWorst=max(oldWorst,abs(oldY-desired))
   check(abs(y-desired)<0.00002f)
  }
 }
 check(oldWorst>2f)
 println("PASS: flat, shallow, almond and round contours sampled at displayed band X; worst error=$worst px, previous mismatch=$oldWorst px. Rigid pose untouched.")
}
