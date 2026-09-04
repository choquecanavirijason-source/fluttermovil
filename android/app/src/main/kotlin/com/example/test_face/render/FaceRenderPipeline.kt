package com.example.test_face.render

import android.graphics.Bitmap
import android.util.Log
import kotlin.math.hypot
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

/**
 * Orquesta, para un frame de MediaPipe, el cálculo de la transformación 3D
 * final de cada ojo: pose de cabeza → landmarks del ojo → ancla → plano →
 * transformación. Stateless — el único estado (suavizado, tamaño natural)
 * vive en cada [EyeModelSlot], que el llamador ([LashRenderer]) le pasa por
 * parámetro y aplica al [io.github.sceneview.node.ModelNode] correspondiente.
 *
 * [camera] es la [CameraProjection] real extraída de `SceneView.cameraNode`
 * por [LashRenderer] — necesaria para que [EyeTransformCalculator] des-
 * proyecte con la perspectiva real en vez de un mapeo lineal (Fase 1 del
 * plan de motor).
 */
object FaceRenderPipeline {

    data class Result(val left: EyeTransform?, val right: EyeTransform?)

    fun compute(
        result: FaceLandmarkerResult,
        imageWidth: Int,
        imageHeight: Int,
        leftNaturalSpan: Float,
        rightNaturalSpan: Float,
        camera: CameraProjection,
        /** [EyeModelSlot.rootLocalY] de cada ojo — ver [EyeTransformCalculator]. */
        leftRootLocalY: Float = 0f,
        rightRootLocalY: Float = 0f,
        /** Estilo activo del diseño cargado (ver [LashStyleConfig]) — se
         * aplica a los DOS ojos por igual (un mismo diseño para ambos; la
         * asimetría izq/der la resuelve [RawMesh.mirroredAcrossX] por
         * separado, no este parámetro). */
        styleConfig: LashStyleConfig = LashStyleConfig.DEFAULT,
        /** Bitmap EXACTO analizado por MediaPipe para [result] — ver
         * [LashEdgeDetector]. `null` degrada a solo landmarks. */
        cameraBitmap: Bitmap? = null,
        /** [EyeModelSlot.lidFilter] de cada ojo — suaviza los puntos del
         * arco del párpado antes de ajustar [LashLineCurve]. `null` deja los
         * puntos crudos (comportamiento anterior). */
        leftLidFilter: UpperLidFilter? = null,
        rightLidFilter: UpperLidFilter? = null,
        /** [EyeModelSlot.openness] de cada ojo — decide, con histéresis y un
         * umbral relativo a la persona, si el ojo está lo bastante abierto
         * como para confiar en la geometría del párpado de este frame (ver
         * [OpennessTracker.update]). Se consulta acá, y no en
         * [LashRenderer], porque su respuesta cambia CÓMO se calcula el
         * ancla más abajo. `null` = tratar el ojo siempre como abierto. */
        leftBlinkTracker: OpennessTracker? = null,
        rightBlinkTracker: OpennessTracker? = null,
        /** [EyeModelSlot.lidShape] de cada ojo — la última forma de párpado
         * y la última curva medidas con el ojo abierto, que se reusan
         * mientras dure el parpadeo. Ver [LidShapeHold]. */
        leftLidShape: LidShapeHold? = null,
        rightLidShape: LidShapeHold? = null,
    ): Result? {
        if (result.faceLandmarks().isEmpty()) return null
        val landmarks: List<NormalizedLandmark> = result.faceLandmarks()[0]

        // La pose 3D completa (facialTransformationMatrixes) es lo ideal,
        // pero el anclaje NO debe depender enteramente de esa única
        // capacidad de MediaPipe: si no está disponible, se sigue
        // posicionando/orientando con los landmarks 2D del ojo (siempre
        // presentes con rostro detectado) vía una pose neutra de respaldo —
        // así el modelo nunca deja de mostrarse solo porque falte la matriz.
        val matricesOptional = result.facialTransformationMatrixes()
        val headPose = if (matricesOptional.isPresent && matricesOptional.get().isNotEmpty()) {
            EyePoseEstimator.fromMediaPipeMatrix(matricesOptional.get()[0])
        } else {
            null
        } ?: run {
            Log.w(TAG, "facialTransformationMatrixes no disponible — usando pose de respaldo (solo 2D)")
            EyePoseEstimator.fallback()
        }

        // Apertura por ojo según los blendshapes de MediaPipe: señal de
        // parpadeo INVARIANTE AL ÁNGULO DE CÁMARA, a diferencia de la
        // geométrica que queda de respaldo. Se lee una sola vez por frame
        // (recorre las ~52 categorías) y se reparte a los dos ojos. Ver
        // EyeBlinkBlendshapes para por qué esto importa desde abajo.
        val blendshapeOpenness = EyeBlinkBlendshapes.openness(result)

        val iw = imageWidth.toFloat()
        val ih = imageHeight.toFloat()

        val left = computeEye(
            "LEFT",
            landmarks, FaceLandmarkIndices.LEFT_EYE_RING, FaceLandmarkIndices.LEFT_IRIS,
            FaceLandmarkIndices.LEFT_EYE_MEDIAL_CANTHUS, FaceLandmarkIndices.LEFT_EYE_LATERAL_CANTHUS,
            FaceLandmarkIndices.LEFT_EYE_UPPER_APEX,
            headPose, iw, ih, leftNaturalSpan, camera, RendererConfiguration.LEFT_EYE_X_NUDGE, leftRootLocalY, styleConfig, cameraBitmap,
            leftLidFilter, leftBlinkTracker, leftLidShape, blendshapeOpenness?.left,
        )
        val right = computeEye(
            "RIGHT",
            landmarks, FaceLandmarkIndices.RIGHT_EYE_RING, FaceLandmarkIndices.RIGHT_IRIS,
            FaceLandmarkIndices.RIGHT_EYE_MEDIAL_CANTHUS, FaceLandmarkIndices.RIGHT_EYE_LATERAL_CANTHUS,
            FaceLandmarkIndices.RIGHT_EYE_UPPER_APEX,
            headPose, iw, ih, rightNaturalSpan, camera, RendererConfiguration.RIGHT_EYE_X_NUDGE, rightRootLocalY, styleConfig, cameraBitmap,
            rightLidFilter, rightBlinkTracker, rightLidShape, blendshapeOpenness?.right,
        )
        // Log.v eliminado — corría en CADA frame y agregaba latencia I/O
        return Result(left, right)
    }

