package com.example.test_face.render

import android.os.SystemClock
import android.util.Log
import com.example.test_face.TrackingTimingTelemetry
import kotlin.math.abs
import kotlin.math.sqrt

/** Denominator-only diagnostics; nothing here is fed back to prediction. */
object PredictorTimingTelemetry {
    /** Created on the compute thread immediately before the existing push.
     * nanoTime is bracketed by elapsed reads; no absolute cross-clock subtraction.
     * afterElapsedNs is published separately because render may see Sample before push returns.
     */
    class Publication(val frame: TrackingTimingTelemetry.Context) {
        val clockElapsedBeforeNs = SystemClock.elapsedRealtimeNanos()
        val clockNanoNs = System.nanoTime()
        val beforeElapsedNs = SystemClock.elapsedRealtimeNanos()
        @Volatile var afterElapsedNs = 0L
            private set
        fun complete() { afterElapsedNs = SystemClock.elapsedRealtimeNanos() }
    }

    /** Reused by the existing main-thread -> worker SPSC ring. */
    internal class Event {
        var mid: Publication? = null; var latest: Publication? = null
        var midPose: EyeTransform? = null; var latestPose: EyeTransform? = null
        var midFunctionalNs = 0L; var latestFunctionalNs = 0L
        var source = 0; var eye = 0; var generation = 0; var mode = 0
        var horizonNs = 0L; var requestedNs = 0f; var capNs = 0f
        var factor = 0f; var functionalDtNs = 0f; var soft = false
        fun clear() { mid = null; latest = null; midPose = null; latestPose = null }
    }

    private data class Key(val session: Long, val source: Int, val eye: Int, val generation: Int)
    private val groups = LinkedHashMap<Key, Stats>() // worker only; at most 32 groups
    private val rejected = LongArray(5) // session/order, source, timestamps, clock rate, pose/horizon
    private var dirty = false
    private var lastMissing = 0L; private var lastDropped = 0L

    internal fun consume(e: Event) {
        val a = e.mid ?: return
        val b = e.latest ?: return
        val fa = a.frame; val fb = b.frame
        dirty = true
        if (fa.sessionId != fb.sessionId || fb.frameId <= fa.frameId) { rejected[0]++; return }
        if (fa.sensorSource != "REALTIME" || fb.sensorSource != "REALTIME") { rejected[1]++; return }
        val aa = a.afterElapsedNs; val ba = b.afterElapsedNs
        fun valid(p: Publication, after: Long): Boolean {
            val f = p.frame
            return f.sensorTimestampNs > 0L && f.sensorTimestampNs <= f.submitElapsedNs &&
                f.submitElapsedNs <= f.callbackElapsedNs && f.callbackElapsedNs <= p.clockElapsedBeforeNs &&
                p.clockElapsedBeforeNs <= p.beforeElapsedNs && p.beforeElapsedNs <= after
        }
        val dc = fb.sensorTimestampNs - fa.sensorTimestampNs
        val ds = fb.submitElapsedNs - fa.submitElapsedNs
        val db = fb.callbackElapsedNs - fa.callbackElapsedNs
        val df = e.latestFunctionalNs - e.midFunctionalNs
        // Bounds for the difference between two unknown instants inside push brackets.
        val dpLow = b.beforeElapsedNs - aa
        val dpHigh = ba - a.beforeElapsedNs
        if (!valid(a, aa) || !valid(b, ba) || dc <= 0L || ds <= 0L || db <= 0L || df <= 0L ||
            dpLow <= 0L || dpHigh < dpLow || fb.mpTimestampMs <= fa.mpTimestampMs ||
            e.functionalDtNs <= 0f || !e.functionalDtNs.isFinite()
        ) { rejected[2]++; return }

        // Check clock DURATION agreement at publication. This detects suspension/drift;
        // it does not claim the clocks have the same origin. Allow 0.1ms diagnostic
        // tolerance beyond the measured bracket, explicitly included in the report.
        val dn = b.clockNanoNs - a.clockNanoNs
        val deLow = b.clockElapsedBeforeNs - a.beforeElapsedNs
        val deHigh = b.beforeElapsedNs - a.clockElapsedBeforeNs
        if (dn <= 0L || dn < deLow - 100_000L || dn > deHigh + 100_000L) { rejected[3]++; return }
        val mid = e.midPose ?: return
        val latest = e.latestPose ?: return
        val dx = (latest.position.x - mid.position.x).toDouble()
        val dy = (latest.position.y - mid.position.y).toDouble()
        val dz = (latest.position.z - mid.position.z).toDouble()
        val displacement = sqrt(dx*dx + dy*dy + dz*dz)
        val functional = e.functionalDtNs.toDouble() // actual Float denominator used by predict
        val capture = dc.toDouble()
        val ratio = functional / capture
        val velocityScaleDifference = 1e9 / functional - 1e9 / capture
        val effective = e.factor.toDouble() * functional // actual extrapolation factor, reconstructed
        if (!displacement.isFinite() || !ratio.isFinite() || !effective.isFinite() ||
            !e.requestedNs.isFinite() || !e.capNs.isFinite()
        ) { rejected[4]++; return }
        val key = Key(fb.sessionId, e.source, e.eye, e.generation)
        val stats = groups[key] ?: Stats().also {
            if (groups.size == 32) {
                val oldest = groups.entries.first()
                log(oldest.key, oldest.value, "evicted")
                groups.remove(oldest.key)
            }
            groups[key] = it
        }
        stats.add(0, dc / 1e6); stats.add(1, ds / 1e6); stats.add(2, db / 1e6)
        stats.add(3, functional / 1e6); stats.add(4, (dpLow / 2.0 + dpHigh / 2.0) / 1e6)
        stats.add(5, ratio)
        stats.add(6, displacement * 1e9 / functional); stats.add(7, displacement * 1e9 / capture)
        stats.add(8, displacement * abs(velocityScaleDifference))
        stats.add(9, (dpHigh - dpLow) / 2e6)
        stats.add(10, e.horizonNs / 1e6); stats.add(11, e.requestedNs / 1e6)
        stats.add(12, effective / 1e6); stats.add(13, e.capNs / 1e6)
        stats.add(14, (dn - (deLow / 2.0 + deHigh / 2.0)) / 1e6)
        stats.add(15, (deHigh - deLow) / 2e6)
        stats.n++
        if (e.mode == 2) stats.quadratic++ else stats.linear++
        if (e.requestedNs > e.capNs) stats.limited++
        if (e.requestedNs < 0f) stats.clampedZero++
        if (e.soft) stats.soft++
        stats.midFrame = fa.frameId; stats.latestFrame = fb.frameId
        stats.midFunctional = e.midFunctionalNs; stats.latestFunctional = e.latestFunctionalNs
        stats.deltaVelocity = "(${dx*velocityScaleDifference},${dy*velocityScaleDifference},${dz*velocityScaleDifference})"
        stats.dirty = true
    }

