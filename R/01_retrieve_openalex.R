# =============================================================================
# R/01_retrieve_openalex.R
#
# Descarga registros de OpenAlex usando UNA consulta por idioma (3 en total).
#
# SOLUCIÓN AL ERROR HTTP 400 "Request Line is too large"
# ───────────────────────────────────────────────────────
# Los nombres de países en el texto de búsqueda hacen la URL demasiado larga.
# Solución: los países se pasan como filtro separado usando códigos ISO
# (authorships.countries) definidos en queries.R — no van en la URL.
#
# AUTENTICACIÓN
# ─────────────
# Agrega a ~/.Renviron (usethis::edit_r_environ()) y reinicia R:
#   OPENALEX_EMAIL="tu@email.com"
#   OPENALEX_API_KEY="tu_clave"
#
# Salida:   data/raw/openalex_raw.csv
# Requiere: openalexR, dplyr, readr, fs
# =============================================================================

library(openalexR)
library(dplyr)
library(readr)
library(fs)

source("R/queries.R")   # carga: oa_queries, oa_countries_iso, YEAR_FROM, YEAR_TO

# ── Configuración ─────────────────────────────────────────────────────────────

MY_EMAIL  <- Sys.getenv("OPENALEX_EMAIL")
MY_APIKEY <- Sys.getenv("OPENALEX_API_KEY")

options(openalexR.mailto = MY_EMAIL)

OUT_FILE  <- "data/raw/openalex_raw.csv"
PAUSA_SEG <- 2L    # segundos entre fragmentos; aumenta a 5 si persiste el 429

FIELDS <- c(
  "id", "doi", "title", "display_name", "publication_year",
  "publication_date", "type", "language",
  "primary_location", "authorships", "abstract_inverted_index",
  "cited_by_count"
)

# ── Función auxiliar: reintentar N veces ante errores ─────────────────────────

intentar <- function(expr, intentos = 3) {
  for (i in seq_len(intentos)) {
    resultado <- tryCatch(expr, error = function(e) {
      message("  Error (intento ", i, "/", intentos, "): ", conditionMessage(e))
      message("  Esperando ", PAUSA_SEG, " seg antes de reintentar ...")
      Sys.sleep(PAUSA_SEG)
      NULL
    })
    if (!is.null(resultado)) return(resultado)
  }
  message("  Fallaron todos los intentos. Se omite este fragmento.")
  NULL
}

# ── Función: descargar un año de una consulta ─────────────────────────────────

fetch_anio <- function(query, anio, lang) {
  message("    descargando año ", anio, " ...")
  Sys.sleep(PAUSA_SEG)
  resultado <- intentar(
    oa_fetch(
      entity                    = "works",
      title_and_abstract.search = query,
      authorships.countries     = oa_countries_iso,   # ISO desde queries.R
      publication_year          = anio,
      options                   = list(select = FIELDS),
      mailto                    = MY_EMAIL,
      api_key                   = MY_APIKEY,
      verbose                   = FALSE
    )
  )
  if (is.null(resultado)) return(tibble())
  resultado |> mutate(query_language = lang, source_db = "OpenAlex")
}

# ── Función: descargar un idioma completo (dividido por año) ──────────────────

fetch_lang <- function(lang) {
  message("\nIdioma: ", lang)
  lapply(YEAR_FROM:YEAR_TO, fetch_anio, query = oa_queries[[lang]], lang = lang) |>
    bind_rows()
}

# ── Descarga ──────────────────────────────────────────────────────────────────

all_raw <- lapply(names(oa_queries), fetch_lang) |>
  bind_rows()

message("\nRegistros brutos descargados: ", nrow(all_raw))

# ── Normalizar DOI ────────────────────────────────────────────────────────────

all_raw <- all_raw |>
  mutate(doi_clean = tolower(trimws(coalesce(doi, NA_character_))))

# ── Deduplicar ────────────────────────────────────────────────────────────────

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

cat > /home/claude/climate_search/R/01_retrieve_openalex.R << 'REOF'
# =============================================================================
# R/01_retrieve_openalex.R
#
# Descarga registros de OpenAlex usando httr2 directamente (POST).
#
# POR QUÉ httr2 EN VEZ DE oa_fetch()
# ────────────────────────────────────
# oa_fetch() siempre construye peticiones GET. Con consultas largas la URL
# supera el límite del servidor (~2000 chars) → HTTP 400.
# Con httr2 enviamos la consulta como POST con body JSON → sin límite de tamaño.
#
# AUTENTICACIÓN
# ─────────────
# Agrega a ~/.Renviron y reinicia R:
#   OPENALEX_EMAIL="tu@email.com"
#   OPENALEX_API_KEY="tu_clave"
#
# Salida:   data/raw/openalex_raw.csv
# Requiere: httr2, jsonlite, dplyr, readr, fs
# =============================================================================