    private fun computeEye(
        eyeLabel: String,
        landmarks: List<NormalizedLandmark>,
        ringIndices: IntArray,
        irisIndices: IntArray,
        /** Fase 2 — ver [MeshEyeTransformCalculator] y
         * [RendererConfiguration.LASH_ANCHOR_FROM_FACE_MESH]. Sin uso cuando
         * el flag está en `false` (default). */
        medialCanthusIndex: Int,
        lateralCanthusIndex: Int,
        upperApexIndex: Int,
        headPose: HeadPose,
        imageWidth: Float,
        imageHeight: Float,
        naturalSpan: Float,
        camera: CameraProjection,
        xNudgeNormalized: Float,
        rootLocalY: Float,
        styleConfig: LashStyleConfig,
        cameraBitmap: Bitmap?,
        lidFilter: UpperLidFilter?,
        opennessTracker: OpennessTracker?,
        lidShape: LidShapeHold?,
        /** Apertura de ESTE ojo según blendshapes, o `null` si el resultado
         * no los trae — ver [EyeBlinkBlendshapes]. */
        blendshapeOpenness: Float?,
    ): EyeTransform? {
        val rawEyeLandmarks = EyeLandmarks.from(landmarks, ringIndices, irisIndices, imageWidth, imageHeight)
            ?: return null
        // LashEdgeDetector DESACTIVADO temporalmente: el debug overlay de Flutter
        // muestra los landmarks CRUDOS de MediaPipe (sin corregir). Para que el
        // modelo 3D se ancle en el mismo lugar que los puntos verdes, usamos
        // los mismos landmarks crudos — sin la corrección de píxel del detector.
        // Reactivar cuando el posicionamiento base sea correcto.
        val eyeLandmarks = rawEyeLandmarks

        // ── Parpadeo, ANTES que cualquier geometría ──────────────────────
        // Se decide acá arriba porque su respuesta cambia CÓMO se calcula el
        // ancla: con el ojo cerrándose, la altura del ojo y la inclinación
        // ajustada del párpado dejan de describir un párpado abierto, así
        // que se reusan congeladas en vez de re-medirse (ver LidShape). Este
        // es el fix del "al parpadear se desconfigura": antes la altura, la
        // tangente y la curva se re-deducían en cada frame de unos puntos
        // que durante el parpadeo colapsan sobre el párpado inferior.
        //
        // No decide si la pestaña se VE: con el ojo cerrado se sigue
        // dibujando, que es cuando más se luce una extensión real.
        // Blendshapes primero (invariantes al ángulo de cámara); el
        // alto/ancho medido en la imagen queda sólo de respaldo — ver
        // [EyeBlinkBlendshapes] y [foreshorteningCorrectedOpenness].
        val openness = blendshapeOpenness
            ?: foreshorteningCorrectedOpenness(eyeLandmarks.opennessRatio, headPose)
        val lidShapeTrusted = opennessTracker?.update(openness) ?: true

        // El ancla 2D en píxeles sigue haciendo falta en los DOS modos: la
        // usa LashLineCurve/LashMeshBender más abajo sin cambios (Fase 2 no
        // toca el doblado de mesh, ver el plan) — solo posición/rotación/
        // escala cambian de fuente según el flag.
        val heldShape = if (lidShapeTrusted) null else lidShape?.shape
        val anchor = EyeAnchorCalculator.compute(eyeLandmarks, imageWidth, styleConfig, heldShape)
            ?: return null
        if (lidShapeTrusted) lidShape?.latchShape(anchor.measuredShape)
        // Ver MeshEyeTransformCalculator (fix 2026-09-01): el plano/orientación
        // se calcula UNA vez acá y lo consumen los DOS caminos — el nuevo ya
        // no deriva right/up/normal de landmarks sueltos, toma esto tal cual.
        val plane = EyePlaneCalculator.compute(headPose, eyeLandmarks, anchor)
        val transform = if (RendererConfiguration.LASH_ANCHOR_FROM_FACE_MESH) {
            MeshEyeTransformCalculator.compute(
                landmarks, medialCanthusIndex, lateralCanthusIndex, upperApexIndex,
                // 9..15, NO 8..15 (fix 2026-09-02, skill "filtro"): el índice 8
                // del anillo es el CANTO (133 izq / 263 der) — la esquina donde
                // se juntan párpado superior e inferior, que está por debajo
                // del arco. Incluirlo arrastraba el promedio hacia el centro
                // del ojo. Estos 7 son exactamente los que el skill lista como
                // arco del párpado superior: 173,157,158,159,160,161,246.
                ringIndices.copyOfRange(9, 16),
                camera, headPose, plane, naturalSpan, rootLocalY, styleConfig,
            ) ?: return null
        } else {
            EyeTransformCalculator.compute(
                headPose, plane, anchor, imageWidth, imageHeight, naturalSpan, camera, xNudgeNormalized, rootLocalY,
            )
        }
        if (RendererConfiguration.MESH_CALIBRATION_LOGGING && shouldLogCalibrationFrame()) {
            logMeshCalibration(
                eyeLabel, landmarks, medialCanthusIndex, lateralCanthusIndex, upperApexIndex,
                // 9..16, igual que la llamada REAL de MeshEyeTransformCalculator
                // de arriba. Acá decía 8..16, o sea que el log comparaba contra
                // un sistema nuevo que incluía el CANTO en el arco del párpado
                // — distinto del que se activaría con el flag. Comparar contra
                // algo que no es lo que se va a encender hace inservible la
                // medición, que es justamente para lo que existe este log.
                ringIndices.copyOfRange(9, 16),
                camera, headPose, plane, naturalSpan, rootLocalY, styleConfig,
                anchor, imageWidth, imageHeight, xNudgeNormalized,
            )
        }
        // Curva del párpado superior para el doblado del mesh (ver
        // LashMeshBender) — se ajusta acá porque eyeLandmarks/anchor ya
        // están calculados en este punto, sin duplicar ese trabajo.
        // Origen = anchor.point (el MISMO punto donde EyeTransformCalculator
        // posiciona el mesh) — unificado 2026-08-10 (ver nota de
        // EyeAnchorCalculator): con el spline de Hermite/Catmull-Rom que
        // reemplazó a la parábola por mínimos cuadrados, ajustar lejos del
        // centroide real de los landmarks ya no mal-condiciona el ajuste, así
        // que transform/curva/doblado de mesh comparten un único frame sin
        // offset de reconciliación (`lashCurveAnchorOffsetPx`, eliminado).
        // Puntos SUAVIZADOS para la curva (ver [UpperLidFilter]): el resto
        // del cálculo — ancla, plano, escala — sigue con los crudos, porque
        // esa rama ya pasa por [EyeTrackingFilter] aguas abajo y filtrar dos
        // veces agregaría lag sin quitar más jitter. Lo que NO estaba
        // filtrado en ningún lado era justamente la forma de la curva.
        //
        // Con el ojo cerrándose NO se reajusta ni se alimenta el filtro: se
        // reusa la última curva buena. Dos motivos distintos, los dos
        // reportados en dispositivo al parpadear:
        //  - reajustar sobre un párpado a medio cerrar aplana la curva y
        //    llega a INVERTIR su curvatura cuando el párpado se pliega, con
        //    lo que [LashMeshBender] deforma el abanico hacia el otro lado;
        //  - y meter esos puntos en [UpperLidFilter] contamina su historial,
        //    así que al reabrir el ojo la forma vuelve arrastrando la del
        //    párpado cerrado (One Euro abre su corte con la velocidad, y un
        //    parpadeo es justamente el movimiento más rápido del párpado —
        //    o sea que es cuando MENOS suaviza).
        val curve = if (lidShapeTrusted) {
            val smoothedLid = lidFilter?.apply(eyeLandmarks.upperLid, System.nanoTime())
                ?: eyeLandmarks.upperLid
            LashLineCurve.fit(smoothedLid, anchor.point, anchor.upperLidTangent)
                ?.also { lidShape?.latchCurve(it) }
                ?: lidShape?.curve
        } else {
            lidShape?.curve
        }
        return transform.copy(
            opennessRatio = openness,
            lashLineCurve = curve,
            eyeWidthPx = anchor.widthPx,
            lidShapeTrusted = lidShapeTrusted,
        )
    }

