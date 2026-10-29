package com.example.test_face

import android.os.SystemClock
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Observational only. Never called by the render thread; never retains images.
 * Records (including completed/ambiguous keys) survive 10s, up to 128 entries.
 * Missing/evicted keys are never matched to the latest frame.
 */
object TrackingTimingTelemetry {
    /** Immutable hand-off; no image or reference to the mutable correlation ring. */
    data class Context(
        val sessionId: Long,
        val frameId: Long,
        val sensorTimestampNs: Long,
        val sensorSource: String,
        val submitElapsedNs: Long,
        val mpTimestampMs: Long,
        val callbackElapsedNs: Long,
    )

    class Frame(
        val sessionId: Long,
        val frameId: Long,
        val sensorNs: Long,
        val source: String,
        val analyzerNs: Long,
    ) {
        var submitNs = 0L
        var mpMs = 0L
        var callbackNs = 0L
        var ambiguous = false
        var closed = false
    }

    private val guard = Any()
    private val records = arrayOfNulls<Frame>(128)
    private var cursor = 0
    private val counts = LongArray(10)
    private val names = arrayOf("received", "submitted", "matched", "unmatched", "ambiguous", "late_closed", "error_unattributed", "not_submitted", "evicted_pending", "invalid_age")
    private val metrics = Array(5) { Histogram() }
    private val metricNames = arrayOf("age_analyzer", "age_submit", "age_callback", "prepare", "submit_callback")
    private var last: Frame? = null
    private var dirty = false

    init {
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "timestamp-trace").apply { isDaemon = true }
        }.scheduleWithFixedDelay({ report() }, 5, 5, TimeUnit.SECONDS)
    }

    fun begin(sessionId: Long, frameId: Long, sensorNs: Long, source: String, analyzerNs: Long): Frame =
        synchronized(guard) {
            // Allocate the phase-2 queue/worker here, never in Choreographer.
            if (PerfFlags.config.timestampTrace && com.example.test_face.render.PoseTraceTelemetry.sink == null) {
                com.example.test_face.render.PoseTraceTelemetry.prepare()
            }
            counts[0]++
            dirty = true
            Frame(sessionId, frameId, sensorNs, source, analyzerNs).also {
                age(it, analyzerNs, 0)
            }
        }

    fun submit(frame: Frame, mpMs: Long) = synchronized(guard) {
        val now = SystemClock.elapsedRealtimeNanos()
        frame.submitNs = now
        frame.mpMs = mpMs
        for (i in records.indices) {
            val old = records[i] ?: continue
            if (now - old.submitNs > 10_000_000_000L) {
                if (old.callbackNs == 0L) counts[8]++
                records[i] = null
            } else if (old.sessionId == frame.sessionId && old.mpMs == mpMs) {
                old.ambiguous = true
                frame.ambiguous = true
            }
        }
        records[cursor]?.let { if (it.callbackNs == 0L) counts[8]++ }
        records[cursor] = frame
        cursor = (cursor + 1) % records.size
        counts[1]++
        dirty = true
        age(frame, now, 1)
        metrics[3].add(now - frame.analyzerNs)
    }

    fun callback(sessionId: Long, mpMs: Long, now: Long): Context? = synchronized(guard) {
        var match: Frame? = null
        var duplicate = false
        for (record in records) {
            if (record != null && record.sessionId == sessionId && record.mpMs == mpMs) {
                if (match != null || record.ambiguous) duplicate = true
                match = record
            }
        }
        dirty = true
        val frame = match
        when {
            duplicate -> { counts[4]++; null }
            frame == null || frame.callbackNs != 0L || now - frame.submitNs > 10_000_000_000L -> { counts[3]++; null }
            else -> {
                frame.callbackNs = now
                if (frame.closed) counts[5]++
                counts[2]++
                age(frame, now, 2)
                metrics[4].add(now - frame.submitNs)
                last = frame
                if (frame.closed || now < frame.submitNs) null else Context(
                    frame.sessionId, frame.frameId, frame.sensorNs, frame.source,
                    frame.submitNs, frame.mpMs, now,
                )
            }
        }
    }

    fun notSubmitted(frame: Frame) = synchronized(guard) {
        if (frame.submitNs == 0L) counts[7]++
        dirty = true
    }

    fun error() = synchronized(guard) { counts[6]++; dirty = true }

    fun closeSession(sessionId: Long) = synchronized(guard) {
        for (record in records) if (record?.sessionId == sessionId) record.closed = true
    }

    private fun age(frame: Frame, now: Long, metric: Int) {
        if (frame.source != "REALTIME" || frame.sensorNs <= 0L) return
        val delta = now - frame.sensorNs
        if (delta < 0L) counts[9]++ else metrics[metric].add(delta)
    }

    private fun report() {
        val message = synchronized(guard) {
            if (!dirty) return
            dirty = false
            buildString {
                append("TIMESTAMP_TRACE cumulative ")
                for (i in names.indices) append("${names[i]}=${counts[i]} ")
                for (i in metrics.indices) append("${metricNames[i]}=${metrics[i].summary()} ")
                last?.let { f ->
                    append("last=(session=${f.sessionId},frame=${f.frameId},source=${f.source},sensor_ns=${f.sensorNs},analyzer_elapsed_ns=${f.analyzerNs},submit_elapsed_ns=${f.submitNs},mp_ms=${f.mpMs},callback_elapsed_ns=${f.callbackNs})")
                }
            }
        }
        Log.i("TimestampTrace", message)
    }

    /** Fixed 1ms bins; final bin is overflow (>2000ms), never a clipped value. */
    private class Histogram {
        private val bins = LongArray(2002)
        private var n = 0L
        fun add(ns: Long) {
            if (ns < 0L) return
            val ms = ns / 1_000_000L
            bins[if (ms > 2000L) 2001 else ms.toInt()]++
            n++
        }
        private fun percentile(percent: Int): String {
            val target = (n * percent + 99) / 100
            var total = 0L
            for (i in bins.indices) {
                total += bins[i]
                if (total >= target) return if (i == 2001) ">2000ms" else "[$i,${i + 1})ms"
            }
            return "n/d"
        }
        fun summary(): String = if (n == 0L) "n/d(n=0)" else
            "(n=$n,p50=${percentile(50)},p95=${percentile(95)},p99=${percentile(99)},overflow=${bins[2001]})"
    }
}
