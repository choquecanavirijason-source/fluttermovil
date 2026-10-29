package com.example.test_face.render

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.VertexBuffer
import java.io.BufferedWriter
import java.io.File
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Observes source-buffer reuse, NOT GPU completion or presentation. No functional decisions. */
internal object BufferLifetimeTelemetry {
    private const val TAG = "BufferLifetime"
    private val ids = AtomicLong()
    private val mainCallbacks by lazy(LazyThreadSafetyMode.PUBLICATION) { Handler(Looper.getMainLooper()) }
    @Volatile private var enabled = false
    @Volatile private var epoch = 0L
    @Volatile private var directory: File? = null
    @Volatile private var active: Capture? = null
    private var startedEpoch = 0L // I/O worker only
    private var workerStarted = false
    private val draining = ArrayList<Capture>() // I/O worker only; max 4

    fun nextId(): Long = ids.incrementAndGet()

    @Synchronized fun configure(context: Context, requested: Boolean) {
        if (enabled == requested) return
        if (requested) {
            val root = context.getExternalFilesDir(null) ?: run {
                Log.e(TAG, "No external app directory; capture unavailable")
                return
            }
            directory = File(root, "buffer_lifetime")
            epoch++
        }
        enabled = requested
        if (!requested) active?.state?.accepting = false
        if (requested && !workerStarted) {
            workerStarted = true
            // Process-lifetime diagnostic I/O worker; never receives native callbacks.
            Executors.newSingleThreadScheduledExecutor { r ->
                Thread(r, "buffer-lifetime-io").apply { isDaemon = true }
            }.scheduleWithFixedDelay({ tick() }, 0, 250, TimeUnit.MILLISECONDS)
        }
    }

    class Binding(
        val capture: Capture, val a: FloatBuffer?, val b: FloatBuffer?, val tangents: FloatBuffer?,
        renderer: Long, eye: Int, val model: Long,
    ) {
        val positionA = BufferLifetimeState.Buffer(nextId(), renderer, eye, model, "POSITION_A")
        val positionB = BufferLifetimeState.Buffer(nextId(), renderer, eye, model, "POSITION_B")
        val tangent = BufferLifetimeState.Buffer(nextId(), renderer, eye, model, "TANGENTS")
        fun matches(c: Capture, modelId: Long, target: FloatBuffer, tangentTarget: FloatBuffer): Boolean =
            capture === c && model == modelId && (a === target || b === target) && tangents === tangentTarget
        fun retire(tracking: Long) {
            capture.state.retire(positionA, tracking)
            capture.state.retire(positionB, tracking)
            capture.state.retire(tangent, tracking)
        }
        fun boundary(tracking: Long) {
            capture.state.boundary(positionA, tracking)
            capture.state.boundary(positionB, tracking)
            capture.state.boundary(tangent, tracking)
        }
    }

    class Write(val binding: Binding, val position: BufferLifetimeState.Buffer, val tracking: Long) {
        private val positionSubmissions = position.submissions.get()
        private val tangentSubmissions = binding.tangent.submissions.get()
        init {
            binding.capture.state.writeStart(position, tracking)
            binding.capture.state.writeStart(binding.tangent, tracking)
        }
        fun end(success: Boolean) {
            binding.capture.state.writeEnd(position, tracking, success, positionSubmissions)
            binding.capture.state.writeEnd(binding.tangent, tracking, success, tangentSubmissions)
            if (!success) finish()
        }
        fun finish() { binding.capture.state.finishWrite() }
        fun upload(vb: VertexBuffer, engine: Engine, index: Int, source: FloatBuffer, count: Int) {
            val buffer = if (index == 0) position else binding.tangent
            val upload = binding.capture.state.submit(buffer, tracking)
            if (upload == null) {
                vb.setBufferAt(engine, index, source, 0, count)
                return
            }
            try {
                vb.setBufferAt(engine, index, source, 0, count, mainCallbacks, upload)
                upload.returned()
            } catch (e: Exception) {
                upload.failed()
                throw e // Same existing renderer exception handler; never retry an upload.
            }
        }
    }

    fun begin(slot: EyeModelSlot, renderer: Long, eye: Int, model: Long,
        target: FloatBuffer, tangentTarget: FloatBuffer): Write? {
        val capture = active ?: return null
        if (!enabled || !capture.state.isOpen()) return null
        if (model != slot.bufferModelGeneration.get()) {
            capture.state.omittedWrites.incrementAndGet()
            return null
        }
        var binding = slot.bufferTraceBinding
        if (binding == null || !binding.matches(capture, model, target, tangentTarget)) {
            // Bound metadata even under repeated model replacement.
            if (capture.bindings.incrementAndGet() > 256) {
                capture.state.omittedWrites.incrementAndGet()
                return null
            }
            val a = slot.positionBufferA
            val b = slot.positionBufferB
            if ((a !== target && b !== target) || slot.tangentBuffer !== tangentTarget ||
                model != slot.bufferModelGeneration.get()) {
                capture.state.omittedWrites.incrementAndGet()
                return null
            }
            binding = Binding(capture, a, b, tangentTarget, renderer, eye, model)
            slot.bufferTraceBinding = binding
        }
        if (slot.bufferModelGeneration.get() != model) {
            binding.retire(slot.bufferTrackingGeneration.get())
            capture.state.omittedWrites.incrementAndGet()
            return null
        }
        if (!capture.state.acquireWrite()) return null
        return Write(binding, if (binding.a === target) binding.positionA else binding.positionB,
            slot.bufferTrackingGeneration.get())
    }

