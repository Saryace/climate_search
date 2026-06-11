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
#       OpenAlex -> title_and_abstract.search   (países van como filtro ISO)
#       WoS      -> TS=( ... )                   + PY=(2021-2025)
#       Scopus   -> TITLE-ABS-KEY( ... )         + PUBYEAR > 2020 AND < 2026
#
# -----------------------------------------------------------------------------
# CÓMO EDITAR
#   Edita solo las listas de conceptos (climate_*, adaptation_*, urban_*).
#   Cada elemento dentro de una lista significa OR; las cuatro listas
#   se unen con AND. Las consultas de las 3 bases se arman solas más abajo.
#
#   * Términos de varias palabras ("cambio climático") -> frase exacta
#   * Palabras sueltas (urbano) y comodines (adapt*)   -> sin comillas
#
# DOS DIFERENCIAS ENTRE MOTORES
#   1) Alcance del campo: OpenAlex busca solo en título + resumen; WoS (TS=) y
#      Scopus (TITLE-ABS-KEY) además incluyen palabras clave.
#   2) Comodín adapt*: en WoS y Scopus trunca normalmente. OpenAlex aplica
#      lematización, por lo que tiene los términos de adaptación sin *
# =============================================================================

# ── Años ──────────────────────────────────────────────────────────────────────

YEAR_FROM <- 2021L
YEAR_TO   <- 2025L

# ── Funciones auxiliares ──────────────────────────────────────────────────────

# Colapsa un vector de términos en un bloque OR entre paréntesis.
# Los términos de más de una palabra se envuelven en comillas automáticamente.
concept_block <- function(terms) {
  terms_quoted <- ifelse(
    grepl(" ", terms) & !grepl('^"', terms),
    paste0('"', terms, '"'),
    terms
  )
  paste0("(", paste(terms_quoted, collapse = " OR "), ")")
}

# Arma la consulta completa uniendo bloques con AND
and_query <- function(...) {
  paste(list(...), collapse = " AND ")
}

# Colapsa un vector en una cadena OR entre comillas (para listas de países)
or_string <- function(terms, quote = TRUE) {
  if (quote) terms <- paste0('"', terms, '"')
  paste(terms, collapse = " OR ")
}

# ── Países ────────────────────────────────────────────────────────────────────

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

# ── Listas de conceptos: INGLÉS ───────────────────────────────────────────────

climate_en <- c(
  "climate change",
  "global change",
  "climate crisis",
  "global warming"
)

adaptation_en <- c(
  "adapt*"
  # , "resilience"        # <- agrega más términos aquí si es necesario, WoS y Scopus
  # , "coping strategy"
)

adaptation_oa_en <- c("adaptation", "adaptive", "adapting", "adapt")

urban_en <- c(
  "built environment",
  "biodiversity",
  "smart city",
  "urban planning",
  "urban resilience",
  "disaster",
  "early warning system"
)

# ── Listas de conceptos: ESPAÑOL ─────────────────────────────────────────────

climate_es <- c(
  "cambio climático",
  "cambio global",
  "crisis climática",
  "calentamiento global"
)

adaptation_es <- c(
  "adapt*"
)

adaptation_oa_es <- c("adaptación", "adaptativo", "adaptarse", "adaptar")

urban_es <- c(
  "ambiente construido",
  "entorno construido",
  "biodiversidad",
  "ciudad inteligente",
  "planificación urbana",
  "resiliencia urbana",
  "calor urbano",
  "desastre",
  "alerta temprana"
)

# ── Listas de conceptos: PORTUGUÉS ───────────────────────────────────────────

climate_pt <- c(
  "mudança climática",
  "alteração climática",
  "mudança global",
  "crise climática",
  "aquecimento global"
)

adaptation_pt <- c(
  "adapt*"
)

adaptation_oa_pt <- c("adaptação", "adaptativo", "adaptar")

urban_pt <- c(
  "ambiente construído",
  "biodiversidade",
  "cidade inteligente",
  "planejamento urbano",
  "planeamento urbano",
  "resiliência urbana",
  "calor urbano",
  "desastre",
  "alerta precoce",
  "alerta antecipada"
)

# ── Consultas OpenAlex ────────────────────────────────────────────────────────
# Países NO van aquí — se pasan aparte en 01_retrieve_openalex.R para no hacer
# que la URL de la llamada sea tan larga (tiene límite de caracteres)

oa_queries <- list(
  english = and_query(
    concept_block(climate_en),
    concept_block(adaptation_oa_en),
    concept_block(urban_en)
  ),
  spanish = and_query(
    concept_block(climate_es),
    concept_block(adaptation_oa_es),
    concept_block(urban_es)
  ),
  portuguese = and_query(
    concept_block(climate_pt),
    concept_block(adaptation_oa_pt),
    concept_block(urban_pt)
  )
)
# ── Consultas WoS ─────────────────────────────────────────────────────────────
# TS= busca en título + resumen + palabras clave
# Países van dentro de TS= como bloque OR de nombres completos

wos_queries <- list(
  english = paste0(
    "TS=(", and_query(
      concept_block(climate_en),
      concept_block(adaptation_en),
      concept_block(urban_en),
      paste0("(", or_string(countries_en), ")")
    ), ") AND PY=(", YEAR_FROM, "-", YEAR_TO, ")"
  ),
  spanish = paste0(
    "TS=(", and_query(
      concept_block(climate_es),
      concept_block(adaptation_es),
      concept_block(urban_es),
      paste0("(", or_string(countries_es), ")")
    ), ") AND PY=(", YEAR_FROM, "-", YEAR_TO, ")"
  ),
  portuguese = paste0(
    "TS=(", and_query(
      concept_block(climate_pt),
      concept_block(adaptation_pt),
      concept_block(urban_pt),
      paste0("(", or_string(countries_pt), ")")
    ), ") AND PY=(", YEAR_FROM, "-", YEAR_TO, ")"
  )
)

# ── Consultas Scopus ──────────────────────────────────────────────────────────
# TITLE-ABS-KEY busca en título + resumen + palabras clave

scopus_queries <- list(
  english = paste0(
    "TITLE-ABS-KEY(", and_query(
      concept_block(climate_en),
      concept_block(adaptation_en),
      concept_block(urban_en),
      paste0("(", or_string(countries_en), ")")
    ), ") AND PUBYEAR > ", YEAR_FROM - 1L, " AND PUBYEAR < ", YEAR_TO + 1L
  ),
  spanish = paste0(
    "TITLE-ABS-KEY(", and_query(
      concept_block(climate_es),
      concept_block(adaptation_es),
      concept_block(urban_es),
      paste0("(", or_string(countries_es), ")")
    ), ") AND PUBYEAR > ", YEAR_FROM - 1L, " AND PUBYEAR < ", YEAR_TO + 1L
  ),
  portuguese = paste0(
    "TITLE-ABS-KEY(", and_query(
      concept_block(climate_pt),
      concept_block(adaptation_pt),
      concept_block(urban_pt),
      paste0("(", or_string(countries_pt), ")")
    ), ") AND PUBYEAR > ", YEAR_FROM - 1L, " AND PUBYEAR < ", YEAR_TO + 1L
  )
)
