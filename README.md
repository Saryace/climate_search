# Búsqueda en bases de datos: OpenAlex, WoS y Scopus

Búsqueda sistemática de literatura sobre **adaptación al cambio climático en
contextos urbanos de Centro y Sudamérica**, 2021–2025.

> Esta parte del repositorio cubre **solo la búsqueda y consolidación de
> registros crudos**: descarga desde las tres bases + deduplicación por DOI.
- **Bases:** Web of Science, Scopus y OpenAlex
- **Idiomas:** inglés, español y portugués
- **Ventana temporal:** 2021–2025
- **Deduplicación:** coincidencia exacta por DOI (insensible a mayúsculas)

---

## Estructura (etapa de búsqueda)

```
climate_search/
├── climate_search.Rproj
├── PACKAGES.R                ← instala paquetes y explica las claves API
├── run_pipeline.R            ← ejecuta los pasos en orden
├── R/
│   ├── queries.R             ← listas de conceptos + consultas de las 3 bases
│   ├── 01_retrieve_openalex.R   OpenAlex (openalexR, gratis, requiere email)
│   ├── 02_retrieve_wos.R        WoS Starter API (rwosstarter, requiere key)
│   ├── 03_retrieve_scopus.R     Scopus (rscopus, requiere key institucional)
│   └── 04_merge_and_dedup.R     une las 3 fuentes y deduplica por DOI
└── data/
    ├── raw/                  ← salidas de cada búsqueda (*_raw.csv)
    └── processed/            ← registros únicos tras deduplicar
```

---

## Cómo se construyen las búsquedas

Las tres bases comparten **las mismas listas de conceptos**, definidas una sola
vez en `R/queries.R`:

| Lista | Concepto |
|-------|----------|
| `climate_*` | cambio climático |
| `adaptation_*` | adaptación |
| `urban_*` | urbano / ambiente / amenazas |
| `countries_*` | países de Centro y Sudamérica |

La lógica es **idéntica** en las tres bases:

```
(cambio climatico) AND (adaptación) AND (urbano) AND (países)
```

Dentro de cada lista los términos se unen con **OR**; las cuatro listas se unen
con **AND**. Lo único que cambia es la sintaxis que envuelve los bloques:

| Base | Campo de búsqueda | Filtro de año |
|------|-------------------|---------------|
| OpenAlex | `title_and_abstract.search` | aparte, en `oa_fetch()` |
| WoS | `TS=( ... )` | `PY=(2021-2025)` |
| Scopus | `TITLE-ABS-KEY( ... )` | `PUBYEAR > 2020 AND PUBYEAR < 2026` |

Para editar la estrategia de búsqueda solo se tocan las listas de conceptos; las
consultas de las tres bases se regeneran solas.

### Dos diferencias entre motores que conviene tener presentes

1. **Alcance del campo.** OpenAlex busca solo en **título y resumen**. WoS (`TS=`)
   y Scopus (`TITLE-ABS-KEY`) además incluyen **palabras clave**, por lo que
   pueden recuperar algo más.
2. **Comodín `adapt*`.** En WoS y Scopus el `*` **trunca** (adapt, adaptation,
   adaptación, adaptive…). OpenAlex **no trunca** con `*`: aplica lematización
   sobre la raíz. En la práctica recuperan la misma familia de términos, pero los
   resultados pueden diferir un poco. Si necesitas comportamiento idéntico,
   reemplaza `adapt*` por variantes explícitas en cada idioma.

---

### 1. Instalar paquetes

```r
source("PACKAGES.R")
```

### 2. Configurar claves API

Agrega a `~/.Renviron` (ábrelo con `usethis::edit_r_environ()`):

```
WOS_STARTER_KEY="tu_clave_wos"
Elsevier_API="tu_clave_scopus"
```

Reinicia R después de guardar.

| Clave | Dónde obtenerla | Restricciones |
|-------|-----------------|---------------|
| `WOS_STARTER_KEY` | [developer.clarivate.com](https://developer.clarivate.com) | Gratis; ~1000 registros/consulta |
| `Elsevier_API` | [dev.elsevier.com](https://dev.elsevier.com) | Requiere suscripción institucional; atada a la IP — usar red del campus o VPN |

Y configura tu correo para OpenAlex en `R/01_retrieve_openalex.R`:

```r
options(openalexR.mailto = "tu@correo.com")
```

### 3. Ejecutar la búsqueda

Paso a paso:

```r
source("R/01_retrieve_openalex.R")   # OpenAlex (no requiere clave, solo email)
source("R/02_retrieve_wos.R")        # requiere WOS_STARTER_KEY
source("R/03_retrieve_scopus.R")     # requiere Elsevier_API (IP institucional)
source("R/04_merge_and_dedup.R")     # une las 3 fuentes y deduplica por DOI
```

Cada script de descarga guarda su propio `*_raw.csv` en `data/raw/`, así que
puedes volver a correr uno solo sin repetir los demás.

---

## Salidas

| Archivo | Contenido |
|---------|-----------|
| `data/raw/openalex_raw.csv` | registros crudos de OpenAlex |
| `data/raw/wos_raw.csv` | registros crudos de WoS |
| `data/raw/scopus_raw.csv` | registros crudos de Scopus |
| `data/processed/merged_all.csv` | todos los registros, con su base de origen |
| `data/processed/unique_records.csv` | conjunto sin duplicados (columna `found_in_dbs`) |

Esquema común de columnas: `source_db`, `query_language`, `title`, `abstract`,
`doi_clean`, `year`, `authors`, `journal`, `doc_type`, `language`, `uid`.

---

## Deduplicación

Coincidencia **exacta por DOI** (en minúsculas, con espacios recortados):

- Registros que comparten DOI: se conserva el que tiene el **resumen más largo**.
- `found_in_dbs` lista todas las bases que aportaron ese DOI.
- Registros sin DOI: se conservan tal cual — no se aplica comparación difusa.

---

*Estrategia basada en [Cortés & Quiroga (2023)](http://www.doi.org/10.3389/fcomm.2023.1226432)*
*Última actualización: junio 2026.*
