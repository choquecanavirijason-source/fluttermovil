package com.example.test_face.render

import android.util.Log
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.sqrt

/** Diagnostic differences, NOT physical tracking errors. One producer (main/render),
 * one worker. No locks, allocations, quaternion math or statistics in offer().
 * Full camera identity is deliberately unavailable; source/generation/sampleNs are local.
 */
object PoseTraceTelemetry {
    @Volatile var sink: Sink? = null
        private set

    /** Called only by the analyzer while timestamp_trace is enabled. */
    @Synchronized fun prepare() {
        if (sink == null) sink = Sink()
    }

    private class Event {
        val timing = PredictorTimingTelemetry.Event()
        var kind = 0; var eye = 0; var source = 0; var generation = 0
        var sampleNs = 0L; var oldSampleNs = 0L; var nowNs = 0L; var horizonNs = 0L
        var cap = 0f; var soft = false; var span = 0f
        var a: EyeTransform? = null; var b: EyeTransform? = null; var c: EyeTransform? = null
        var ta = 0L; var tb = 0L; var tc = 0L
        var from: EyeTransform? = null; var to: EyeTransform? = null
        var px = 0f; var py = 0f; var pz = 0f
        var qx = 0f; var qy = 0f; var qz = 0f; var qw = 1f
    }

    class Sink internal constructor() {
        private val ring = Array(512) { Event() }
        @Volatile private var written = 0L
        @Volatile private var read = 0L
        @Volatile private var dropped = 0L
        private val stats = Array(6) { Stats() }
        private var ticks = 0
        private var dirty = false
        @Volatile private var timingMissing = 0L
        @Volatile private var timingDropped = 0L
        @Volatile private var timingObserved = false

        init {
            Executors.newSingleThreadScheduledExecutor { r ->
                Thread(r, "pose-trace").apply { isDaemon = true }
            }.scheduleWithFixedDelay({ drain() }, 100, 100, TimeUnit.MILLISECONDS)
        }

        /** kind: 0=forecast(new-old), 1=blend(output-prediction), 2=follower(target-output).
         * Forecast history is from the previous CONSUMED sample; current prediction is
         * the actual functional output before blend. Same now/horizon/cap/soft for both.
         */
        fun offer(
            kind: Int, eye: Int, source: Int, generation: Int, sampleNs: Long,
            nowNs: Long, span: Float, from: EyeTransform?, to: EyeTransform,
            a: EyeTransform? = null, b: EyeTransform? = null, c: EyeTransform? = null,
            ta: Long = 0L, tb: Long = 0L, tc: Long = 0L,
            horizonNs: Long = 0L, cap: Float = 0f, soft: Boolean = false,
            px: Float = 0f, py: Float = 0f, pz: Float = 0f,
            qx: Float = 0f, qy: Float = 0f, qz: Float = 0f, qw: Float = 1f,
        ) {
            if (eye !in 0..1) return
            val w = written
            if (w - read >= ring.size) { dropped++; return }
            val e = ring[(w % ring.size).toInt()]
            e.kind = kind; e.eye = eye; e.source = source; e.generation = generation
            e.sampleNs = sampleNs; e.oldSampleNs = tc; e.nowNs = nowNs; e.span = span
            e.from = from; e.to = to; e.a = a; e.b = b; e.c = c
            e.ta = ta; e.tb = tb; e.tc = tc
            e.horizonNs = horizonNs; e.cap = cap; e.soft = soft
            e.px = px; e.py = py; e.pz = pz
            e.qx = qx; e.qy = qy; e.qz = qz; e.qw = qw
            written = w + 1 // release the complete slot
        }

