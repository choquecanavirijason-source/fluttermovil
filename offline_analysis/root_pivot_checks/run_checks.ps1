$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $repo 'android/app/src/main/kotlin/com/example/test_face/render'
$output = Join-Path $repo 'build/root_pivot_regression'
New-Item -ItemType Directory -Force $output | Out-Null
$math = Get-ChildItem (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1/dev.romainguy/kotlin-math-jvm/1.5.3') -Recurse -Filter '*.jar' | Select-Object -First 1
if (!$math) { throw 'Cached kotlin-math dependency not found' }
$sources = @(Get-ChildItem $PSScriptRoot -Filter '*.kt' | ForEach-Object FullName)
$sources += (Join-Path $render 'LashLineCurve.kt'), (Join-Path $render 'LashMeshBender.kt'), (Join-Path $render 'LashRootDepth.kt'), (Join-Path $render 'LashRootBinding.kt')
$jar = Join-Path $output 'checks.jar'
& kotlinc @sources -classpath $math.FullName -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'Root pivot checks failed to compile' }
& java -cp ($jar + ';' + $math.FullName) com.example.test_face.render.CheckKt
if ($LASTEXITCODE -ne 0) { throw 'Root pivot checks failed' }
