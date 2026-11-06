$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $repo 'android/app/src/main/kotlin/com/example/test_face/render'
$output = Join-Path $repo 'build/root_binding_regression'
New-Item -ItemType Directory -Force $output | Out-Null
$fixtures = Join-Path $PSScriptRoot '../root_pivot_checks'
$math = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/dev.romainguy/kotlin-math-jvm/1.5.3') -Recurse -Filter '*.jar' | Select-Object -First 1
if (!$math) { throw 'Cached kotlin-math dependency not found' }
$sources = @('Geometry.kt','Normal.kt','Log.kt') | ForEach-Object { Join-Path $fixtures $_ }
$sources += @(Get-ChildItem $PSScriptRoot -Filter '*.kt' | ForEach-Object FullName)
$sources += @('LashLineCurve.kt','LashMeshBender.kt','LashRootBinding.kt','LashRootDepth.kt','LidDropRotation.kt','CameraProjection.kt') | ForEach-Object { Join-Path $render $_ }
$jar = Join-Path $output 'checks.jar'
& kotlinc @sources -classpath $math.FullName -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Root binding checks failed to compile' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.CheckKt
if ($LASTEXITCODE -ne 0) { throw 'Root binding checks failed' }
$meshes = Join-Path $output 'meshes'
& python (Join-Path $PSScriptRoot 'extract_assets.py') $meshes
if ($LASTEXITCODE -ne 0) { throw 'Asset fixture extraction failed' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.AssetCheckKt $meshes
if ($LASTEXITCODE -ne 0) { throw 'Real asset binding checks failed' }