        internal fun offerTiming(
            eye: Int, source: Int, generation: Int, mid: PredictorTimingTelemetry.Publication?,
            latest: PredictorTimingTelemetry.Publication?, midPose: EyeTransform, latestPose: EyeTransform,
            midFunctionalNs: Long, latestFunctionalNs: Long, mode: Int,
            horizonNs: Long, requestedNs: Float, capNs: Float, factor: Float, functionalDtNs: Float, soft: Boolean,
        ) {
            timingObserved = true
            if (mid == null || latest == null) { timingMissing++; return }
            val w = written
            if (w - read >= ring.size) { timingDropped++; return }
            val slot = ring[(w % ring.size).toInt()]
            slot.kind = 3
            val e = slot.timing
            e.eye = eye; e.source = source; e.generation = generation
            e.mid = mid; e.latest = latest; e.midPose = midPose; e.latestPose = latestPose
            e.midFunctionalNs = midFunctionalNs; e.latestFunctionalNs = latestFunctionalNs; e.mode = mode
            e.horizonNs = horizonNs; e.requestedNs = requestedNs; e.capNs = capNs
            e.factor = factor; e.functionalDtNs = functionalDtNs; e.soft = soft
            written = w + 1
        }

        private fun drain() {
            while (read < written) {
                val r = read
                val e = ring[(r % ring.size).toInt()]
                if (e.kind == 3) PredictorTimingTelemetry.consume(e.timing) else consume(e)
                e.a = null; e.b = null; e.c = null; e.from = null; e.to = null
                e.timing.clear()
                read = r + 1 // producer cannot reuse a slot before this release
                dirty = true
            }
            if (++ticks < 50) return
            ticks = 0
            if (timingObserved) PredictorTimingTelemetry.report(timingMissing, timingDropped)
            if (!dirty && dropped == 0L) return
            dirty = false
            for (eye in 0..1) for (kind in 0..2) {
                val label = when (kind) { 0 -> "forecast_same_time"; 1 -> "blend_applied"; else -> "follower_residual" }
                Log.i("PoseTrace", "POSE_TRACE diagnostic cumulative eye=$eye kind=$label sessionId=n/a frameId=n/a dropped=$dropped ${stats[eye * 3 + kind].summary()}")
            }
        }

        private fun consume(e: Event) {
            val to = e.to ?: return
            val from = when (e.kind) {
                0 -> shadow(e) ?: return
                1 -> e.from ?: return
                else -> EyeTransform(Float3(e.px, e.py, e.pz), Quaternion(e.qx, e.qy, e.qz, e.qw), to.scale)
            }
            val dp = to.position - from.position
            // Common WORLD axes, shortest quaternion arc; q and -q produce the same vector.
            val a = to.rotation; val b = from.rotation
            var x = -a.w * b.x + a.x * b.w - a.y * b.z + a.z * b.y
            var y = -a.w * b.y + a.x * b.z + a.y * b.w - a.z * b.x
            var z = -a.w * b.z - a.x * b.y + a.y * b.x + a.z * b.w
            var w = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
            val norm = sqrt(x*x + y*y + z*z + w*w)
            if (norm <= 1e-12f || !norm.isFinite()) return
            val inv = (if (w < 0f) -1f else 1f) / norm
            x *= inv; y *= inv; z *= inv; w *= inv
            val sinHalf = sqrt(x*x + y*y + z*z)
            val k = if (sinHalf > 1e-8f)
                Math.toDegrees(2.0 * kotlin.math.atan2(sinHalf.toDouble(), w.toDouble())).toFloat() / sinHalf
            else 114.59156f
            val span = e.span
            stats[e.eye * 3 + e.kind].add(e, dp, span, x*k, y*k, z*k)
        }

