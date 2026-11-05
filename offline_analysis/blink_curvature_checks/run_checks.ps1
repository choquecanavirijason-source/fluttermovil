$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render'
$config = Get-Content (Join-Path $render 'RendererConfiguration.kt') -Raw
$names = @('LASH_CLOSED_DROP_ENABLED', 'LASH_CLOSED_DROP_DEGREES', 'LASH_CLOSED_DROP_GAIN', 'LASH_CLOSED_BAND_COMPENSATION_ENABLED', 'LASH_CLOSED_BAND_FLATTEN', 'LASH_CLOSED_BAND_COMPENSATION_MAX', 'LASH_BEND_SMOOTHING')
$constants = foreach ($name in $names) {
    $match = [regex]::Match($config, "const val $name = (true|false|[0-9.]+f?)")
    if (!$match.Success) { throw "Missing constant: $name" }
    $match.Value
}
$output = Join-Path ([IO.Path]::GetTempPath()) ('blink-curvature-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
$adapter = Join-Path $output 'Config.kt'
[IO.File]::WriteAllText($adapter, "package com.example.test_face.render`nobject RendererConfiguration {`n" + ($constants -join "`n") + "`n}")
$math = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/dev.romainguy/kotlin-math-jvm/1.5.3') -Recurse -Filter '*.jar' | Select-Object -First 1
if (!$math) { throw 'Cached kotlin-math dependency not found' }
$jar = Join-Path $output 'checks.jar'
& kotlinc (Join-Path $render 'LidDropRotation.kt') $adapter (Join-Path $PSScriptRoot 'BlinkCurvatureChecks.kt') -classpath $math.FullName -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Blink checks did not compile' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.BlinkCurvatureChecksKt
if ($LASTEXITCODE -ne 0) { throw 'Blink checks failed' }

$renderer = Get-Content (Join-Path $render 'LashRenderer.kt') -Raw
if (!$renderer.Contains('LidDropRotation.deformationSmoothing(')) { throw 'Renderer is not using the tested compensation policy' }
if (!$renderer.Contains('writeSyncedPose(leftSlot, leftPose, leftClosed)') -or !$renderer.Contains('writeSyncedPose(rightSlot, rightPose, rightClosed)')) { throw 'Frame-specific blink snapshots are missing' }
