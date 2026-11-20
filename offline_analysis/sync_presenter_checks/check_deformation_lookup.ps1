$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render'
$output = Join-Path ([IO.Path]::GetTempPath()) ('lash-lookup-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
[IO.File]::WriteAllText((Join-Path $output 'Geometry.kt'), "package io.github.sceneview.geometries`nimport dev.romainguy.kotlin.math.Float3`nobject Geometry { data class Vertex(val position: Float3, val normal: Float3? = null) }")
[IO.File]::WriteAllText((Join-Path $output 'Normal.kt'), "package io.github.sceneview.math`nimport dev.romainguy.kotlin.math.*`nfun normalToTangent(normal: Float3) = Quaternion(0f,0f,0f,1f)")
[IO.File]::WriteAllText((Join-Path $output 'Log.kt'), "package android.util`nobject Log { fun i(tag: String, value: String) = 0; fun w(tag: String, value: String) = 0 }")
$config = Get-Content (Join-Path $render 'RendererConfiguration.kt') -Raw
$names = @('WIDTH_MULTIPLIER','HEIGHT_VOLUME_MULTIPLIER','LASH_DEFORMATION_ENABLED','MESH_CALIBRATION_LOGGING','LASH_BEND_STRENGTH','LASH_BEND_WING_STRENGTH','LASH_CURVE_FALLOFF_WIDTH_MULTIPLIER')
$constants = foreach ($name in $names) {
    $match = [regex]::Match($config, "const val $name = (true|false|[0-9.]+f?)")
    if (!$match.Success) { throw "Missing constant: $name" }
    $match.Value
}
$types = @'
package com.example.test_face.render
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.geometries.Geometry
data class ImagePoint(val x: Float, val y: Float)
data class RawMesh(val vertices: List<Geometry.Vertex>, val minX: Float, val maxX: Float)
data class LashStyleConfig(val zDepthDropRadiusFraction: Float = 0.5f, val foxyLiftMultiplier: Float = 0f)
'@
[IO.File]::WriteAllText((Join-Path $output 'Types.kt'), $types + "`nobject RendererConfiguration {`n" + ($constants -join "`n") + "`n}")
$math = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/dev.romainguy/kotlin-math-jvm/1.5.3') -Recurse -Filter '*.jar' | Select-Object -First 1
if (!$math) { throw 'Cached kotlin-math dependency not found' }
$sources = @(Get-ChildItem $output -Filter '*.kt' | ForEach-Object FullName)
$sources += (Join-Path $render 'LashMeshBender.kt'), (Join-Path $render 'LashLineCurve.kt'), (Join-Path $render 'LashDeformationLookup.kt'), (Join-Path $PSScriptRoot 'DeformationLookupChecks.kt')
$jar = Join-Path $output 'checks.jar'
& kotlinc @sources -classpath $math.FullName -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Lookup checks did not compile' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.DeformationLookupChecksKt
if ($LASTEXITCODE -ne 0) { throw 'Lookup checks failed' }
