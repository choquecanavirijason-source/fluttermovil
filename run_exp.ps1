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
$lines = adb logcat -v time -d -s LashRenderer:I CameraXManager:I FaceLandmarkerHelper:I flutter:I |
    Select-String "PERF_|DISPOSITIVO|RESINFO|Delegado|TIEMPOS_ETAPAS|FLUTTER_TIMINGS|TERMICO" |
    ForEach-Object { $_.Line }

# Estado térmico SEVERE o peor: la CPU/GPU bajan de frecuencia y los tiempos
# no se pueden comparar con otra corrida. Se avisa en consola y en la PRIMERA
# línea del archivo, para que no pase desapercibido al pegar el log.
$hot = @($lines | Where-Object { $_ -match "termico=(SEVERE|CRITICAL|EMERGENCY|SHUTDOWN)" })
$header = @()
if ($hot.Count -gt 0) {
    $total = @($lines | Where-Object { $_ -match "TIEMPOS_ETAPAS" }).Count
    $warn = "!!! MEDICION NO COMPARABLE: $($hot.Count) de $total ventanas con termico SEVERE o peor - dejar enfriar el equipo y repetir !!!"
    Write-Host $warn -ForegroundColor Red
    $header = @($warn)
}
($header + $lines) | Tee-Object -FilePath "exp_$Name.txt"
