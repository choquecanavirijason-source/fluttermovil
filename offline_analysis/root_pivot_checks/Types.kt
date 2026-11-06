package com.example.test_face.render
import io.github.sceneview.geometries.Geometry
data class ImagePoint(val x:Float,val y:Float)
data class RawMesh(val vertices:List<Geometry.Vertex>,val minX:Float,val maxX:Float,val minY:Float)
data class LashStyleConfig(val zDepthDropRadiusFraction:Float=0.5f,val foxyLiftMultiplier:Float=0f)
object RendererConfiguration {
const val WIDTH_MULTIPLIER = 1.15f
const val HEIGHT_VOLUME_MULTIPLIER = 1.55f
const val LASH_DEFORMATION_ENABLED = true
const val MESH_CALIBRATION_LOGGING = false
const val LASH_BEND_STRENGTH = 1.0f
const val LASH_BEND_WING_STRENGTH = 0.5f
const val LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER = 0.5f
}
