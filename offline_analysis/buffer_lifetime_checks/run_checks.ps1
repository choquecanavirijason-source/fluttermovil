$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$cache = Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1'
function Find-Jar([string]$relative) {
    $jar = Get-ChildItem (Join-Path $cache $relative) -Recurse -Filter '*.jar' | Select-Object -First 1
    if (!$jar) { throw "Existing cached dependency missing: $relative" }
    $jar.FullName
}
$compiler = Find-Jar 'org.jetbrains.kotlin/kotlin-compiler-embeddable/2.2.20'
$stdlib = Find-Jar 'org.jetbrains.kotlin/kotlin-stdlib/2.2.20'
$annotations = Find-Jar 'org.jetbrains/annotations'
$coroutines = Find-Jar 'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm'
$reflect = Find-Jar 'org.jetbrains.kotlin/kotlin-reflect'
$trove = Find-Jar 'org.jetbrains.intellij.deps/trove4j'
$output = Join-Path ([System.IO.Path]::GetTempPath()) ('buffer-lifetime-checks-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
$state = Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render/BufferLifetimeState.kt'
& java -cp ($compiler,$stdlib,$annotations,$coroutines,$reflect,$trove -join ';') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
    -no-stdlib -no-reflect -classpath ($stdlib,$annotations -join ';') -d $output `
    $state (Join-Path $PSScriptRoot 'BufferLifetimeStateChecks.kt')
if ($LASTEXITCODE -ne 0) { throw 'Kotlin state checks did not compile' }
& java -cp ($output,$stdlib -join ';') com.example.test_face.render.BufferLifetimeStateChecksKt
if ($LASTEXITCODE -ne 0) { throw 'Kotlin state checks failed' }
Write-Host "JVM test classes: $output"

# Check actual functional arguments against HEAD; prior telemetry is preserved.
$renderer = 'android/app/src/main/kotlin/com/example/test_face/render/LashRenderer.kt'
$before = (& git -C $root show ('HEAD:' + $renderer)) -join "`n"
$after = Get-Content (Join-Path $root $renderer) -Raw
$call = 'LashMeshBender\.bendInPlace\(([\s\S]*?)\n\s*\)'
$beforeArgs = [regex]::Match($before, $call).Groups[1].Value -replace '\s+', ''
$afterArgs = [regex]::Match($after, $call).Groups[1].Value -replace '\s+', ''
if (!$beforeArgs -or $beforeArgs -cne $afterArgs) { throw 'Functional bend arguments changed' }
foreach ($line in @(
    'geometry.vertexBuffer.setBufferAt(engine, 0, target, 0, vertexCount * 3)',
    'geometry.vertexBuffer.setBufferAt(engine, 1, tangentTarget, 0, vertexCount * 4)'
)) {
    if (!$before.Contains($line) -or !$after.Contains($line)) { throw "Original off-path missing: $line" }
}
$benderDiff = & git -C $root diff HEAD -- 'android/app/src/main/kotlin/com/example/test_face/render/LashMeshBender.kt'
if ($benderDiff) { throw 'LashMeshBender changed' }
Write-Host 'PASS: bend arguments unchanged; original off-path upload arguments preserved; bender unchanged'
