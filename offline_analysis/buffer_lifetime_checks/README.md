# BufferLifetime: source-memory diagnostic (Filament 1.51.0)

The experiment does not gate writes, change bendPending, retain geometry resources,
copy vertex data, retry uploads, or change pose publication. The old five-argument
setBufferAt calls remain the path when the flag is off and no earlier diagnostic
write is awaiting submission. Already prepared diagnostic work and its callbacks
are allowed to finish after switching off.

## Contract and lifecycle

Filament 1.51.0's seven-argument setBufferAt overload adds an Object handler and a
Runnable callback to the original arguments. The original five-argument overload
delegates to it with null/null. The callback means the source buffer is no longer
needed; it does not timestamp GPU rendering or presentation.

Sources checked before implementation:
- https://github.com/google/filament/blob/v1.51.0/android/filament-android/src/main/java/com/google/android/filament/VertexBuffer.java
- https://github.com/google/filament/blob/v1.51.0/android/filament-android/src/main/cpp/VertexBuffer.cpp

Callbacks use a Handler on the process main Looper, independent of SceneView's
Engine and of the Activity. They capture diagnostic state only: no Engine, node,
Activity, slot, or FloatBuffer. Native Filament retains its own source-memory
descriptor until release. The observer cannot guarantee delivery after process
death or an abnormal Engine teardown. Unresolved transfers remain pending, not
presumed released. SceneView's existing destruction and reset policies are unchanged.

Model generations increase in EyeModelSlot.reset; renderer and buffer IDs are
monotonic process-local IDs. Tracking boundaries mark release/recovery separately.
An old callback only updates its own old buffer descriptor. Diagnostic generation
checks omit ambiguous observations; they never cancel functional work. Existing
functional reset/upload races are observed, not repaired by this experiment.

## Limits and cost

- 15 seconds of new write observations, independently of timestamp_trace.
- Rearm with off -> on; leaving on does not start successive captures.
- Up to 2048 queued events, 256 pending callbacks, 8192 attempted diagnostic uploads,
  32768 attempted events, 256 binding allocations per capture, and four draining captures.
- Saturation omits diagnostics and preserves the original upload without callback.
- One process-lifetime daemon I/O worker, started only after first enabling; it wakes
  every 250 ms, including while idle. It never runs native callbacks.
- Small event/Write/Upload allocations occur while recording. Queueing is lock-free
  (ConcurrentLinkedQueue plus atomic capacity reservation); no per-frame log or I/O.
- Callback dispatch on the main Looper adds overhead and can delay release observation.
  Observational instrumentation can change scheduling; neutral performance is NOT proven.
- The final report waits for prepared writes and observed callbacks. After 20 seconds,
  unresolved captures produce a SNAPSHOT and keep bounded state for late callbacks.
  A later FINAL includes those callbacks. After four unresolved captures new captures
  are refused; normal rendering continues. No worker shutdown can strand callbacks.

## Future device procedure (not executed by implementation)

Application ID: com.example.test_face. Existing perf_flags.properties must exist;
do not replace it with a file containing only the new property.

PowerShell helper below downloads the existing file, preserves all other property
lines, saves a local backup, and changes only the new diagnostic property. Stop on
duplicate definitions, retrieval failure, or a continued final line. Use a single
connected device (otherwise add -s SERIAL to each adb call).