    class Capture(val id: Long, dir: File) {
        val state = BufferLifetimeState(id, SystemClock.elapsedRealtimeNanos(), SystemClock::elapsedRealtimeNanos)
        val bindings = AtomicLong()
        val file = File(dir, "buffer_lifetime_${System.currentTimeMillis()}_$id.csv")
        private var writer: BufferedWriter? = file.bufferedWriter().also {
            it.write("captureId,event,elapsedRealtimeNs,rendererId,eye,modelGeneration,trackingGeneration,bufferId,bufferKind,uploadId,pending,value\n")
        }
        private val durations = ArrayList<Long>() // worker only, at most totalUploadLimit
        private val returns = ArrayList<Long>()
        private var events = 0L
        var reported = false
        var ioFailed = false
        fun drain() {
            repeat(4096) {
                val e = state.poll() ?: return
                events++
                if (e.kind.startsWith("RELEASE_OBSERVED")) durations.add(e.value)
                if (e.kind == "RETURN") returns.add(e.value)
                writer?.apply {
                    write("$id,${e.kind},${e.ns},${e.buffer.rendererId},${e.buffer.eye},${e.buffer.modelGeneration},${e.trackingGeneration},${e.buffer.id},${e.buffer.kind},${e.uploadId},${e.pending},${e.value}\n")
                }
            }
        }
        fun report(final: Boolean) {
            val sorted = durations.sorted()
            val sortedReturns = returns.sorted()
            fun percentile(values: List<Long>, p: Double): Double = if (values.isEmpty()) Double.NaN else
                values[((values.size - 1) * p).toInt()] / 1_000_000.0
            Log.i(TAG, "${if (final) "FINAL" else "SNAPSHOT"} captureId=$id events=$events " +
                "callbacks=${durations.size} callbackMs_p50=${percentile(sorted, .50)} " +
                "p95=${percentile(sorted, .95)} p99=${percentile(sorted, .99)} " +
                "javaObservedMs_p50=${percentile(sortedReturns, .50)} " +
                "java_p95=${percentile(sortedReturns, .95)} java_p99=${percentile(sortedReturns, .99)} " +
                "potentialWriteWindows=${state.potentialWrites.get()} submitDuringWrite=${state.racedWrites.get()} " +
                "pending=${state.pending.get()} peakPending=${state.peakPending.get()} " +
                "exceptions=${state.failures.get()} lateCallbacks=${state.lateCallbacks.get()} " +
                "writesInFlight=${state.writesInFlight.get()} " +
                "droppedEvents=${state.dropped.get()} omittedUploads=${state.omittedUploads.get()} " +
                "omittedWrites=${state.omittedWrites.get()} ioFailed=$ioFailed file=${file.absolutePath} " +
                "meaning=potential_overlap_not_corruption callback_includes_main_dispatch")
            writer?.flush()
            if (final) { state.finalized = true; writer?.close(); writer = null }
        }
        fun failIo(e: Exception) {
            ioFailed = true
            runCatching { writer?.close() }
            writer = null
            state.accepting = false
            Log.e(TAG, "captureId=$id I/O failed; CSV incomplete", e)
        }
    }

    private fun tick() {
        try {
            val now = SystemClock.elapsedRealtimeNanos()
            val iterator = draining.iterator()
            while (iterator.hasNext()) {
                val c = iterator.next()
                try {
                    if (now >= c.state.endNs) c.state.accepting = false
                    c.drain()
                    if (!c.state.accepting) {
                        if (active === c) active = null
                        if (c.state.pending.get() == 0 && c.state.writesInFlight.get() == 0 && c.state.empty()) {
                            c.report(true)
                            iterator.remove()
                        } else if (!c.reported && now >= c.state.endNs + 5_000_000_000L) {
                            c.report(false)
                            c.reported = true // Keep bounded state/writer alive for late callbacks.
                        }
                    }
                } catch (e: Exception) { c.failIo(e) }
            }
            if (enabled && epoch != startedEpoch && active == null) {
                startedEpoch = epoch
                if (draining.size >= 4) {
                    Log.w(TAG, "Capture refused: four previous captures still draining; re-arm later")
                    return
                }
                val dir = directory ?: return
                check(dir.isDirectory || dir.mkdirs()) { "Cannot create buffer lifetime directory" }
                val c = Capture(epoch, dir)
                draining.add(c)
                active = c
                Log.i(TAG, "START captureId=${c.id} durationMs=15000 file=${c.file.absolutePath}")
            }
        } catch (e: Exception) { Log.e(TAG, "Diagnostic worker failure", e) }
    }
}
