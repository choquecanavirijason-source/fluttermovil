package com.example.test_face.render

import android.content.Context
import android.os.SystemClock
import android.util.Log
import com.example.test_face.TrackingTimingTelemetry
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
import java.io.BufferedWriter
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** Independent 15-second diagnostic capture. Single render producer, single I/O worker.
 * No pose from this recorder is ever used as tracking input. All clocks stay labelled.
 */
object PoseTrajectoryTelemetry {
    private const val DURATION_NS = 15_000_000_000L
    private const val MAX_RECORDS = 4096L
    @Volatile private var active: Capture? = null
    @Volatile private var enabled = false
    @Volatile private var epoch = 0L
    private var startedEpoch = 0L // worker only
    private var directory: File? = null
    private var workerStarted = false
    private var executor: ScheduledExecutorService? = null

    val current: Capture?
        get() = active?.takeIf { it.accepting && SystemClock.elapsedRealtimeNanos() < it.endNs }

    /** Called by PerfFlags.load, not by render. Re-arm requires off -> on. */
    @Synchronized fun configure(context: Context, requested: Boolean) {
        if (requested == enabled) return
        if (requested) {
            val root = context.getExternalFilesDir(null)
            if (root == null) { Log.e("PoseTrajectory", "No external app directory; capture unavailable"); return }
            directory = File(root, "pose_trajectories")
            epoch++
        }
        enabled = requested
        if (!requested) active?.accepting = false
        if (!workerStarted && requested) {
            workerStarted = true
            val service = Executors.newSingleThreadScheduledExecutor { r ->
                Thread(r, "pose-trajectory-io").apply { isDaemon = true }
            }
            executor = service
            service.scheduleWithFixedDelay({ tick() }, 0, 50, TimeUnit.MILLISECONDS)
        }
    }

    private fun tick() {
        try {
            val c = active
            if (c != null) {
                if (!enabled || c.id != epoch || SystemClock.elapsedRealtimeNanos() >= c.endNs || c.attempted >= MAX_RECORDS)
                    c.accepting = false
                c.drain()
                if (!c.accepting && !c.inOffer && c.empty()) {
                    c.finish()
                    active = null
                }
            }
            if (active == null && enabled && epoch != startedEpoch) {
                startedEpoch = epoch
                val dir = directory ?: return
                check(dir.isDirectory || dir.mkdirs()) { "Cannot create trajectory directory" }
                val cNew = Capture(startedEpoch, File(dir, "pose_trajectory_${System.currentTimeMillis()}_$startedEpoch.csv"))
                active = cNew // publish only after allocation/header on worker
                Log.i("PoseTrajectory", "START captureId=${cNew.id} durationMs=15000 file=${cNew.file.absolutePath}")
            }
        } catch (e: Exception) {
            val c = active
            c?.accepting = false
            runCatching { c?.writer?.close() }
            active = null
            startedEpoch = epoch
            Log.e("PoseTrajectory", "Capture failed; partial file is not complete", e)
        } finally {
            stopIdleWorker()
        }
    }

    /** Lifecycle lock is never acquired by offer/current or a render hook. */
    @Synchronized private fun stopIdleWorker() {
        if (active == null && (!enabled || startedEpoch == epoch)) {
            executor?.shutdown()
            executor = null
            workerStarted = false
        }
    }

    /** One immutable pose snapshot per processed eye, allocated on compute only. */
    class Processed(
        val captureId: Long,
        val context: TrackingTimingTelemetry.Context?,
        raw: EyeTransform,
        filtered: EyeTransform,
        val rawElapsedNs: Long,
        val filteredElapsedNs: Long,
        val recovering: Boolean,
    ) {
        val poses = FloatArray(14)
        val openness = raw.normalizedOpenness
        val lidTrusted = raw.lidShapeTrusted
        @Volatile var publicationBeforeNs = 0L
            private set
        @Volatile var publicationAfterNs = 0L
            private set
        init { put(poses, 0, raw); put(poses, 7, filtered) }
        fun beforePush() { publicationBeforeNs = SystemClock.elapsedRealtimeNanos() }
        fun afterPush() { publicationAfterNs = SystemClock.elapsedRealtimeNanos() }
    }