    /**
     * CAMINO DE RESPALDO desde 2026-09-04 — la señal de parpadeo preferida
     * son ahora los blendshapes de MediaPipe ([EyeBlinkBlendshapes]), que no
     * necesitan esta corrección porque no se miden sobre la imagen. Esto se
     * usa sólo si el resultado no trae blendshapes. Se conserva porque es la
     * mejor aproximación disponible en ese caso, pero tiene un tope
     * ([FORESHORTENING_CLAMP]) que en ángulos marcados se queda corta — y esa
     * insuficiencia es justamente lo que hacía que, con la cámara desde
     * abajo, un ojo abierto y escorzado se leyera como un ojo cerrándose.
     *
     * Corrige [EyeLandmarks.opennessRatio] por ESCORZO antes de que
     * [LashRenderer.opennessDamping] decida si el ojo está cerrado.
     *
     * ## Por qué
     *
     * `opennessRatio` es `alto/ancho` del anillo del ojo MEDIDO EN LA IMAGEN,
     * y se compara contra umbrales fijos
     * ([RendererConfiguration.EYE_CLOSED_OPENNESS_THRESHOLD] = 0.12,
     * `EYE_OPEN_...` = 0.22). Pero esa medida no depende solo de cuánto
     * abriste el ojo: también del ÁNGULO de la cabeza.
     *
     * Al mirar la cámara desde ABAJO o desde ARRIBA (que es como la gente
     * se prueba un filtro: se mira de abajo, de frente y de arriba), el ojo
     * se escorza verticalmente y el alto proyectado se encoge con el coseno
     * del cabeceo. Un ojo bien abierto ronda 0.35 de frente, pero a ~60°
     * cae a ~0.18: el motor lo interpretaba como parpadeo, encogía el modelo
     * y al cruzar 0.12 lo OCULTABA — la pestaña desaparecía justo en los
     * ángulos en los que la usuaria la quiere ver.
     *
     * ## Cómo
     *
     * [HeadPose.up] y [HeadPose.right] están en el mundo de Filament, con la
     * cámara mirando por -Z, así que el plano de imagen es XY. La longitud
     * de la proyección de cada eje sobre ese plano (`hypot(x, y)`) es
     * exactamente cuánto sobrevive de ese eje en la imagen:
     *
     *   - `upInPlane`    = 1 de frente, cos(cabeceo) al inclinar → factor por
     *                      el que se encogió el ALTO.
     *   - `rightInPlane` = 1 de frente, cos(giro) al girar → factor por el
     *                      que se encogió el ANCHO.
     *
     * Deshacer ambos escorzos sobre `alto/ancho` es multiplicar por
     * `rightInPlane / upInPlane`. El clamp acota cuánto puede amplificar en
     * ángulos extremos: con 0.45 el factor máximo es ~2.2, suficiente para
     * no perder un ojo abierto y escorzado, pero sin llegar a que un ojo
     * REALMENTE cerrado (ratio ≈ 0.03-0.08) cruce el umbral de 0.12 y deje la
     * pestaña puesta durante un parpadeo.
     *
     * Con la pose de respaldo ([EyePoseEstimator.fallback], sin matriz de
     * MediaPipe) los dos factores valen 1 y esto es un no-op.
     */
    private fun foreshorteningCorrectedOpenness(ratio: Float, headPose: HeadPose): Float {
        val upInPlane = hypot(headPose.up.x, headPose.up.y)
            .coerceIn(FORESHORTENING_CLAMP, 1f)
        val rightInPlane = hypot(headPose.right.x, headPose.right.y)
            .coerceIn(FORESHORTENING_CLAMP, 1f)
        return ratio * (rightInPlane / upInPlane)
    }

