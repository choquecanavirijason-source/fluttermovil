$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $env:TEMP ('lash-freeze-checks-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Source($name, $content) { [IO.File]::WriteAllText((Join-Path $output $name), $content, $utf8) }
Write-Source 'Context.kt' @'
package android.content
import java.io.File
open class Context(val directory: File) {
    fun getExternalFilesDir(type: String?): File = directory
    val applicationContext: Context get() = this
}
'@
Write-Source 'Android.kt' @'
package android.util
data class Size(val width: Int, val height: Int)
object Log {
    val messages = mutableListOf<String>()
    fun i(tag: String, text: String): Int { messages.add(text); return 0 }
    fun w(tag: String, text: String): Int { messages.add(text); return 0 }
    fun w(tag: String, text: String, error: Throwable): Int { messages.add(text); return 0 }
}
'@
Write-Source 'Render.kt' @'
package com.example.test_face.render
object RendererConfiguration {
    const val FAST_MOTION_POSITION_SPANS_PER_SEC = 1f
    const val FAST_MOTION_ROTATION_VELOCITY = 1f
    const val PREVIEW_PATH_LATENCY_NANOS = 0L
}
object PoseInterpolator {
    const val INTERVAL_MARGIN_NANOS = 1L
    const val ABSOLUTE_MAX_EXTRAPOLATION_NANOS = 1L
}
object PoseTrajectoryTelemetry { fun configure(context: android.content.Context, enabled: Boolean) {} }
object BufferLifetimeTelemetry { fun configure(context: android.content.Context, enabled: Boolean) {} }
'@
Write-Source 'Checks.kt' @'
import android.content.Context
import com.example.test_face.PerfFlags
import java.io.File
fun main(args: Array<String>) {
    val root = File(args[0]).apply { mkdirs() }
    val ctx = Context(root)
    val file = File(root, PerfFlags.FILE_NAME)
    check(!PerfFlags.read(ctx).first.lashDeformationFreeze) // missing file
    for ((text, expected) in listOf(
        "" to false, "other_flag=on" to false,
        "lash_deformation_freeze=off" to false,
        "lash_deformation_freeze=on" to true,
        "lash_deformation_freeze= ON " to true,
        "lash_deformation_freeze=true" to false,
        "lash_deformation_freeze=invalid" to false,
        "lash_deformation_freeze=" to false
    )) {
        file.writeText(text)
        val cfg = PerfFlags.read(ctx, log = true).first
        check(cfg.lashDeformationFreeze == expected) { text }
        check(!cfg.bufferLifetimeTrace)
        check(PerfFlags.describe(cfg).contains("lash_deformation_freeze=${if(expected) "on" else "off"}"))
    }
    check(android.util.Log.messages.any { it.contains("lash_deformation_freeze=invalid") && it.contains("default") })
    println("PASS: actual PerfFlags parser: missing file/key, on/off, normalized, invalid, empty, log, trace default")
    checkSessions()
}
'@
$cache = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1'
function Find-Jar($relative) {
    $item = Get-ChildItem (Join-Path $cache $relative) -Recurse -Filter '*.jar' | Select-Object -First 1
    if (!$item) { throw "Missing cached jar: $relative" }
    $item.FullName
}
$compiler = Find-Jar 'org.jetbrains.kotlin/kotlin-compiler-embeddable/2.2.20'
$stdlib = Find-Jar 'org.jetbrains.kotlin/kotlin-stdlib/2.2.20'
$annotations = Find-Jar 'org.jetbrains/annotations'
$coroutines = Find-Jar 'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm'
$reflect = Find-Jar 'org.jetbrains.kotlin/kotlin-reflect'
$trove = Find-Jar 'org.jetbrains.intellij.deps/trove4j'
$renderer = [IO.File]::ReadAllText((Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render/LashRenderer.kt'))
$start = $renderer.IndexOf('    @Volatile private var lashDeformationFrozen')
$end = $renderer.IndexOf('    /** Estilo activo', $start)
$sessionMethods = $renderer.Substring($start, $end - $start)
Write-Source 'Session.kt' (@'
import android.util.Log
class FakeGeometry {
    var restores = 0
    fun setVertices(engine: Any, vertices: List<Int>) { check(vertices == listOf(1,2,3)); restores++ }
}
class FakeRaw { val vertices = listOf(1,2,3) }
class FakeSlot { val rawMesh: FakeRaw? = FakeRaw(); val geometry: FakeGeometry? = FakeGeometry() }
class FakeScene { val engine = Any() }
class Session {
    val leftSlot = FakeSlot()
    val rightSlot = FakeSlot()
    val sceneView: FakeScene? = FakeScene()
    val TAG = "test"
    val frozen get() = lashDeformationFrozen
'@ + "`n" + $sessionMethods + @'
}
fun checkSessions() {
    val s = Session()
    s.beginCameraSession(false)
    check(!s.frozen && s.leftSlot.geometry!!.restores == 0)
    s.reportRequestedDeformationMode(true)
    check(!s.frozen) // hot requested ON stays OFF
    s.beginCameraSession(true)
    check(s.frozen && s.leftSlot.geometry!!.restores == 1 && s.rightSlot.geometry!!.restores == 1)
    s.reportRequestedDeformationMode(false)
    check(s.frozen) // hot requested OFF stays ON
    s.beginCameraSession(false)
    check(!s.frozen && s.leftSlot.geometry!!.restores == 1)
    s.beginCameraSession(true)
    check(s.frozen && s.leftSlot.geometry!!.restores == 2)
    println("PASS: actual extracted session methods: OFF/ON latching, hot changes deferred, rest restored on new ON session")
}
'@)
$sources = @(Get-ChildItem $output -Filter '*.kt' | Select-Object -ExpandProperty FullName)
$sources += Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/PerfFlags.kt'
& java -cp ($compiler,$stdlib,$annotations,$coroutines,$reflect,$trove -join ';') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -classpath ($stdlib,$annotations -join ';') -d (Join-Path $output 'classes') @sources
if ($LASTEXITCODE -ne 0) { throw 'Parser harness compilation failed' }
& java -cp ((Join-Path $output 'classes'),$stdlib -join ';') ChecksKt (Join-Path $output 'data')
if ($LASTEXITCODE -ne 0) { throw 'Parser checks failed' }
& node (Join-Path $PSScriptRoot 'static_checks.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Static checks failed' }