    private class Row {
        val poses = FloatArray(42) // input, euro, predicted, blend, follower, final; each pxyz/qxyzw
        var event = 0L; var evaluation = 0L; var frameTime = 0L; var renderElapsed = 0L
        var source = 0; var eye = 0; var generation = 0; var functional = 0L
        var flags = 0; var lost = 0; var openness = Float.NaN; var closedAmount = Float.NaN
        var availableStages = 0
        var processed: Processed? = null
        var context: TrackingTimingTelemetry.Context? = null
    }

    class Capture internal constructor(val id: Long, val file: File) {
        private val ring = Array(256) { Row() }
        @Volatile private var written = 0L
        @Volatile private var read = 0L
        @Volatile var attempted = 0L
            private set
        @Volatile private var dropped = 0L
        @Volatile internal var inOffer = false
        @Volatile internal var accepting = true
        private var rows = 0L
        private val previousSource = IntArray(2)
        private val previousGeneration = IntArray(2) { -1 }
        internal val writer: BufferedWriter = file.bufferedWriter(Charsets.UTF_8, 64 * 1024)
        val endNs = SystemClock.elapsedRealtimeNanos() + DURATION_NS

        init {
            writer.appendLine("#schema=pose_trajectory_v1 durationMs=15000 clocks=sensor_source,elapsed,mp_uptime_ms,functional_nano,choreographer; poses=world_position_and_quaternion; evaluation_is_not_presentation")
            writer.append("captureId,eventSeq,renderEvaluationId,frameTimeNanos,renderElapsedNs,source,sessionId,frameId,eye,generation,functionalNs,sensorNs,sensorSource,mpTimestampMs,submitElapsedNs,callbackElapsedNs,rawElapsedNs,euroElapsedNs,publicationBeforeNs,publicationAfterNs,flags,lostFrames,normalizedOpenness,closedAmount")
            for (stage in arrayOf("input", "euro", "predicted", "blend", "follower", "final"))
                for (component in arrayOf("px", "py", "pz", "qx", "qy", "qz", "qw")) writer.append(",$stage" + "_$component")
            writer.newLine()
        }

