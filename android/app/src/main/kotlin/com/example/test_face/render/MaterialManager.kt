package com.example.test_face.render

import android.util.Log
import com.google.android.filament.Material
import io.github.sceneview.SceneView
import io.github.sceneview.node.ModelNode

/**
 * Material del modelo de pestañas: intenta aplicar el material Filament
 * ANISOTRÓPICO real de fibra (`assets/materials/lash_fiber.filamat`, ver
 * Fase 4 del plan de motor y `lash_fiber.mat` en el mismo directorio) y, si
 * no está disponible, cae de vuelta al ajuste PBR genérico defensivo que ya
 * existía (`doubleSided` sobre el material importado del glTF).
 *
 * El material anisotrópico requiere que el `.glb` tenga tangentes — los
 * assets actuales bajo `assets/modelos` NO las tienen (modelados como
 * geometría sólida sin datos de tangente, ver auditoría del motor); el
 * fallback existe precisamente para no romper nada mientras esos assets no
 * se hayan regenerado con el nuevo generador de Blender
 * (`tools/blender/generate_lash_cards.py`).
 *
 * NO cachea el `Material` compilado entre llamadas: un `Material` creado
 * vía `sceneView.materialLoader` queda atado al `Engine` de ESE `SceneView`
 * — cachearlo a nivel de este `object` (que vive más allá del ciclo de vida
 * de cualquier `SceneView` individual) reproduciría exactamente el bug de
 * referencias a un Engine muerto que ya se corrigió en la auditoría de
 * navegación. Cargar el `.filamat` de assets es una operación barata (no es
 * decodificar un `.glb`), así que recargarlo en cada `loadIntoSlot()` no
 * tiene costo perceptible.
 */
object MaterialManager {

    private const val TAG = "MaterialManager"
    private const val FIBER_MATERIAL_ASSET = "materials/lash_fiber.filamat"

    /** Fuerza de anisotropía del material de fibra ([0,1] — Filament shading
     * model `anisotropic`). No es un parche de proyección/posición como los
     * eliminados en la Fase 1: es un parámetro artístico legítimo del
     * shader, igual que `roughness` en cualquier PBR. */
    private const val ANISOTROPY_STRENGTH = 0.85f

    fun tune(node: ModelNode, sceneView: SceneView) {
        val fiberMaterial = loadFiberMaterial(sceneView)
        if (fiberMaterial != null) {
            applyAnisotropicMaterial(node, fiberMaterial)
        } else {
            tuneGenericPbr(node)
        }
    }

    private fun loadFiberMaterial(sceneView: SceneView): Material? = try {
        sceneView.materialLoader.createMaterial(FIBER_MATERIAL_ASSET)
    } catch (e: Exception) {
        Log.i(
            TAG,
            "Material de fibra ($FIBER_MATERIAL_ASSET) no disponible — usando PBR genérico. " +
                "Ver Fase 4 del plan de motor: requiere compilar lash_fiber.mat con matc y un " +
                ".glb con tangentes (tools/blender/generate_lash_cards.py).",
        )
        null
    }

    private fun applyAnisotropicMaterial(node: ModelNode, template: Material) {
        try {
            val instance = template.createInstance()
            // Dirección de anisotropía en espacio tangente: +X = a lo largo
            // de la fibra — coincide con la U del UV que genera
            // tools/blender/generate_lash_cards.py (s ∈ [0,1] a lo largo de
            // cada tira).
            instance.setParameter("anisotropy", ANISOTROPY_STRENGTH)
            instance.setParameter("anisotropyDirection", 1f, 0f, 0f)
            instance.setDoubleSided(true)
            node.setMaterialInstance(instance)
        } catch (e: Exception) {
            Log.e(TAG, "No se pudo aplicar el material anisotrópico de fibra — cae a PBR genérico", e)
            tuneGenericPbr(node)
        }
    }

    /** Ajuste defensivo sobre el material PBR genérico importado del glTF —
     * comportamiento previo, usado mientras no exista el material de fibra
     * compilado o el `.glb` cargado no tenga tangentes. */
    private fun tuneGenericPbr(node: ModelNode) {
        node.materialInstances.forEach { instances ->
            instances.forEach { instance ->
                try {
                    instance.setDoubleSided(true)
                } catch (e: Exception) {
                    Log.w(TAG, "No se pudo ajustar el material del modelo", e)
                }
            }
        }
    }
}
