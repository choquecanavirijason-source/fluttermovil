$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render'
$output = Join-Path ([IO.Path]::GetTempPath()) ('upper-lid-checks-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
# Only Android-independent data/config adapters. Compile the real filter sources.
$config = Get-Content (Join-Path $render 'RendererConfiguration.kt') -Raw
$constants = foreach ($name in @('LID_POINT_MIN_CUTOFF', 'LID_POINT_BETA', 'ONE_EURO_D_CUTOFF', 'EYE_BLINK_OPEN_BELOW', 'EYE_BLINK_CLOSED_ABOVE', 'OPENNESS_BASELINE_RISE', 'OPENNESS_BASELINE_DECAY', 'OPENNESS_WARMUP_SAMPLES', 'OPENNESS_CLOSED_FRACTION', 'OPENNESS_OPEN_FRACTION', 'SHAPE_TRUST_DROP_BELOW', 'SHAPE_TRUST_RESTORE_ABOVE')) {
    $match = [regex]::Match($config, "const val $name = [0-9.]+f?")
    if (!$match.Success) { throw "Missing config constant: $name" }
    $match.Value
}
$adapter = "package com.example.test_face.render`ndata class ImagePoint(val x: Float, val y: Float)`nobject RendererConfiguration {`n" + ($constants -join "`n") + "`n}"
$adapterPath = Join-Path $output 'Adapters.kt'
[IO.File]::WriteAllText($adapterPath, $adapter)
$jar = Join-Path $output 'checks.jar'
& kotlinc (Join-Path $render 'OneEuroFilter.kt') (Join-Path $render 'UpperLidFilter.kt') (Join-Path $render 'OpennessTracker.kt') $adapterPath (Join-Path $PSScriptRoot 'UpperLidLocalChecks.kt') (Join-Path $PSScriptRoot 'BlinkRecoveryChecks.kt') -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Kotlin compilation failed' }
& java -jar $jar
if ($LASTEXITCODE -ne 0) { throw 'Local shape checks failed' }
