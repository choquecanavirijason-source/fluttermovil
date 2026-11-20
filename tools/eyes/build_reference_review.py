"""Build an offline review gallery and CSV from measured reference frames."""
import argparse
import csv
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


NOTES = {
    "redondos_01": ("comparación", "Apertura amplia. La medición está junto al límite actual; revisar la etiqueta de forma."),
    "redondos_02": ("comparación", "Delineado visible. El ancho/alto se solapa con referencias del grupo almendrado."),
    "redondos_03_DUDOSO": ("gesto", "Apertura reducida y gesto en la zona de las cejas. Revisar antes de usar para calibrar la forma."),
    "redondos_04_DUDOSO": ("encuadre", "Rostro parcialmente recortado y maquillaje de ojos visible. Útil como prueba de encuadre."),
    "redondos_05_DUDOSO": ("gesto", "Sonrisa y orientación de la mirada. Útil para comprobar cambios por expresión."),
    "almendrados_01": ("maquillaje", "Delineado/sombra visibles alrededor de los ojos. Revisar como caso de maquillaje."),
    "almendrados_02": ("comparación", "Mirada frontal y contorno visible. Candidata para comparar mediciones; etiqueta pendiente de revisión."),
    "almendrados_03": ("gesto", "Apertura ocular reducida. El analizador devuelve alargado; la forma natural requiere otra toma."),
    "almendrados_04": ("comparación", "Contorno visible con maquillaje en los bordes. Candidata para comparar apertura."),
    "almendrados_05": ("postura", "Inclinación visible del rostro. Útil para verificar invariancia a la rotación."),
    "almendrados_06_DUDOSO": ("comparación", "Priorizar contorno y postura al revisar. El labial por sí solo no indica que falle la medida del ojo."),
    "alargados_01_DUDOSO": ("etiqueta", "Maquillaje alrededor del ojo. El contorno medido cae en el intervalo intermedio; revisar el grupo."),
    "alargados_02_DUDOSO": ("etiqueta", "Encuadre cerrado. El contorno medido cae en el intervalo intermedio; revisar el grupo."),
    "alargados_03": ("etiqueta", "El ancho/alto medido se solapa con las referencias almendradas. La etiqueta alargado necesita revisión."),
    "alargados_04_DUDOSO": ("postura", "Cabeza girada y mirada oblicua. Útil como caso de pose, pendiente de una toma frontal para calibración."),
    "encapotados_01": ("párpado", "Referencia de párpado y apertura reducida. La forma del contorno se evalúa por separado."),
    "encapotados_02": ("párpado", "Referencia de párpado con iluminación cálida y direccional; revisar también calidad de luz."),
    "encapotados_03_DUDOSO": ("párpado", "La relación entre pliegue, sombra y contorno necesita revisión manual."),
    "encapotados_04": ("párpado", "Referencia frontal de párpado. Su etiqueta es independiente de la forma del contorno."),
    "encapotados_05_DUDOSO": ("párpado", "Expresión y pliegues visibles; requiere revisión manual de la característica del párpado."),
    "monolidos_01": ("párpado", "Revisar el pliegue superior a resolución completa. La medida del contorno es independiente."),
    "monolidos_02": ("párpado", "Referencia frontal para revisar el pliegue superior y el contorno por separado."),
    "monolidos_03": ("párpado", "Revisar cada párpado por separado; la etiqueta provisional requiere confirmación."),
    "monolidos_04_DUDOSO": ("párpado", "Pliegue bajo o poco visible. Conservar como referencia ambigua para revisión."),
    "monolidos_05_DUDOSO": ("párpado", "Comprobar el detalle de ambos párpados en la imagen original y revisar la etiqueta."),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    document = json.loads(args.results.read_text(encoding="utf-8"))
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for entry in document["rows"]:
        stem = Path(entry["archivo"]).stem
        use, note = NOTES.get(stem, ("pendiente", "Pendiente de revisión visual"))
        analysis = entry["analysis"]
        rows.append({
            **{k: v for k, v in entry.items() if k != "frame"},
            "uso_recomendado": use, "nota_revision": note,
            "photo_uri": Path(entry["source_path"]).as_uri(),
            "ratio": round(analysis["aspect_ratio"], 4) if analysis["reliable"] else None,
            "inclinacion": round(analysis["tilt_deg"], 2) if analysis["reliable"] else None,
            "forma_app": analysis["shape"],
        })
    fields = ["archivo", "grupo_provisional", "estado", "forma_app", "ratio",
              "inclinacion", "uso_recomendado", "nota_revision", "enlace_original", "licencia"]
    with (output / "indice_revisado.csv").open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    # Diagnostic crops are derived views. Original source images remain inputs.
    width, cell_height = 360, 195
    groups = list(dict.fromkeys(row["grupo_provisional"] for row in rows))
    columns = max(sum(row["grupo_provisional"] == group for row in rows) for group in groups)
    contact = Image.new("RGB", (width * columns, cell_height * len(groups)), "#eef3ef")
    draw = ImageDraw.Draw(contact)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)
    for group_index, group in enumerate(groups):
        entries = [e for e in document["rows"] if e["grupo_provisional"] == group]
        for column, entry in enumerate(entries):
            image = ImageOps.exif_transpose(Image.open(entry["source_path"])).convert("RGB")
            frame = entry["frame"]
            points = frame["leftEye"] + frame["rightEye"]
            if not points:
                continue
            xs = [p["x"] * image.width / frame["imageWidth"] for p in points]
            ys = [p["y"] * image.height / frame["imageHeight"] for p in points]
            eye_width, eye_height = max(xs) - min(xs), max(ys) - min(ys)
            crop = image.crop((max(0, int(min(xs) - eye_width * .05)),
                               max(0, int(min(ys) - eye_height * .75)),
                               min(image.width, int(max(xs) + eye_width * .05)),
                               min(image.height, int(max(ys) + eye_height * .55))))
            crop.thumbnail((348, 132))
            x, y = column * width, group_index * cell_height
            contact.paste(crop, (x + (width - crop.width) // 2, y + 4))
            draw.rectangle((x + 2, y + 2, x + 357, y + 192), outline="#a47b42", width=2)
            draw.text((x + 9, y + 142), Path(entry["archivo"]).stem, font=font, fill="#183726")
            a = entry["analysis"]
            draw.text((x + 9, y + 166), f"App: {a['shape']} / ancho-alto {a['aspect_ratio']:.2f}", font=font, fill="#304b3b")
    contact.save(output / "contacto_ojos.jpg", quality=94)

    data = json.dumps(rows, ensure_ascii=False).replace("<", "\\u003c")
    page = """<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Revisión de referencias reales · Elashes</title><style>
*{box-sizing:border-box}body{margin:0;background:#f1f4f0;color:#1a3427;font:15px system-ui,sans-serif}header{background:#094732;color:#fff;padding:22px 28px}h1{font-size:24px;margin:0 0 7px}header p{margin:0;color:#dce8df}main{display:grid;grid-template-columns:340px 1fr;gap:20px;padding:22px}aside,article{background:#fff;border:1px solid #dce4dc;border-radius:12px;padding:20px}article{display:flex;flex-direction:column;align-items:center}img{max-width:100%;height:70vh;object-fit:contain}button,select{padding:10px;border:1px solid #a5b9ab;border-radius:6px;background:#fff;color:#094732}button{cursor:pointer}nav{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}label{display:block;margin:16px 0}label select{display:block;margin-top:7px;width:100%}.note{background:#edf4ec;padding:12px;border-left:3px solid #9f8351;line-height:1.5}.small{font-size:12px;color:#5b6c60}strong{font-weight:650}a{color:#094732}p{line-height:1.5}body.focus main{grid-template-columns:1fr}body.focus aside,body.focus header{display:none}body.focus img{height:90vh}#back{position:fixed;top:12px;right:12px;display:none}body.focus #back{display:block}@media(max-width:750px){main{grid-template-columns:1fr;padding:10px}img{height:65vh}}
</style><header><h1>25 referencias reales · revisión de etiquetas</h1><p>Detectadas 25 caras. Las etiquetas de origen son provisionales. Forma e información del párpado se revisan por separado.</p></header>
<main><aside><strong id="name"></strong><p id="source"></p><p class="note" id="metrics"></p><p id="review"></p><p class="small" id="originalnote"></p>
<label>Grupo de origen<select id="filter"><option value="">Todos</option></select></label><nav><button id="prev">Anterior</button><button id="next">Siguiente</button></nav>
<label>Forma revisada por el salón<select id="shape"><option value="">Pendiente</option><option>Redondo</option><option>Almendrado</option><option>Alargado</option><option>Ambiguo / otra toma</option></select></label>
<label>Párpado revisado por el salón<select id="lid"><option value="">Pendiente</option><option>Pliegue visible</option><option>Encapotado</option><option>Monólido</option><option>Ambiguo / otra toma</option></select></label>
<nav><button id="export">Exportar revisión</button><button id="focus">Solo fotografía</button></nav><p><a href="indice_revisado.csv">Medidas y notas en CSV</a> · <a href="contacto_ojos.jpg">Resumen de ojos</a></p>
<p class="small">Análisis local con el archivo de modelo de la app. Ejecución CPU en modo imagen. En el teléfono pueden variar los resultados por captura, resolución, seguimiento temporal y versión del runtime.</p>
<p class="small">Las referencias de encapotado y monólido sirven para revisión de párpados. El analizador actual solo clasifica tres formas del contorno. Las fotos originales y el índice permanecen en su carpeta de origen.</p>
<p class="small" id="license"></p><a id="original" target="_blank" rel="noreferrer">Abrir página original</a></aside><article><img id="photo" alt="Referencia facial para revisión"><p id="position" class="small"></p></article></main><button id="back">Volver a la revisión</button>
<script>const rows=__DATA__;const storageKey='elashes-eye-review-__KEY__';let saved={};try{saved=JSON.parse(localStorage.getItem(storageKey)||'{}')}catch{}let visible=rows,index=0;const el=id=>document.getElementById(id);
for(const group of [...new Set(rows.map(r=>r.grupo_provisional))]){const option=document.createElement('option');option.value=group;option.textContent=group;el('filter').append(option)}
function show(){const r=visible[index];el('name').textContent=r.archivo;el('source').textContent='Grupo provisional: '+r.grupo_provisional+' · '+r.estado;el('metrics').textContent='App: '+r.forma_app+' · ancho/alto '+r.ratio.toFixed(2)+' · inclinación '+r.inclinacion.toFixed(1)+'°';el('review').textContent=r.nota_revision;el('originalnote').textContent='Nota de origen: '+(r.nota||'sin observaciones');el('photo').src=r.photo_uri;el('position').textContent=(index+1)+' / '+visible.length;el('original').href=r.enlace_original;el('license').textContent='Licencia indicada por la colección: '+r.licencia;el('shape').value=saved[r.archivo]?.shape||'';el('lid').value=saved[r.archivo]?.lid||''}
function move(delta){index=(index+delta+visible.length)%visible.length;show()}
el('next').onclick=()=>move(1);el('prev').onclick=()=>move(-1);el('filter').onchange=()=>{visible=rows.filter(r=>!el('filter').value||r.grupo_provisional===el('filter').value);index=0;show()};
function save(){const r=visible[index];saved[r.archivo]={shape:el('shape').value,lid:el('lid').value};try{localStorage.setItem(storageKey,JSON.stringify(saved))}catch{}}
el('shape').onchange=save;el('lid').onchange=save;el('export').onclick=()=>{const blob=new Blob([JSON.stringify(rows.map(r=>({archivo:r.archivo,grupo_provisional:r.grupo_provisional,revision:saved[r.archivo]||null})),null,2)],{type:'application/json'});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='revision_salon_ojos.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
el('focus').onclick=()=>document.body.classList.add('focus');el('back').onclick=()=>document.body.classList.remove('focus');document.addEventListener('keydown',e=>{if(e.target.tagName==='SELECT')return;if(e.key==='ArrowRight')move(1);if(e.key==='ArrowLeft')move(-1);if(e.key==='Escape')document.body.classList.remove('focus')});show();</script></html>"""
    key = hashlib.sha256(args.results.read_bytes()).hexdigest()[:16]
    page = page.replace("__DATA__", data).replace("__KEY__", key)
    (output / "revision.html").write_text(page, encoding="utf-8")
    summary = {"runtime": document["mediapipe_version"], "model_sha256": document["model_sha256"],
               "running_mode": document["running_mode"], "rows": rows}
    (output / "resultados.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Review created at {output.resolve()}")


if __name__ == "__main__":
    main()
