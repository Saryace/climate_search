# =============================================================================
# R/01_retrieve_openalex.R
#
# Descarga registros de OpenAlex buscando países en título y resumen,
# igual que WoS y Scopus — para que los resultados sean comparables.
#
# ESTRATEGIA PARA EVITAR HTTP 400 Y 429
# ──────────────────────────────────────
# El problema: una consulta con (clima AND urbano AND 23 países) supera el
# límite de URL de OpenAlex (~2000 chars codificados) → HTTP 400.
# La solución: dividir por PAÍS. Cada llamada busca UN país a la vez:
#
#   (clima AND urbano) AND "Argentina"  → año 2021 ... 2025
#   (clima AND urbano) AND "Bolivia"    → año 2021 ... 2025
#   ...
#
# Cada URL mide < 500 chars. Se agregan pausas entre llamadas → sin 429.
# La deduplicación por DOI al final elimina registros repetidos entre países.
#
# AUTENTICACIÓN
# ─────────────
# Agrega a ~/.Renviron y reinicia R:
#   OPENALEX_EMAIL="tu@email.com"
#   OPENALEX_API_KEY="tu_clave"   # opcional, aumenta límites
#
# Salida:   data/raw/openalex_raw.csv
# Requiere: openalexR, dplyr, readr, fs
# =============================================================================

library(openalexR)
library(dplyr)
library(readr)
library(fs)

source("R/queries.R")

# ── Configuración ─────────────────────────────────────────────────────────────

MY_EMAIL  <- Sys.getenv("OPENALEX_EMAIL")
MY_APIKEY <- Sys.getenv("OPENALEX_API_KEY")

if (nchar(MY_EMAIL) == 0) {
  stop(
    "OPENALEX_EMAIL no está configurado.\n",
    "Agrega a ~/.Renviron (usethis::edit_r_environ()) y reinicia R:\n",
    '  OPENALEX_EMAIL="tu@email.com"'
  )
}

options(openalexR.mailto = MY_EMAIL)

OUT_FILE  <- "data/raw/openalex_raw.csv"
PAUSA_SEG <- 10L   # segundos entre llamadas — aumenta a 5 si reaparece el 429

FIELDS <- c(
  "id", "doi", "title", "display_name", "publication_year",
  "publication_date", "type", "language",
  "primary_location", "authorships", "abstract_inverted_index",
  "cited_by_count"
)

# ── Construir combinaciones: consulta base × país × año ───────────────────────
# Cada fila es una llamada a la API — URL corta, sin 400.

combinaciones <- bind_rows(
  tidyr::crossing(
    lang    = "english",
    base    = oa_queries[["english"]],
    pais    = countries_en,
    anio    = YEAR_FROM:YEAR_TO
  ),
  tidyr::crossing(
    lang    = "spanish",
    base    = oa_queries[["spanish"]],
    pais    = countries_es,
    anio    = YEAR_FROM:YEAR_TO
  ),
  tidyr::crossing(
    lang    = "portuguese",
    base    = oa_queries[["portuguese"]],
    pais    = countries_pt,
    anio    = YEAR_FROM:YEAR_TO
  )
)

message("Total de combinaciones a consultar: ", nrow(combinaciones),
        " (≈ ", round(nrow(combinaciones) * PAUSA_SEG / 60, 1), " min)")

# ── Función: una llamada (consulta + país + año) ──────────────────────────────

fetch_uno <- function(base, pais, anio, lang) {
  # Construir consulta corta: (clima AND urbano) AND "País"
  query <- paste0(base, ' AND "', pais, '"')
  
  Sys.sleep(PAUSA_SEG)
  
  res <- tryCatch(
    oa_fetch(
      entity                    = "works",
      title_and_abstract.search = query,
      publication_year          = anio,
      options                   = list(select = FIELDS),
      mailto                    = MY_EMAIL,
      api_key                   = if (nchar(MY_APIKEY) > 0) MY_APIKEY else NULL,
      verbose                   = FALSE
    ),
    error = function(e) {
      message("  Error [", lang, " | ", pais, " | ", anio, "]: ",
              conditionMessage(e))
      NULL
    }
  )
  
  if (is.null(res) || nrow(res) == 0) return(tibble())
  
  res |> mutate(
    query_language = lang,
    source_db      = "OpenAlex",
    pais_consulta  = pais
  )
}

# ── Descarga ──────────────────────────────────────────────────────────────────

message("\nIniciando descarga ...")

results_list <- purrr::pmap(
  combinaciones,
  function(lang, base, pais, anio) {
    message("  ", lang, " | ", pais, " | ", anio)
    fetch_uno(base, pais, anio, lang)
  }
)

all_raw <- bind_rows(results_list)
message("\nRegistros brutos descargados: ", nrow(all_raw))

# ── Aplanar columnas anidadas ─────────────────────────────────────────────────
# openalexR devuelve columnas-lista (p.ej. author, primary_location) que
# write_csv no sabe serializar. Aplanamos 'author' a texto y descartamos
# cualquier otra columna-lista restante para que el CSV se escriba bien.

if ("author" %in% names(all_raw)) {
  all_raw$author <- vapply(all_raw$author, function(a) {
    if (is.null(a) || !is.data.frame(a) || !"au_display_name" %in% names(a)) {
      return(NA_character_)
    }
    paste(a$au_display_name, collapse = "; ")
  }, character(1))
}

list_cols <- names(all_raw)[vapply(all_raw, is.list, logical(1))]
if (length(list_cols) > 0) {
  message("Descartando columnas-lista no serializables: ",
          paste(list_cols, collapse = ", "))
  all_raw <- all_raw |> select(-all_of(list_cols))
}

# ── Normalizar DOI ────────────────────────────────────────────────────────────

all_raw <- all_raw |>
  mutate(doi_clean = tolower(trimws(coalesce(doi, NA_character_))))

# ── Deduplicar (muchos registros aparecen en varios países) ──────────────────

has_doi <- all_raw |> filter(!is.na(doi_clean) & doi_clean != "")
no_doi  <- all_raw |> filter(is.na(doi_clean)  | doi_clean == "")

all_dedup <- bind_rows(
  has_doi |> arrange(doi_clean) |> distinct(doi_clean, .keep_all = TRUE),
  no_doi  |>
    mutate(title_norm = tolower(trimws(coalesce(display_name, "")))) |>
    distinct(title_norm, .keep_all = TRUE) |>
    select(-title_norm)
)

message("Tras deduplicación: ", nrow(all_dedup),
        " registros (", nrow(all_raw) - nrow(all_dedup), " eliminados)")

# ── Guardar ───────────────────────────────────────────────────────────────────

dir_create("data/raw")
write_csv(all_dedup, OUT_FILE)
message("Guardado en ", OUT_FILE)