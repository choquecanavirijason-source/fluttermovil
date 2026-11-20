$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render'
$output = Join-Path ([IO.Path]::GetTempPath()) ('sync-presenter-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
[IO.File]::WriteAllText((Join-Path $output 'Image.kt'), "package android.media`nclass Image(val timestamp: Long) { var closed=0; fun close() { closed++; check(closed == 1) } }")
[IO.File]::WriteAllText((Join-Path $output 'Clock.kt'), "package android.os`nobject SystemClock { fun elapsedRealtimeNanos() = System.nanoTime() }")
[IO.File]::WriteAllText((Join-Path $output 'Log.kt'), "package android.util`nobject Log { fun i(tag: String, value: String) = 0 }")
$config = Get-Content (Join-Path $render 'RendererConfiguration.kt') -Raw
$constant = [regex]::Match($config, 'const val LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER = [0-9.]+f').Value
if (!$constant) { throw 'Curve constant missing' }
$types = @'
package com.example.test_face.render
import dev.romainguy.kotlin.math.Float3
import dev.romainguy.kotlin.math.Quaternion
data class ImagePoint(val x: Float, val y: Float)
class CameraProjection
data class LashStyleConfig(val id: Int = 0)
data class EyeTransform(val position: Float3, val rotation: Quaternion, val scale: Float3,
    val eyeWidthPx: Float = 0f, val worldPerImagePx: Float = 0f, val lashLineCurve: LashLineCurve? = null)
'@
[IO.File]::WriteAllText((Join-Path $output 'Types.kt'), $types + "`nobject RendererConfiguration { $constant }")
$math = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/dev.romainguy/kotlin-math-jvm/1.5.3') -Recurse -Filter '*.jar' | Select-Object -First 1
if (!$math) { throw 'Cached kotlin-math dependency not found' }
$sources = @(Get-ChildItem $output -Filter '*.kt' | ForEach-Object FullName)
$sources += (Join-Path $render 'SyncPresenter.kt'), (Join-Path $render 'LashLineCurve.kt'), (Join-Path $PSScriptRoot 'SyncPresenterChecks.kt')
$jar = Join-Path $output 'checks.jar'
& kotlinc @sources -classpath $math.FullName -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Sync checks did not compile' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.SyncPresenterChecksKt
if ($LASTEXITCODE -ne 0) { throw 'Sync checks failed' }