library(httr2)
library(jsonlite)
library(dplyr)
library(readr)
library(fs)

source("R/queries.R")

# ── Configuración ─────────────────────────────────────────────────────────────

MY_EMAIL  <- Sys.getenv("OPENALEX_EMAIL")
MY_APIKEY <- Sys.getenv("OPENALEX_API_KEY")

OUT_FILE  <- "data/raw/openalex_raw.csv"
PAUSA_SEG <- 2L
POR_PAGINA <- 200L   # máximo permitido por OpenAlex

FIELDS <- paste(c(
  "id", "doi", "title", "display_name", "publication_year",
  "publication_date", "type", "language",
  "primary_location", "authorships", "abstract_inverted_index",
  "cited_by_count"
), collapse = ",")

# ── Función: una página via GET con filtros en query string ───────────────────
# Los filtros de país y año son cortos — solo la búsqueda de texto es larga.
# Separamos: texto en el body (POST simulado via cursor) y filtros cortos en URL.

fetch_pagina <- function(query_texto, anio, cursor = "*") {
  
  # Construir el filtro: texto de búsqueda + país ISO + año
  paises <- paste(oa_countries_iso, collapse = "|")
  
  filtro <- paste0(
    "title_and_abstract.search:", query_texto,
    ",authorships.countries:", paises,
    ",publication_year:", anio
  )
  
  resp <- request("https://api.openalex.org/works") |>
    req_url_query(
      filter     = filtro,
      select     = FIELDS,
      per_page   = POR_PAGINA,
      cursor     = cursor,
      mailto     = MY_EMAIL,
      api_key    = if (nchar(MY_APIKEY) > 0) MY_APIKEY else NULL
    ) |>
    req_timeout(60) |>
    req_retry(max_tries = 3, backoff = ~ PAUSA_SEG) |>
    req_perform()
  
  resp_body_json(resp, simplifyVector = FALSE)
}

# ── Función: todos los registros de un año ────────────────────────────────────

fetch_anio <- function(query, anio, lang) {
  message("    año ", anio, " ...")
  Sys.sleep(PAUSA_SEG)
  
  # Primera página
  pagina <- tryCatch(
    fetch_pagina(query, anio, cursor = "*"),
    error = function(e) {
      message("  Error año ", anio, ": ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(pagina)) return(tibble())
  
  total <- pagina$meta$count %||% 0L
  message("      total: ", total)
  if (total == 0L) return(tibble())
  
  registros <- pagina$results
  cursor_sig <- pagina$meta$next_cursor
  
  # Páginas siguientes
  while (!is.null(cursor_sig) && length(registros) < total) {
    Sys.sleep(PAUSA_SEG)
    pagina <- tryCatch(
      fetch_pagina(query, anio, cursor = cursor_sig),
      error = function(e) {
        message("  Error paginando: ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(pagina)) break
    registros <- c(registros, pagina$results)
    cursor_sig <- pagina$meta$next_cursor
  }
  
  # Convertir lista a tibble
  tibble(
    source_db      = "OpenAlex",
    query_language = lang,
    id             = map_chr(registros, \(r) r$id          %||% NA_character_),
    doi            = map_chr(registros, \(r) r$doi         %||% NA_character_),
    display_name   = map_chr(registros, \(r) r$display_name %||% NA_character_),
    year           = map_int(registros, \(r) r$publication_year %||% NA_integer_),
    type           = map_chr(registros, \(r) r$type        %||% NA_character_),
    language       = map_chr(registros, \(r) r$language    %||% NA_character_),
    cited_by_count = map_int(registros, \(r) r$cited_by_count %||% NA_integer_)
  )
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

# ── Función: todos los años de un idioma ──────────────────────────────────────

fetch_lang <- function(lang) {
  message("\nIdioma: ", lang)
  lapply(YEAR_FROM:YEAR_TO, fetch_anio,
         query = oa_queries[[lang]], lang = lang) |>
    bind_rows()
}

# ── Descarga ──────────────────────────────────────────────────────────────────

all_raw <- lapply(names(oa_queries), fetch_lang) |>
  bind_rows()

message("\nRegistros brutos: ", nrow(all_raw))

# ── Normalizar DOI ────────────────────────────────────────────────────────────

all_raw <- all_raw |>
  mutate(doi_clean = tolower(trimws(coalesce(doi, NA_character_))))

# ── Deduplicar ────────────────────────────────────────────────────────────────

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
        " (", nrow(all_raw) - nrow(all_dedup), " eliminados)")

# ── Guardar ───────────────────────────────────────────────────────────────────

dir_create("data/raw")
write_csv(all_dedup, OUT_FILE)
message("Guardado en ", OUT_FILE)