    /** Ver [foreshorteningCorrectedOpenness]. */
    private const val FORESHORTENING_CLAMP = 0.45f

    /**
     * Instrumentación temporal de calibración (ver
     * [RendererConfiguration.MESH_CALIBRATION_LOGGING]) — recalcula el
     * sistema que NO está activo ahora mismo (mesh nuevo vs. plano/headPose
     * viejo) solo para loguearlo lado a lado con el activo, tag
     * [CALIB_TAG]. No participa en `transform` ni en el render — puramente
     * diagnóstico, sacar cuando termine esta ronda de calibración de
     * [RendererConfiguration.LASH_ANCHOR_FROM_FACE_MESH].
     */
    /**
     * Throttle del log de calibración: [logMeshCalibration] emite 5 líneas
     * por ojo, o sea 10 por frame — a 30 fps son 300 líneas por segundo. Eso
     * inunda logcat Y agrega I/O en el camino crítico del render, con lo que
     * la medición terminaría distorsionando justo la fluidez que queremos
     * medir. Una tanda por segundo alcanza de sobra para comparar los dos
     * sistemas en cada ángulo.
     *
     * Contador de DIAGNÓSTICO únicamente — es el único estado de este objeto
     * (ver el KDoc de la clase, "Stateless") y solo se toca con
     * [RendererConfiguration.MESH_CALIBRATION_LOGGING] en `true`.
     */
    private var calibrationFrameCounter = 0

