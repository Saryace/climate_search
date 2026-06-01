# =============================================================================
# R/queries.R
# Búsquedas Booleanas para OpenAlex, WOS y Scopus
#
# -----------------------------------------------------------------------------
# CÓMO EDITAR 
#     Cada búsqueda se arma a partir de una lista de conceptos por idea
#
#         climate_*     -> términos de cambio climático
#         adaptation_*  -> términos de adaptación
#         urban_*       -> términos urbanos / ambiente / amenazas
#         countries_*   -> los países que se quieren conservar
#
#     Cada coma dentro de una lista significa "OR" y las cuatro LISTAS se unen
#     con AND.
#
#     OTROS:
#   * Los términos de varias palabras (p. ej. "cambio climático") se buscan como
#     frase exacta.
#   * Las palabras sueltas (p. ej. urbano) y los comodines (p. ej. adapt*) se
#     dejan SIN comillas para que la base de datos pueda expandirlos 
# =============================================================================

# Función que une los términos

or_string <- function(terms, quote = TRUE) {
  if (quote) terms <- paste0('"', terms, '"')
  paste(terms, collapse = " OR ")
}

# Función que pone comillas entre OR
concept_block <- function(terms) {
  quoted <- ifelse(grepl(" ", terms), paste0('"', terms, '"'), terms)
  paste0("(", paste(quoted, collapse = " OR "), ")")
}

# Une las listas de conceptos con AND.
all_of <- function(...) paste(c(...), collapse = " AND ")


# Años --------------------------------------------------------------------



# Paises ------------------------------------------------------------------
# Paises en español con y sin acento

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



# Lista de conceptos en inglés --------------------------------------------

climate_en <- c(
  "climate change",
  "global change",
  "climate emergency",
  "climate crisis",
  "global warming"
)

adaptation_en <- c(
  "adapt*"               # coincide con adapt, adapts, adaptation, adaptive,
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

# Lista conceptos en español ----------------------------------------------

climate_es <- c(
  "cambio climático",
  "cambio global",
  "emergencia climática",
  "crisis climática",
  "calentamiento global"
)

adaptation_es <- c(
  "adapt*"               # coincide con adaptar, adaptación, adaptativo, ...
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

# Lista conceptos PT ------------------------------------------------------

climate_pt <- c(
  "mudança climática",
  "alteração climática",
  "mudança global",
  "emergência climática",
  "crise climática",
  "aquecimento global"
)

adaptation_pt <- c(
  "adapt*"               # coincide con adaptar, adaptação, adaptativo, ...
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


# Consulta Booleana para OpenAlex -----------------------------------------
# Cada consulta = (clima) AND (adaptación) AND (urbano) AND (países).

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

# Consulta Booleana para WOS ----------------------------------------------
# # En WOS los operadores tienen prioridad (OR se evalúa después de AND)
# Por ello, cada bloque conceptual debe ir entre paréntesis

# Consulta Booleana para OpenAlex -----------------------------------------
# Cada consulta = (clima) AND (adaptación) AND (urbano) AND (países).

oa_queries <- list(
  english = all_of(
    concept_block(climate_en),
    concept_block(adaptation_en),
    concept_block(urban_en),
    paste0("(", or_string(countries_en), ")")
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

# Consulta Booleana para Web of Science -----------------------------------
# IMPORTANTE: cada bloque va con paréntesis.
# En WoS la precedencia es NEAR/x > SAME > NOT > AND > OR.
# Sin paréntesis, los OR pueden expandir demasiado la búsqueda.

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
  english = build_wos_query(
    climate_terms    = climate_en,
    adaptation_terms = adaptation_en,
    urban_terms      = urban_en,
    country_terms    = countries_en
  ),
  spanish = build_wos_query(
    climate_terms    = climate_es,
    adaptation_terms = adaptation_es,
    urban_terms      = urban_es,
    country_terms    = countries_es
  ),
  portuguese = build_wos_query(
    climate_terms    = climate_pt,
    adaptation_terms = adaptation_pt,
    urban_terms      = urban_pt,
    country_terms    = countries_pt
  )
)

# Consulta Booleana para Scopus -------------------------------------------
# En Scopus los (*) SÍ funcionan dentro de comillas dobles, y cada bloque 
# puede ir en su propio campo
# PUBYEAR usa > y < estrictos (no existe >=): por eso YEAR_FROM-1 y YEAR_TO+1
# dan el rango inclusivo 2021–2025.
# field = "TITLE-ABS-KEY" equivale al alcance del TS= de WoS (título + resumen
# + palabras clave). Se puede usar field = "TITLE-ABS" si quieres excluir las keywords.

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
  english = build_scopus_query(
    climate_terms    = climate_en,
    adaptation_terms = adaptation_en,
    urban_terms      = urban_en,
    country_terms    = countries_en
  ),
  spanish = build_scopus_query(
    climate_terms    = climate_es,
    adaptation_terms = adaptation_es,
    urban_terms      = urban_es,
    country_terms    = countries_es
  ),
  portuguese = build_scopus_query(
    climate_terms    = climate_pt,
    adaptation_terms = adaptation_pt,
    urban_terms      = urban_pt,
    country_terms    = countries_pt
  )
)

