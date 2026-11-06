$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $repo 'android/app/src/main/kotlin/com/example/test_face/render'
$fixtures = Join-Path $PSScriptRoot '../root_pivot_checks'
$output = Join-Path $repo 'build/static_fit_regression'
New-Item -ItemType Directory -Force $output | Out-Null
$math = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/dev.romainguy/kotlin-math-jvm/1.5.3') -Recurse -Filter '*.jar' | Select-Object -First 1
if (!$math) { throw 'Cached kotlin-math dependency not found' }
$sources = @('Geometry.kt','Normal.kt','Log.kt','Types.kt') | ForEach-Object { Join-Path $fixtures $_ }
$sources += (Join-Path $PSScriptRoot 'Check.kt'), (Join-Path $render 'LashLineCurve.kt'), (Join-Path $render 'LashMeshBender.kt'), (Join-Path $render 'LashRootBinding.kt')
$jar = Join-Path $output 'checks.jar'
& kotlinc @sources -classpath $math.FullName -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Static fit checks failed to compile' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.CheckKt
if ($LASTEXITCODE -ne 0) { throw 'Static fit checks failed' }