```powershell
$ErrorActionPreference = 'Stop'
$remoteFlags = '/sdcard/Android/data/com.example.test_face/files/perf_flags.properties'
$captureDir = Join-Path $PWD ('buffer_lifetime_run_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $captureDir | Out-Null
function Set-BufferLifetimeTrace([ValidateSet('on','off')][string]$Value) {
    $local = Join-Path $captureDir 'perf_flags.properties'
    adb pull $remoteFlags $local
    if ($LASTEXITCODE -ne 0) { throw 'Cannot retrieve existing flags; no configuration sent' }
    Copy-Item -LiteralPath $local -Destination ($local + '.' + [guid]::NewGuid() + '.bak')
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]][System.IO.File]::ReadAllLines($local))
    $indices = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*buffer_lifetime_trace\s*[=:]') { $indices += $i }
    }
    if ($indices.Count -gt 1) { throw 'Duplicate diagnostic property; nothing sent' }
    if ($indices.Count -eq 1) { $lines[$indices[0]] = "buffer_lifetime_trace=$Value" }
    else {
        if ($lines.Count -gt 0 -and $lines[$lines.Count-1].TrimEnd().EndsWith('\')) {
            throw 'Continued final property line; nothing sent'
        }
        $lines.Add("buffer_lifetime_trace=$Value")
    }
    [System.IO.File]::WriteAllLines($local, $lines, [System.Text.UTF8Encoding]::new($false))
    adb push $local $remoteFlags
    if ($LASTEXITCODE -ne 0) { throw 'Flags upload failed' }
}

# Existing CameraX flag reload applies the new flag without rebinding CameraX.
# If it was already on, first set off and wait for the effective off log.
Set-BufferLifetimeTrace off
adb logcat -v threadtime 'CameraXManager:I' 'BufferLifetime:I' '*:S'
# Stop logcat with Ctrl+C after PERF_FLAGS confirms off, then:
Set-BufferLifetimeTrace on
adb logcat -v threadtime 'CameraXManager:I' 'BufferLifetime:I' '*:S'
# After START, record ~15 seconds of normal operation; wait for FINAL or SNAPSHOT.
# Stop logcat with Ctrl+C, then:
Set-BufferLifetimeTrace off
adb pull '/sdcard/Android/data/com.example.test_face/files/buffer_lifetime' $captureDir
if ($LASTEXITCODE -ne 0) { throw 'Capture retrieval failed' }
```

There is no restart requirement for the new flag. Verify effective PERF_FLAGS and
BufferLifetime START instead of inferring activation from file contents. Avoid model
changes for the first capture; test reset/model teardown separately afterward.

## CSV and interpretation

All observation timestamps use elapsedRealtimeNanos, never subtracted from a
functional predictor clock. Rows carry captureId, event, rendererId, eye,
modelGeneration, trackingGeneration, bufferId, kind, uploadId, pending, and value.

- WRITE_BEGIN/WRITE_END bracket a bend invocation. This is a conservative write
  window, not the exact time of each per-vertex store. WRITE_ABORT_OR_SKIP means
  no successful bend; an exception can have partially written data.
- WRITE_BEGIN pending > 0 is a potential premature-reuse window relative to prior
  observed submissions of that exact buffer. Inspect the matching upload IDs and
  RELEASE_OBSERVED rows; callback dispatch delay can explain such windows.
- WRITE_END value > 0 counts submissions during the bracket; SUBMIT value > 0
  means a write bracket was open at submission.
- RETURN value is submit-observation -> Java-return-observation in nanoseconds,
  including instrumentation overhead, not isolated JNI execution time.
- RELEASE_OBSERVED[_LATE] value is submit -> callback execution in nanoseconds.
  LATE includes capture end/off, retired model, tracking boundary, or failed call.
- EXCEPTION_UNRESOLVED does not decrement pending. Only a callback does so.
- MODEL_RETIRED and TRACKING_BOUNDARY identify transition segments to exclude.

Summary uses milliseconds for javaObservedMs and callbackMs percentiles; counts
are global capture totals. CSV preserves eye/buffer identity for offline grouping.
Percentiles use floor((N-1)*p). Empty populations yield NaN.

Reject absence-of-overlap conclusions if droppedEvents, omittedUploads, omittedWrites,
ioFailed, exceptions, or unresolved pending are nonzero. Do not assume uploads made
before capture start are tracked. Tracking/model boundaries require separate analysis.
Early-stop and incomplete captures must not be treated as complete 15-second runs.
Correlate CSV rows by IDs and timestamps, not FIFO order across producer threads.

Repeated potential reuse with complete coverage justifies designing explicit buffer
ownership until release, but is not evidence of corruption: the callback may be
queued after the native consumer already released the source. No conclusion about
visible lag, GPU completion or PreviewView synchronization follows from this trace.

## Host verification

Run .\offline_analysis\buffer_lifetime_checks\run_checks.ps1. It uses existing cached
Kotlin compiler jars, creates JVM classes only in a temporary directory, and tests
overlaps, release ordering, duplicate/late callbacks, model/tracking identities,
exceptions, bounded queues/uploads, 15-second expiry and concurrent producers.
It also compares actual bend arguments against HEAD and checks that the original
off-path upload calls and unchanged LashMeshBender source remain present.

These are state-machine and source checks, not a Filament GPU test or a Samsung
performance/visual parity test. An enabled/disabled/on-device FPS comparison and
model/recovery/Engine teardown validation remain necessary before interpreting data.
