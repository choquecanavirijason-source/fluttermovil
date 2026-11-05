# Cámara trasera sobre el checkpoint d2f074f

Se restauró el comportamiento del commit d2f074f a petición del usuario,
conservando únicamente la corrección validada del espejo de la cámara trasera.
CameraBackground usa CameraUvTransform para aplicar la inversión horizontal
adicional solo en la ruta frontal. La trasera conserva su imagen sin espejo.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File offline_analysis/rear_camera_uv_checks/check_camera_uv.ps1
```

La prueba compila la transformación real: 175 casos de la frontal coinciden con
la fórmula original, U aumenta de izquierda a derecha en la trasera con giro 0,
y se conservan las conversiones de los giros de 90/180/270 grados.

Los experimentos posteriores al checkpoint se respaldaron localmente en
build/rollback_before_d2f074f (sin versionar). También se respaldó el archivo de
configuración del teléfono para poder retirarlo al instalar la versión restaurada.

La versión restaurada compiló, se instaló por Wi-Fi y se abrió. Se retiró el
archivo experimental del teléfono y se verificó DEFAULT_CONFIG_RESTORED: la app
usa los valores originales del checkpoint. Solo queda como diferencia funcional
la corrección del espejo de la cámara trasera validada por el usuario.
