# =============================================================================
# R/queries.R
# Búsquedas Booleanas para OpenAlex, WoS y Scopus
#
# -----------------------------------------------------------------------------
# IDEA CENTRAL
#   Las TRES bases usan las MISMAS listas de conceptos (definidas una sola vez
#   abajo). La lógica es idéntica en las tres:
#
#       (clima) AND (adaptación) AND (urbano) AND (países)
#
#   Lo único que cambia es la sintaxis que envuelve esos bloques según el motor:
#       OpenAlex -> title_and_abstract.search   (el año va aparte, en oa_fetch)
#       WoS      -> TS=( ... )                   + PY=(2021-2025)
#       Scopus   -> TITLE-ABS-KEY( ... )         + PUBYEAR > 2020 AND < 2026
#
# -----------------------------------------------------------------------------
# CÓMO EDITAR
#   Edita solo las listas de conceptos (climate_*, adaptation_*, urban_*,
#   countries_*). Cada coma dentro de una lista significa OR; las cuatro listas
#   se unen con AND. Las consultas de las 3 bases se arman solas más abajo.
#
#   * Términos de varias palabras ("cambio climático") -> frase exacta (comillas)
#   * Palabras sueltas (urbano) y comodines (adapt*)    -> sin comillas
#
# DOS DIFERENCIAS ENTRE MOTORES (importantes al comparar resultados)
#   1) Alcance del campo: OpenAlex busca solo en título + resumen; WoS (TS=) y
#      Scopus (TITLE-ABS-KEY) además incluyen palabras clave -> pueden traer algo
#      más.
#   2) Comodín adapt*: en WoS y Scopus el "*" trunca (adapt, adaptation,
#      adaptación, adaptive...). OpenAlex NO trunca con "*": aplica lematización
#      sobre la raíz. En la práctica recuperan lo mismo, pero pueden diferir un
#      poco. Si quieres comportamiento idéntico, reemplaza "adapt*" por variantes
#      explícitas en cada idioma.
# =============================================================================


# ── Funciones auxiliares ──────────────────────────────────────────────────────

# Une un vector de términos en "A OR B OR C" (por defecto entre comillas).
or_string <- function(terms, quote = TRUE) {
  if (quote) terms <- paste0('"', terms, '"')
  paste(terms, collapse = " OR ")
}

# Convierte UNA lista de conceptos en un grupo entre paréntesis: (a OR b ...).
# Los términos de varias palabras van entre comillas (frase exacta); las
# palabras sueltas y los comodines quedan sin comillas.
concept_block <- function(terms) {
  quoted <- ifelse(grepl(" ", terms), paste0('"', terms, '"'), terms)
  paste0("(", paste(quoted, collapse = " OR "), ")")
}

# Une varios bloques de conceptos con AND.
all_of <- function(...) paste(c(...), collapse = " AND ")

# "x o por defecto y": devuelve x salvo que sea NULL o de largo 0.
# (Lo usan 01/02/03 al leer campos que a veces no vienen.)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# Devuelve la columna 'name' si existe en df; si no, un marcador NA.
# Mantiene robustos los transmute() frente a campos que la API no devuelve.
col_or_na <- function(df, name, na = NA_character_) {
  if (name %in% names(df)) df[[name]] else na
}


# ── Años ──────────────────────────────────────────────────────────────────────
# Ventana temporal de la búsqueda (inclusiva)

YEAR_FROM <- 2021L
YEAR_TO   <- 2025L


# ── Países ──────────────────────────────────────────────────────────────────
# Países en español/inglés/portugués, con y sin acento.
countries_en <- c(
  "Argentina", "Bolivia", "Brazil", "Brasil", "Chile", "Colombia",
  "Ecuador", "Guyana", "Paraguay", "Peru", "Suriname", "Uruguay",
  "Venezuela", "Belize", "Costa Rica", "El Salvador", "Guatemala",
  "Honduras", "Mexico", "México", "Nicaragua", "Panama", "Panamá"
)
countries_es <- c(
  "Argentina", "Bolivia", "Brasil", "Chile", "Colombia", "Ecuador",
  "Guyana", "Paraguay", "Perú", "Suriname", "Uruguay", "Venezuela",
  "Belice", "Costa Rica", "El Salvador", "Guatemala", "Honduras",
  "México", "Nicaragua", "Panamá"
)
countries_pt <- c(
  "Argentina", "Bolívia", "Bolivia", "Brasil", "Chile", "Colômbia",
  "Colombia", "Equador", "Ecuador", "Guiana", "Guyana", "Paraguai",
  "Paraguay", "Peru", "Suriname", "Uruguai", "Uruguay", "Venezuela",
  "Belize", "Costa Rica", "El Salvador", "Guatemala", "Honduras",
  "México", "Nicarágua", "Nicaragua", "Panamá"
)


# ── Lista de conceptos: INGLÉS ──────────────────────────────────────────────────
climate_en <- c(
  "climate change",
  "global change",
  "climate emergency",
  "climate crisis",
  "global warming"
)

