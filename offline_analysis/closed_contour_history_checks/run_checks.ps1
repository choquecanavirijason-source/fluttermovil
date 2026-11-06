$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '../..')
$render = Join-Path $repo 'android/app/src/main/kotlin/com/example/test_face/render'
$output = Join-Path $repo 'build/closed_contour_history_regression'
New-Item -ItemType Directory -Force $output | Out-Null
$jar = Join-Path $output 'checks.jar'
& kotlinc (Join-Path $render 'LashLineCurve.kt') (Join-Path $render 'ClosedLidContour.kt') (Join-Path $PSScriptRoot 'Check.kt') -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'History checks failed to compile' }
& java -jar $jar
if ($LASTEXITCODE -ne 0) { throw 'History checks failed' }