        /** Pure position/rotation evaluation of captured old history. NEVER calls sample,
         * predict or blend. Mirrors the current predictor; parity is checked separately.
         */
        private fun shadow(e: Event): EyeTransform? {
            val c = e.c ?: return null
            val b = e.b ?: return null
            val dt1 = (e.tc - e.tb).toFloat()
            if (dt1 <= 0f) return null
            val elapsed = (e.nowNs + e.horizonNs - e.tc).toFloat()
            val effective = when {
                elapsed <= 0f -> 0f
                elapsed <= e.cap -> elapsed
                !e.soft -> e.cap
                else -> e.cap + PoseInterpolator.SOFT_EXTRAPOLATION_TAIL_NANOS *
                    (1f - kotlin.math.exp(-(elapsed - e.cap) / PoseInterpolator.SOFT_EXTRAPOLATION_TAIL_NANOS))
            }
            val t = effective / dt1
            val a = e.a
            val dt0 = (e.tb - e.ta).toFloat()
            val p = if (a != null && dt0 > 0f) {
                val v0 = (b.position - a.position) * (1f / dt0)
                val v1 = (c.position - b.position) * (1f / dt1)
                val accel = (v1 - v0) * (1f / ((dt0 + dt1) * 0.5f))
                val ts = t * dt1
                val velocity = v1 * ts
                val acceleration = accel * (0.5f * ts * ts)
                val len = length(acceleration)
                val limit = length(velocity) * PoseInterpolator.ACCEL_TERM_MAX_RATIO
                c.position + velocity + if (len > limit && len > 1e-30f) acceleration * (limit / len) else acceleration
            } else b.position + (c.position - b.position) * (1f + t)
            val qa = b.rotation; val qb = c.rotation
            val dot = qa.x*qb.x + qa.y*qb.y + qa.z*qb.z + qa.w*qb.w
            val aligned = if (dot < 0f) Quaternion(-qb.x, -qb.y, -qb.z, -qb.w) else qb
            val factor = 1f + t
            val x = qa.x + (aligned.x - qa.x)*factor; val y = qa.y + (aligned.y - qa.y)*factor
            val z = qa.z + (aligned.z - qa.z)*factor; val w = qa.w + (aligned.w - qa.w)*factor
            val lenSq = x*x + y*y + z*z + w*w
            val q = if (lenSq <= 0f || !lenSq.isFinite()) { if (dot < 0f) aligned else qb }
                else { val inv = 1f/sqrt(lenSq); Quaternion(x*inv, y*inv, z*inv, w*inv) }
            return EyeTransform(p, q, c.scale)
        }
    }

    private fun length(p: Float3): Float = sqrt(p.x*p.x + p.y*p.y + p.z*p.z)

    private class Stats {
        var n = 0L; var invalid = 0L; var significantPairs = 0L
        var posReversals = 0L; var rotReversals = 0L
        var posSum = 0.0; var rotSum = 0.0; var posMax = 0f; var rotMax = 0f
        var lastPos = Float3(); var lastRot = Float3()
        var priorPos: Float3? = null; var priorRot: Float3? = null
        var source = 0; var generation = 0; var sample = 0L; var lastNs = 0L; var oldSample = 0L
        fun add(e: Event, dp: Float3, span: Float, rx: Float, ry: Float, rz: Float) {
            if (span <= 1e-6f || !span.isFinite()) { invalid++; return }
            val p = dp * (1f / span); val r = Float3(rx, ry, rz)
            val pm = length(p); val rm = length(r)
            if (!pm.isFinite() || !rm.isFinite()) { invalid++; return }
            val contiguous = source == e.source && generation == e.generation && e.nowNs - lastNs in 0L..250_000_000L
            if (!contiguous) { priorPos = null; priorRot = null }
            // Compare directions once per new sample, not each decaying vsync.
            // Fixed DIAGNOSTIC deadbands: 0.5% eye width and 0.1 degree; no filter change.
            if (e.sampleNs != sample || !contiguous) {
                if (pm > 0.005f) {
                    priorPos?.let { if (dot(p, it) < -0.5f * pm * length(it)) posReversals++ }
                    priorPos = p
                } else priorPos = null
                if (rm > 0.1f) {
                    priorRot?.let { if (dot(r, it) < -0.5f * rm * length(it)) rotReversals++ }
                    priorRot = r
                } else priorRot = null
                significantPairs++
            }
            source = e.source; generation = e.generation; sample = e.sampleNs; lastNs = e.nowNs; oldSample = e.oldSampleNs
            lastPos = p; lastRot = r
            n++; posSum += pm; rotSum += rm
            posMax = maxOf(posMax, pm); rotMax = maxOf(rotMax, rm)
        }
        fun summary() = "n=$n invalid=$invalid sample_events=$significantPairs source=$source generation=$generation sample_ns=$sample old_sample_ns=$oldSample " +
            "pos_spans(mean=${if(n>0) posSum/n else 0.0},max=$posMax,last_xyz=$lastPos,reversals=$posReversals) " +
            "rot_deg(mean=${if(n>0) rotSum/n else 0.0},max=$rotMax,last_xyz=$lastRot,reversals=$rotReversals)"
        private fun dot(a: Float3, b: Float3) = a.x*b.x + a.y*b.y + a.z*b.z
    }
}
