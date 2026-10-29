package com.example.test_face.render

/** Standalone JVM checks: no Android runtime, device, Gradle test dependencies or native buffers. */
fun main() {
    var now = 100L
    fun buffer(id: Long = 1) = BufferLifetimeState.Buffer(id, 10, 0, id, "TANGENTS")
    fun events(s: BufferLifetimeState): List<BufferLifetimeState.Event> = buildList {
        while (true) add(s.poll() ?: break)
    }

    val s = BufferLifetimeState(1, now, { now }, durationNs = 150)
    val old = buffer()
    check(s.acquireWrite())
    s.writeStart(old, 1)
    s.writeEnd(old, 1, true, 0)
    val u = checkNotNull(s.submit(old, 1))
    check(s.pending.get() == 1 && old.pending.get() == 1)
    s.finishWrite()
    s.writeStart(old, 1)
    s.writeEnd(old, 1, true, 1)
    check(s.potentialWrites.get() == 1L)
    now += 20
    u.returned()
    u.run()
    u.run() // Duplicate callbacks cannot free a later upload or go negative.
    check(s.pending.get() == 0 && old.pending.get() == 0)
    val firstEvents = events(s)
    check(firstEvents.count { it.kind == "RELEASE_OBSERVED" } == 1)
    check(firstEvents.single { it.kind == "RELEASE_OBSERVED" }.value == 20L)
    s.writeStart(old, 1)
    s.writeEnd(old, 1, true, 1)
    check(s.potentialWrites.get() == 1L)

    val oldUpload = checkNotNull(s.submit(old, 1))
    val replacement = buffer(2)
    s.retire(old, 2)
    s.boundary(old, 2)
    s.writeStart(old, 1) // Stale work must not roll tracking generation backwards.
    s.writeEnd(old, 1, false, old.submissions.get())
    check(old.trackingGeneration.get() == 2L)
    oldUpload.run()
    check(s.lateCallbacks.get() == 1L)
    check(replacement.pending.get() == 0 && !replacement.retired.get())
    check(s.pending.get() == 0)

    s.writeStart(replacement, 3)
    val during = checkNotNull(s.submit(replacement, 3))
    s.writeEnd(replacement, 3, true, 0)
    check(s.racedWrites.get() == 1L)
    during.failed()
    check(s.pending.get() == 1 && s.failures.get() == 1L)
    during.run()
    check(s.pending.get() == 0 && s.lateCallbacks.get() == 2L)

    now = s.endNs
    check(!s.isOpen() && !s.acquireWrite()) // Exact automatic 15-second boundary in production.
    check(s.writesInFlight.get() == 0)
    val delayed = checkNotNull(s.submit(replacement, 3)) // Already prepared work can submit late.
    s.accepting = false
    delayed.run()
    check(s.lateCallbacks.get() == 3L && s.pending.get() == 0)

    val limited = BufferLifetimeState(2, now, { now }, queueLimit = 2, uploadLimit = 1,
        totalUploadLimit = 3)
    val limitedBuffer = buffer(3)
    val first = checkNotNull(limited.submit(limitedBuffer, 1))
    check(limited.submit(limitedBuffer, 1) == null)
    check(limited.pending.get() == 1)
    first.run()
    check(limited.pending.get() == 0)
    val third = checkNotNull(limited.submit(limitedBuffer, 1))
    check(limited.submit(limitedBuffer, 1) == null)
    third.run()
    check(limited.omittedUploads.get() == 2L && limited.dropped.get() > 0)
    check(events(limited).size <= 2)

    val concurrent = BufferLifetimeState(3, now, { now }, queueLimit = 10_000)
    val shared = buffer(4)
    val threads = List(4) {
        Thread {
            repeat(100) {
                concurrent.writeStart(shared, 1)
                val before = shared.submissions.get()
                val upload = checkNotNull(concurrent.submit(shared, 1))
                concurrent.writeEnd(shared, 1, true, before)
                upload.run()
            }
        }.apply { start() }
    }
    threads.forEach { it.join() }
    check(shared.pending.get() == 0 && shared.writing.get() == 0)
    check(concurrent.pending.get() == 0 && concurrent.dropped.get() == 0L)
    val submissions = events(concurrent).filter { it.kind == "SUBMIT" }
    check(submissions.size == 400 && submissions.map { it.uploadId }.toSet().size == 400)
    println("PASS: overlap, release, duplicates, late callbacks, generations, exceptions, limits, expiry, MPSC")
}
