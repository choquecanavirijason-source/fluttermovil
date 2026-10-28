param(
    [string]$Name, 
    [string]$Flags = ""
)

$pkg = "com.example.test_face"
$dir = "/sdcard/Android/data/$pkg/files"

Write-Host "Preparando entorno..."
adb shell am force-stop $pkg

if ($Flags -eq "") {  
    adb shell "rm -f $dir/perf_flags.properties"
} else {  
    $content = ($Flags -split ";") -join "`n"  
    adb shell "printf '$content`n' > $dir/perf_flags.properties"
}

adb logcat -c
adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null

Read-Host "App lista. Navega a la camara/filtro, quieto 5 s, mueve la cabeza 30 s y PRESIONA ENTER AL TERMINAR"

Write-Host "Extrayendo logs..."
adb logcat -v time -d -s LashRenderer:I CameraXManager:I FaceLandmarkerHelper:I flutter:I | Select-String "PERF_|DISPOSITIVO|RESINFO|Delegado|TIEMPOS_ETAPAS|FLUTTER_TIMINGS" | Tee-Object -FilePath "exp_$Name.txt"