    internal fun report(missing: Long, dropped: Long) {
        if (!dirty && missing == lastMissing && dropped == lastDropped) return
        dirty = false; lastMissing = missing; lastDropped = dropped
        Log.i("PredictorTiming", "PREDICTOR_TIMING diagnostic_only missingContext=$missing queueDropped=$dropped " +
            "rejected(session_order=${rejected[0]},source=${rejected[1]},timestamps=${rejected[2]},clock_duration=${rejected[3]},pose_horizon=${rejected[4]}) " +
            "clockToleranceMs=0.1 effectiveHorizon=reconstructed_from_functional_factor units_velocity=world_per_s")
        for ((key, stats) in groups) if (stats.dirty) { log(key, stats, "cumulative"); stats.dirty = false }
    }

    private fun log(key: Key, s: Stats, scope: String) {
        Log.i("PredictorTiming", "PREDICTOR_TIMING $scope sessionId=${key.session} eye=${key.eye} generation=${key.generation} source=${key.source} " +
            "n=${s.n} linear=${s.linear} quadratic=${s.quadratic} limited=${s.limited} clampedZero=${s.clampedZero} soft=${s.soft} " +
            "midFrameId=${s.midFrame} latestFrameId=${s.latestFrame} midFunctionalNs=${s.midFunctional} latestFunctionalNs=${s.latestFunctional} " +
            names.indices.joinToString(" ") { "${names[it]}=${s.metric(it)}" } + " lastDeltaVelocityXYZ=${s.deltaVelocity}")
    }

    private val names = arrayOf("deltaCaptureMs", "deltaSubmitMs", "deltaCallbackMs", "deltaFunctionalMs", "deltaPublicationMs", "R",
        "speedFunctionalWorldPerSec", "speedCaptureWorldPerSec", "deltaVelocityWorldPerSec", "publicationUncertaintyMs",
        "horizonRequestedMs", "extrapRequestedMs", "extrapEffectiveMs", "capMs", "clockDurationResidualMs", "clockBridgeUncertaintyMs")
    private class Stats {
        val sums = DoubleArray(16); val mins = DoubleArray(16) { Double.POSITIVE_INFINITY }
        val maxs = DoubleArray(16) { Double.NEGATIVE_INFINITY }
        var n = 0L; var linear = 0L; var quadratic = 0L; var limited = 0L; var clampedZero = 0L; var soft = 0L
        var midFrame = 0L; var latestFrame = 0L; var midFunctional = 0L; var latestFunctional = 0L
        var deltaVelocity = ""; var dirty = false
        fun add(i: Int, value: Double) { sums[i] += value; mins[i] = minOf(mins[i], value); maxs[i] = maxOf(maxs[i], value) }
        fun metric(i: Int) = "(mean=${sums[i]/n},min=${mins[i]},max=${maxs[i]})"
    }
}
