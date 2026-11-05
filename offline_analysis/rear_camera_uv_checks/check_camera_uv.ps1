$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../..')
$output = Join-Path ([IO.Path]::GetTempPath()) ('camera-uv-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $output | Out-Null
$jar = Join-Path $output 'checks.jar'
& kotlinc (Join-Path $root 'android/app/src/main/kotlin/com/example/test_face/render/CameraUvTransform.kt') (Join-Path $PSScriptRoot 'CameraUvChecks.kt') -include-runtime -d $jar
if ($LASTEXITCODE -ne 0) { throw 'UV checks did not compile' }
& java -jar $jar
if ($LASTEXITCODE -ne 0) { throw 'Camera UV checks failed' }
