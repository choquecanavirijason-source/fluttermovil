package com.example.test_face.render

/**
 * X de la RAÍZ de la fibra a la que pertenece cada vértice, calculada una vez
 * por modelo.
 *
 * El root binding ubica cada vértice en la línea del párpado según su X. Con
 * la X propia del vértice, la punta de una fibra inclinada hacia afuera caía
 * en OTRO punto de la línea: en la esquina externa (donde el párpado baja y
 * se curva) la fibra seguía esa curva y quedaba "doblada", acostada sobre el
 * borde. Con la X de su raíz, toda la fibra se ancla en el mismo punto y su
 * inclinación se aplica en línea recta desde ahí (ver LashMeshBender).
 *
 * Los modelos del generador (CatEyeRecipe) guardan cada cinta como tramos
 * consecutivos con `uv.x` = 0 en la raíz … 1 en la punta. Si el modelo no
 * sigue ese formato devuelve `null` y el motor usa la X de cada vértice,
 * como antes.
 */
object LashRootX {
    fun perVertex(raw: RawMesh): FloatArray? {
        val vertices = raw.vertices
        if (vertices.isEmpty()) return null
        val height = vertices.maxOf { it.position.y } - raw.minY
        val tolerance = (height * 0.005f).coerceAtLeast(1e-6f)
        val out = FloatArray(vertices.size)
        var current = Float.NaN
        var strips = 0
        var anomalies = 0
        for (i in vertices.indices) {
            val v = vertices[i]
            val uvx = v.uvCoordinate?.x ?: return null
            val atRoot = v.position.y - raw.minY <= tolerance
            if (uvx <= 1e-4f) {
                if (!atRoot) {
                    // Inicio de tramo fuera de la raíz (p. ej. la fila de
                    // arriba del riel): se ancla en su propia X.
                    anomalies++
                    current = Float.NaN
                    out[i] = v.position.x
                    continue
                }
                if (i == 0 || (vertices[i - 1].uvCoordinate?.x ?: 1f) > 1e-4f) strips++
                current = v.position.x
            }
            // Vértices en la fila de la raíz (incluido el riel) se anclan en
            // su propia X; el resto, en la raíz de su tramo.
            out[i] = if (atRoot || current.isNaN()) v.position.x else current
        }
        // Un modelo que no es del generador tiene muchos "inicios" fuera de
        // la raíz: se deja como antes.
        return if (strips >= 8 && anomalies <= strips / 20 + 1) out else null
    }
}
