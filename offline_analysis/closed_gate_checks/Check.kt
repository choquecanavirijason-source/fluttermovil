package com.example.test_face.render
fun main() {
 fun curve(h:Float)=LashLineCurve.fit(listOf(ImagePoint(-50f,0f),ImagePoint(0f,h),ImagePoint(50f,0f)),ImagePoint(0f,0f),ImagePoint(1f,0f))!!
 val held=curve(-15f); val measured=curve(4f)
 val tracker=OpennessTracker(); val state=ClosedLidContour()
 check(tracker.updateFromBlendshape(0.97f,0.35f))
 check(!ClosedLidContour.shouldMeasure(true,tracker.normalizedOpenness))
 // Actual phone samples: blink remains closed while geometric ratio crosses
 // the old second gate. Each sample arrives about 100 ms apart.
 val ratios=listOf(0.136f,0.150f,0.156f,0.143f,0.147f,0.155f,0.132f,0.155f)
 var oldDiscarded=0
 ratios.forEachIndexed { i, geo ->
  val trusted=tracker.updateFromBlendshape(0.22f,geo)
  check(!trusted) { "Fixture no longer classified closed" }
  val openness=tracker.normalizedOpenness
  if(openness>=0.3f) oldDiscarded++
  check(ClosedLidContour.shouldMeasure(trusted,openness)) { "Valid closed contour dropped at $openness" }
  val shape=state.resolve(held,measured,0f,i*100_000_000L)
  if(i>=3) check(shape === measured) { "Returned to previous open arc" }
 }
 check(oldDiscarded>=2)
 check(tracker.updateFromBlendshape(0.97f,0.35f))
 check(!ClosedLidContour.shouldMeasure(true,tracker.normalizedOpenness))
 check(state.resolve(held,null,0f,900_000_000) === held)
 println("PASS: actual closed-eye fluctuations retain current contour, settle to measured line, and reopen unchanged. Old gate discarded $oldDiscarded/8 closed samples.")
}
