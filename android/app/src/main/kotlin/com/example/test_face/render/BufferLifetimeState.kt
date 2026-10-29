package com.example.test_face.render

import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/** Android-free diagnostic state. Never gates a functional write or upload. */
internal class BufferLifetimeState(
    val id: Long,
    val startNs: Long,
    private val clock: () -> Long,
    private val durationNs: Long = 15_000_000_000L,
    private val queueLimit: Int = 2048,
    private val uploadLimit: Int = 256,
    private val totalUploadLimit: Int = 8192,
    private val totalEventLimit: Int = 32768,
) {
    data class Event(
        val kind: String, val ns: Long, val buffer: Buffer,
        val trackingGeneration: Long, val uploadId: Long = 0,
        val pending: Int = 0, val value: Long = 0,
    )

    class Buffer(
        val id: Long, val rendererId: Long, val eye: Int, val modelGeneration: Long,
        val kind: String,
    ) {
        val pending = AtomicInteger()
        val writing = AtomicInteger()
        val retired = AtomicBoolean()
        val trackingGeneration = AtomicLong()
        val submissions = AtomicLong()
        val closedBoundaryLogged = AtomicBoolean()
    }

    private val events = ConcurrentLinkedQueue<Event>()
    private val queued = AtomicInteger()
    private val uploadSequence = AtomicLong()
    private val eventSequence = AtomicLong()
    val dropped = AtomicLong()
    val omittedUploads = AtomicLong()
    val omittedWrites = AtomicLong()
    val pending = AtomicInteger()
    val potentialWrites = AtomicLong()
    val racedWrites = AtomicLong()
    val lateCallbacks = AtomicLong()
    val failures = AtomicLong()
    val peakPending = AtomicInteger()
    val writesInFlight = AtomicInteger()
    @Volatile var accepting = true
    @Volatile var finalized = false
    val endNs: Long get() = startNs + durationNs

    fun isOpen(): Boolean = accepting && clock() < endNs

    fun acquireWrite(): Boolean {
        writesInFlight.incrementAndGet()
        if (isOpen()) return true
        writesInFlight.decrementAndGet()
        return false
    }

    fun finishWrite() { writesInFlight.decrementAndGet() }

    fun writeStart(buffer: Buffer, tracking: Long) {
        buffer.trackingGeneration.accumulateAndGet(tracking, ::maxOf)
        buffer.writing.incrementAndGet()
        val outstanding = buffer.pending.get()
        if (outstanding > 0) potentialWrites.incrementAndGet()
        emit(Event("WRITE_BEGIN", clock(), buffer, tracking, pending = outstanding))
    }

    fun writeEnd(buffer: Buffer, tracking: Long, success: Boolean, submissionsBefore: Long) {
        val during = buffer.submissions.get() - submissionsBefore
        if (during > 0) racedWrites.incrementAndGet()
        buffer.writing.decrementAndGet()
        emit(Event(if (success) "WRITE_END" else "WRITE_ABORT_OR_SKIP", clock(), buffer,
            tracking, pending = buffer.pending.get(), value = during))
    }

    fun submit(buffer: Buffer, tracking: Long): Upload? {
        // Capacity reservation only; failure drops diagnostics, never the upload itself.
        val sequence = uploadSequence.incrementAndGet()
        if (sequence > totalUploadLimit) {
            omittedUploads.incrementAndGet()
            return null
        }
        if (pending.getAndIncrement() >= uploadLimit) {
            pending.decrementAndGet()
            omittedUploads.incrementAndGet()
            return null
        }
        val count = buffer.pending.incrementAndGet()
        buffer.submissions.incrementAndGet()
        peakPending.accumulateAndGet(pending.get(), ::maxOf)
        val now = clock()
        emit(Event("SUBMIT", now, buffer, tracking, sequence, count,
            buffer.writing.get().toLong()))
        return Upload(buffer, tracking, sequence, now)
    }

    inner class Upload(
        private val buffer: Buffer, private val tracking: Long,
        private val sequence: Long, private val submittedNs: Long,
    ) : Runnable {
        private val completed = AtomicBoolean()
        private val failed = AtomicBoolean()
        fun returned() {
            val now = clock()
            emit(Event("RETURN", now, buffer, tracking, sequence, value = now - submittedNs))
        }
        fun failed() {
            failed.set(true)
            failures.incrementAndGet()
            // Do not assume that an exceptional native call cannot retain a buffer.
            emit(Event("EXCEPTION_UNRESOLVED", clock(), buffer, tracking, sequence))
        }
        override fun run() {
            if (!completed.compareAndSet(false, true)) return
            val now = clock()
            val late = !accepting || now >= endNs || buffer.retired.get() ||
                tracking != buffer.trackingGeneration.get() || failed.get()
            if (late) lateCallbacks.incrementAndGet()
            val count = buffer.pending.decrementAndGet()
            emit(Event(if (late) "RELEASE_OBSERVED_LATE" else "RELEASE_OBSERVED",
                now, buffer, tracking, sequence, count, now - submittedNs))
            pending.decrementAndGet() // Publish the event before allowing capture finalization.
        }
    }

    fun retire(buffer: Buffer, tracking: Long) {
        if (!buffer.retired.compareAndSet(false, true) || finalized) return
        emit(Event("MODEL_RETIRED", clock(), buffer, tracking, pending = buffer.pending.get()))
    }

    fun boundary(buffer: Buffer, tracking: Long) {
        buffer.trackingGeneration.accumulateAndGet(tracking, ::maxOf)
        if (finalized || (!isOpen() && !buffer.closedBoundaryLogged.compareAndSet(false, true))) return
        emit(Event("TRACKING_BOUNDARY", clock(), buffer, tracking, pending = buffer.pending.get()))
    }

    private fun emit(event: Event) {
        if (finalized) return
        if (eventSequence.incrementAndGet() > totalEventLimit) {
            dropped.incrementAndGet()
            return
        }
        if (queued.getAndIncrement() >= queueLimit) {
            queued.decrementAndGet()
            dropped.incrementAndGet()
        } else events.offer(event)
    }

    fun poll(): Event? = events.poll()?.also { queued.decrementAndGet() }
    fun empty(): Boolean = queued.get() == 0
}