adaptation_en <- c(
  "adapt*"               # adapt, adapts, adaptation, adaptive (ver nota del encabezado)
  # , "resilience"       # <- ejemplo: agrega más términos de adaptación aquí
  # , "coping strategy"
)

urban_en <- c(
  "built environment",
  "biodiversity",
  "urban",
  "city",
  "cities",
  "smart city",
  "urban planning",
  "urban resilience",
  "urban heat",
  "land use",
  "disaster",
  "early warning system"
)


# ── Lista de conceptos: ESPAÑOL ─────────────────────────────────────────────────
climate_es <- c(
  "cambio climático",
  "cambio global",
  "emergencia climática",
  "crisis climática",
  "calentamiento global"
)

adaptation_es <- c(
  "adapt*"               # adaptar, adaptación, adaptativo, ...
)

urban_es <- c(
  "ambiente construido",
  "entorno construido",
  "biodiversidad",
  "urbano",
  "ciudad",
  "ciudad inteligente",
  "planificación urbana",
  "resiliencia urbana",
  "calor urbano",
  "uso del suelo",
  "desastre",
  "alerta temprana"
)


# ── Lista de conceptos: PORTUGUÉS ───────────────────────────────────────────────
climate_pt <- c(
  "mudança climática",
  "alteração climática",
  "mudança global",
  "emergência climática",
  "crise climática",
  "aquecimento global"
)

adaptation_pt <- c(
  "adapt*"               # adaptar, adaptação, adaptativo, ...
)

urban_pt <- c(
  "ambiente construído",
  "biodiversidade",
  "urbano",
  "cidade",
  "cidades",
  "cidade inteligente",
  "planejamento urbano",
  "planeamento urbano",
  "resiliência urbana",
  "calor urbano",
  "uso do solo",
  "uso da terra",
  "desastre",
  "alerta precoce",
  "alerta antecipada"
)


# ── Consulta Booleana: OpenAlex ─────────────────────────────────────────────────
# (clima) AND (adaptación) AND (urbano) AND (países).
# El año NO va en esta cadena: se pasa como filtro en oa_fetch()

oa_queries <- list(
  english = all_of(
    concept_block(climate_en),
    concept_block(adaptation_en),
    concept_block(urban_en),
    paste0("(", or_string(countries_en), ")")   # países siempre entre comillas
  ),
  spanish = all_of(
    concept_block(climate_es),
    concept_block(adaptation_es),
    concept_block(urban_es),
    paste0("(", or_string(countries_es), ")")
  ),
  portuguese = all_of(
    concept_block(climate_pt),
    concept_block(adaptation_pt),
    concept_block(urban_pt),
    paste0("(", or_string(countries_pt), ")")
  )
)


# ── Consulta Booleana: Web of Science ───────────────────────────────────────────
# Cada bloque va dentro de su propio TS=( ). En WoS la precedencia es
# NEAR > SAME > NOT > AND > OR, por eso cada bloque conceptual va entre paréntesis.
build_wos_query <- function(climate_terms, adaptation_terms, urban_terms, country_terms) {
  glue::glue(
    "TS=({concept_block(climate_terms)}) ",
    "AND TS=({concept_block(adaptation_terms)}) ",
    "AND TS=({concept_block(urban_terms)}) ",
    "AND TS=({paste0('(', or_string(country_terms), ')')}) ",
    "AND PY=({YEAR_FROM}-{YEAR_TO})"
  )
}

wos_queries <- list(
  english    = build_wos_query(climate_en, adaptation_en, urban_en, countries_en),
  spanish    = build_wos_query(climate_es, adaptation_es, urban_es, countries_es),
  portuguese = build_wos_query(climate_pt, adaptation_pt, urban_pt, countries_pt)
)


# ── Consulta Booleana: Scopus ───────────────────────────────────────────────────
# TITLE-ABS-KEY equivale al alcance de TS= en WoS (título + resumen + keywords).
# Usa field = "TITLE-ABS" si quieres excluir las palabras clave.
# PUBYEAR usa > y < estrictos (no existe >=): por eso YEAR_FROM-1 y YEAR_TO+1
# dan el rango inclusivo 2021–2025.
build_scopus_query <- function(climate_terms, adaptation_terms, urban_terms, country_terms,
                               field = "TITLE-ABS-KEY") {
  glue::glue(
    "{field}({concept_block(climate_terms)}) ",
    "AND {field}({concept_block(adaptation_terms)}) ",
    "AND {field}({concept_block(urban_terms)}) ",
    "AND {field}({paste0('(', or_string(country_terms), ')')}) ",
    "AND PUBYEAR > {YEAR_FROM - 1L} AND PUBYEAR < {YEAR_TO + 1L}"
  )
}

scopus_queries <- list(
  english    = build_scopus_query(climate_en, adaptation_en, urban_en, countries_en),
  spanish    = build_scopus_query(climate_es, adaptation_es, urban_es, countries_es),
  portuguese = build_scopus_query(climate_pt, adaptation_pt, urban_pt, countries_pt)
)