    private fun shouldLogCalibrationFrame(): Boolean {
        calibrationFrameCounter++
        // 60 = 2 ojos x 30 resultados de MediaPipe ≈ una tanda por segundo.
        return calibrationFrameCounter % 60 < 2
    }

    private fun logMeshCalibration(
        eyeLabel: String,
        landmarks: List<NormalizedLandmark>,
        medialCanthusIndex: Int,
        lateralCanthusIndex: Int,
        upperApexIndex: Int,
        upperLidIndices: IntArray,
        camera: CameraProjection,
        headPose: HeadPose,
        plane: EyePlane,
        naturalSpan: Float,
        rootLocalY: Float,
        styleConfig: LashStyleConfig,
        anchor: EyeAnchor,
        imageWidth: Float,
        imageHeight: Float,
        xNudgeNormalized: Float,
    ) {
        val meshDebug = MeshEyeTransformCalculator.computeWithDebug(
            landmarks, medialCanthusIndex, lateralCanthusIndex, upperApexIndex, upperLidIndices,
            camera, headPose, plane, naturalSpan, rootLocalY, styleConfig,
        )
        val oldTransform = EyeTransformCalculator.compute(
            headPose, plane, anchor, imageWidth, imageHeight, naturalSpan, camera, xNudgeNormalized, rootLocalY,
        )

        val nt = meshDebug.transform
        if (nt != null) {
            Log.i(
                CALIB_TAG,
                "$eyeLabel NEW pos=(%.4f,%.4f,%.4f) scaleFactor=%.4f scaleY=%.4f normal=(%.4f,%.4f,%.4f) eyeWidthWorld=%.4f eyeHeightWorld=%.4f baseZ=%.4f".format(
                    nt.position.x, nt.position.y, nt.position.z, nt.scale.x, nt.scale.y,
                    meshDebug.normal.x, meshDebug.normal.y, meshDebug.normal.z,
                    meshDebug.eyeWidthWorld, meshDebug.eyeHeightWorld, meshDebug.baseZ,
                ),
            )
            Log.i(
                CALIB_TAG,
                "$eyeLabel NEW_Y_BREAKDOWN centroidY=%.4f anchorBaseY=%.4f heightOffsetTermY=%.4f rootCorrectionTermY=%.4f rootLocalY=%.4f scaleY=%.4f -> posY=%.4f".format(
                    meshDebug.centroidY, meshDebug.anchorBaseY, meshDebug.heightOffsetTermY, meshDebug.rootCorrectionTermY,
                    meshDebug.rootLocalYIn, meshDebug.scaleYOut, nt.position.y,
                ),
            )
            Log.i(
                CALIB_TAG,
                "$eyeLabel BASIS_NEW right=(%.4f,%.4f,%.4f) up=(%.4f,%.4f,%.4f)".format(
                    meshDebug.right.x, meshDebug.right.y, meshDebug.right.z,
                    meshDebug.up.x, meshDebug.up.y, meshDebug.up.z,
                ),
            )
            Log.i(
                CALIB_TAG,
                "$eyeLabel BASIS_OLD right=(%.4f,%.4f,%.4f) up=(%.4f,%.4f,%.4f)".format(
                    plane.right.x, plane.right.y, plane.right.z,
                    plane.up.x, plane.up.y, plane.up.z,
                ),
            )
        } else {
            Log.w(
                CALIB_TAG,
                "$eyeLabel NEW transform=null eyeWidthWorld=%.4f eyeHeightWorld=%.4f baseZ=%.4f".format(
                    meshDebug.eyeWidthWorld, meshDebug.eyeHeightWorld, meshDebug.baseZ,
                ),
            )
        }
        Log.i(
            CALIB_TAG,
            "$eyeLabel OLD pos=(%.4f,%.4f,%.4f) scaleFactor=%.4f scaleY=%.4f".format(
                oldTransform.position.x, oldTransform.position.y, oldTransform.position.z,
                oldTransform.scale.x, oldTransform.scale.y,
            ),
        )
    }

    private const val TAG = "FaceRenderPipeline"
    private const val CALIB_TAG = "MESH_CALIB"
}
