# =============================================================================
# R/03_retrieve_scopus.R
#
# Busca trabajos en la base de datos de Elsevier
# Se necesita el paquete rscopus (CRAN) y una Elsevier API key.
#
# Configuración
# 1. Ir a  https://dev.elsevier.com/user/signin y solicitar una API key
# 2. Agregrar a  ~/.Renviron (usando usethis::edit_r_environ()):
#      Elsevier_API="your_key_here"
#    Restart R after saving.
# ⚠️ La API key está atada a la IP de la institución
#    Hay que hacerlo en la institución registrada (por ejemplo campus)
#
# Límite: ~5000 registro por query
#
# Salida: data/raw/scopus_raw.csv
# =============================================================================

library(rscopus)
library(dplyr)
library(readr)
library(purrr)
library(cli)
library(fs)
library(glue)

source("R/queries.R")

# Configuración años ------------------------------------------------------

YEAR_FROM <- 2021L
YEAR_TO   <- 2025L
OUT_FILE  <- "data/raw/scopus_raw.csv"
MAX_COUNT <- 5000L
# Api key -----------------------------------------------------------------


cli_h1("Scopus API")

if (!have_api_key()) {
  stop(
    "Elsevier_API no encontrado en in ~/.Renviron.\n"
  )
}

cli_alert_warning("Asegúrate de estar conectado a la red de la institución, la clave está vinculada a la dirección IP")

# Llamada -----------------------------------------------------------------

fetch_scopus <- function(query, lang_label) {
  cli_h2("Idioma: {lang_label}")
  cli_alert_info("Query (truncated): {substr(query, 1, 120)}...")

  tryCatch({
    res   <- scopus_search(query = query, max_count = MAX_COUNT,
                           count = 25L, verbose = FALSE)
    total <- as.integer(res$total_results %||% 0L)
    cli_alert_info("Total: {total}")

    if (total == 0L) {
      cli_alert_warning("Sin resultados")
      return(tibble())
    }

    if (total > MAX_COUNT) {
      cli_alert_warning(
        "{total} trabajos, el máximo {MAX_COUNT} se alcanzó",
      )
    }

    entries <- res$entries
    if (is.null(entries) || length(entries) == 0) return(tibble())

    records <- map_dfr(entries, \(e) tibble(
      title    = e[["dc:title"]]              %||% NA_character_,
      abstract = e[["dc:description"]]        %||% NA_character_,
      doi      = e[["prism:doi"]]             %||% NA_character_,
      year     = e[["prism:coverDate"]]       %||% NA_character_,
      authors  = e[["dc:creator"]]            %||% NA_character_,
      journal  = e[["prism:publicationName"]] %||% NA_character_,
      doc_type = e[["subtypeDescription"]]    %||% NA_character_,
      language = e[["dc:language"]]           %||% NA_character_,
      uid      = e[["dc:identifier"]]         %||% NA_character_
    ))

    cli_alert_success("{nrow(records)} encontrados")

    records |>
      transmute(
        source_db      = "Scopus",
        query_language = lang_label,
        title,
        abstract,
        doi_clean = tolower(trimws(coalesce(doi, NA_character_))),
        year      = suppressWarnings(as.integer(substr(coalesce(year, ""), 1, 4))),
        authors,
        journal,
        doc_type,
        language,
        uid
      )

  }, error = function(e) {
    cli_alert_danger("Error: {e$message}")
    tibble()
  })
}

results_list <- imap(scopus_queries, fetch_scopus)
all_raw      <- bind_rows(results_list)

cli_alert_info("Total: {nrow(all_raw)}")

# Eliminar duplicados -----------------------------------------------------

has_doi <- all_raw |> filter(!is.na(doi_clean) & doi_clean != "" & doi_clean != "na")
no_doi  <- all_raw |> filter(is.na(doi_clean)  | doi_clean == "" | doi_clean == "na")

scopus_dedup <- bind_rows(
  has_doi |> arrange(doi_clean) |> distinct(doi_clean, .keep_all = TRUE),
  no_doi  |> distinct(uid, .keep_all = TRUE)
)

cli_alert_success(
  "Despúes de eliminar duplicados: {nrow(scopus_dedup)} ({nrow(all_raw) - nrow(scopus_dedup)} eliminados)"
)

dir_create("data/raw")
write_csv(scopus_dedup, OUT_FILE)
cli_alert_success("Guardar en {OUT_FILE}")
