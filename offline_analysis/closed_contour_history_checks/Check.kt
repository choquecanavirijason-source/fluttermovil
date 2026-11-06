package com.example.test_face.render
data class ImagePoint(val x:Float,val y:Float)
object RendererConfiguration { const val LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER = 0.5f }
fun main() {
 fun curve(h:Float) = LashLineCurve.fit(listOf(ImagePoint(-50f,0f),ImagePoint(0f,-h),ImagePoint(50f,0f)),ImagePoint(0f,0f),ImagePoint(1f,0f))!!
 val openA=curve(15f); val openB=curve(5f); val closed=curve(-3f); val otherClosed=curve(-1f)
 for (held in listOf(null,openA,openB)) {
  val state=ClosedLidContour()
  check(state.resolve(held,null,0f,0)==held)
  state.resolve(held,closed,0.1f,10_000_000)
  check(state.resolve(held,closed,0.1f,310_000_000) === closed) { "Inherited prior open contour" }
  check(state.resolve(held,otherClosed,0.1f,320_000_000) === otherClosed) { "Inherited prior closed contour" }
  check(state.resolve(openB,null,0f,330_000_000) === openB) { "Open geometry changed" }
  val brief=state.resolve(openB,closed,0f,340_000_000)
  check(brief === openB) { "Existing brief-closure transition changed" }
  state.reset()
  check(state.resolve(null,closed,0f,0) === closed) { "Closed-first needs an open sample" }
 }
 println("PASS: closed-first and open-to-closed settle to identical measured contour; different open/closed faces cannot retain an old arc; open geometry and brief-closure weight retained")
}
