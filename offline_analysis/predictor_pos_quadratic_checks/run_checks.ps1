$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $env:TEMP ('predictor-quadratic-checks-' + [guid]::NewGuid())
& node (Join-Path $PSScriptRoot 'generate_checks.cjs') $output
if ($LASTEXITCODE -ne 0) { throw 'Static checks/generation failed' }
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
$math = Find-Jar 'dev.romainguy/kotlin-math-jvm/1.5.3'
$sources = @(Get-ChildItem $output -Filter '*.kt' | Select-Object -ExpandProperty FullName)
$sources += Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/PerfFlags.kt'
& java -cp ($compiler,$stdlib,$annotations,$coroutines,$reflect,$trove -join ';') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -classpath ($stdlib,$annotations,$math -join ';') -d (Join-Path $output 'classes') @sources
if ($LASTEXITCODE -ne 0) { throw 'Kotlin checks compilation failed' }
& java -cp ((Join-Path $output 'classes'),$stdlib,$math -join ';') ChecksKt (Join-Path $output 'data')
if ($LASTEXITCODE -ne 0) { throw 'Kotlin checks failed' }