        /** Render only. Copies primitives into a preallocated slot; never waits or writes I/O.
         * flags: 1 missing context, 2 missing processed, 4 history changed within evaluation,
         * 8 tracking lost, 16 history/source boundary, 32 recovery, 64 untrusted lid,
         * 128 no node, 256 hidden, 512 nonfinite, 1024 missing render stages/publication.
         */
        internal fun offer(
            source: Int, eye: Int, generation: Int, functionalNs: Long, evaluation: Long, frameTime: Long,
            processed: Processed?, fallbackContext: TrackingTimingTelemetry.Context?,
            predicted: EyeTransform?, blended: EyeTransform?, follower: PoseFollower?,
            finalPosition: Float3?, finalRotation: Quaternion?, lostFrames: Int, extraFlags: Int,
        ) {
            if (eye !in 0..1) return
            inOffer = true
            try {
                if (!accepting || SystemClock.elapsedRealtimeNanos() >= endNs || attempted >= MAX_RECORDS) return
                val seq = ++attempted
                val w = written
                if (w - read >= ring.size) { dropped++; return }
                val r = ring[(w % ring.size).toInt()]
                r.event = seq; r.evaluation = evaluation; r.frameTime = frameTime
                r.renderElapsed = SystemClock.elapsedRealtimeNanos()
                r.source = source; r.eye = eye; r.generation = generation; r.functional = functionalNs
                r.processed = processed?.takeIf { it.captureId == id }
                r.context = processed?.context ?: fallbackContext
                r.flags = extraFlags or (if (lostFrames > 0) 8 else 0)
                r.lost = lostFrames
                if (r.context == null) r.flags = r.flags or 1
                if (previousSource[eye] != source || previousGeneration[eye] != generation) r.flags = r.flags or 16
                previousSource[eye] = source; previousGeneration[eye] = generation
                r.poses.fill(Float.NaN)
                r.availableStages = 0
                val p = r.processed
                r.openness = p?.openness ?: Float.NaN
                r.closedAmount = follower?.closedAmount ?: Float.NaN
                if (p == null) r.flags = r.flags or 2 else {
                    for (i in 0..13) r.poses[i] = p.poses[i]
                    r.availableStages = r.availableStages or 3
                    if (p.recovering) r.flags = r.flags or 32
                    if (!p.lidTrusted) r.flags = r.flags or 64
                    if (p.publicationBeforeNs == 0L || p.publicationAfterNs == 0L) r.flags = r.flags or 1024
                }
                if (predicted != null) { put(r.poses, 14, predicted); r.availableStages = r.availableStages or 4 }
                if (blended != null) { put(r.poses, 21, blended); r.availableStages = r.availableStages or 8 }
                if (follower != null) {
                    r.availableStages = r.availableStages or 16
                    r.poses[28] = follower.posX; r.poses[29] = follower.posY; r.poses[30] = follower.posZ
                    r.poses[31] = follower.rotX; r.poses[32] = follower.rotY; r.poses[33] = follower.rotZ; r.poses[34] = follower.rotW
                }
                if (finalPosition != null && finalRotation != null) {
                    r.availableStages = r.availableStages or 32
                    r.poses[35] = finalPosition.x; r.poses[36] = finalPosition.y; r.poses[37] = finalPosition.z
                    r.poses[38] = finalRotation.x; r.poses[39] = finalRotation.y; r.poses[40] = finalRotation.z; r.poses[41] = finalRotation.w
                }
                if (predicted == null || blended == null || follower == null || finalPosition == null) r.flags = r.flags or 1024
                written = w + 1
            } finally { inOffer = false }
        }

        internal fun empty() = read == written
        internal fun drain() {
            while (read < written) {
                val rIndex = read
                val r = ring[(rIndex % ring.size).toInt()]
                val p = r.processed; val c = r.context
                for (i in r.poses.indices) if (r.availableStages and (1 shl (i / 7)) != 0 && !r.poses[i].isFinite()) {
                    r.flags = r.flags or 512
                    break
                }
                writer.append("$id,${r.event},${r.evaluation},${r.frameTime},${r.renderElapsed},${r.source},${c?.sessionId ?: -1},${c?.frameId ?: -1},${r.eye},${r.generation},${r.functional},${c?.sensorTimestampNs ?: 0},${c?.sensorSource ?: "UNKNOWN"},${c?.mpTimestampMs ?: 0},${c?.submitElapsedNs ?: 0},${c?.callbackElapsedNs ?: 0},${p?.rawElapsedNs ?: 0},${p?.filteredElapsedNs ?: 0},${p?.publicationBeforeNs ?: 0},${p?.publicationAfterNs ?: 0},${r.flags},${r.lost},${r.openness},${r.closedAmount}")
                for (v in r.poses) writer.append(',').append(v.toString())
                writer.newLine()
                r.processed = null; r.context = null
                rows++
                read = rIndex + 1
            }
        }
        internal fun finish() {
            val reason = if (attempted >= MAX_RECORDS) "record_limit" else if (SystemClock.elapsedRealtimeNanos() >= endNs) "duration" else "disabled_or_rearmed"
            writer.appendLine("#END captureId=$id reason=$reason attempted=$attempted rows=$rows queueDropped=$dropped")
            writer.close()
            Log.i("PoseTrajectory", "END captureId=$id reason=$reason rows=$rows queueDropped=$dropped file=${file.absolutePath}; toggle off/on to rearm")
        }
    }

    private fun put(out: FloatArray, offset: Int, pose: EyeTransform) {
        out[offset] = pose.position.x; out[offset+1] = pose.position.y; out[offset+2] = pose.position.z
        out[offset+3] = pose.rotation.x; out[offset+4] = pose.rotation.y
        out[offset+5] = pose.rotation.z; out[offset+6] = pose.rotation.w
    }
}
